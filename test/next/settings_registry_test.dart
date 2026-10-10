import 'dart:io';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as harness;
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/settings/application_settings.dart';
import 'package:nipaplay/next/settings/capability.dart';
import 'package:nipaplay/next/settings/denylist.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/player_abstraction/mdk_player_adapter.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/player_remote_control_bridge.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';

class SettingsPlayer extends Fake
    implements MdkPlayerAdapter, BufferingAwarePlayer, AsyncDisposablePlayer {
  final properties = <String, String>{};
  @override
  final buffering = ValueNotifier<bool>(false);
  @override
  Future<void> disposeAsync() async {}
  @override
  double volume = 1.0;
  @override
  double playbackRate = 1.0;
  @override
  PlayerPlaybackState state = PlayerPlaybackState.stopped;
  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(duration: 0, subtitle: [
        PlayerSubtitleStreamInfo(rawRepresentation: 'offline subtitle')
      ]);
  @override
  List<int> activeSubtitleTracks = [];
  @override
  List<int> activeAudioTracks = [];
  @override
  int get position => 0;
  @override
  int get bufferedPosition => 0;
  @override
  String? getProperty(String key) => properties[key];
  @override
  void setProperty(String key, String value) {
    properties[key] = value;
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {}
  @override
  List<String> getDecoders(PlayerMediaType type) => ['FFmpeg'];
  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) {}
  @override
  void setPlaybackRate(double rate) {
    playbackRate = rate;
  }

  @override
  void dispose() {}

  String get kernelName => 'MDK';
}

class _PlayingSettingsState extends VideoPlayerState {
  _PlayingSettingsState(super.suppliedPlayer) : super.forSettings();
  @override
  bool get hasVideo => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late SettingsRegistry registry;
  late harness.Harness api;
  late VideoPlayerState video;
  late SettingsProvider preferences;
  late CredentialStore previousCredentials;
  late MemoryVault vault;

  setUp(() async {
    sqfliteFfiInit();
    previousCredentials = CredentialStore.instance;
    vault = MemoryVault();
    CredentialStore.instance = CredentialStore(vault, desktop: true);
    root = await Directory.systemTemp.createTemp('nipa-settings-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path);
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    preferences = SettingsProvider();
    await preferences.ready;
    video = VideoPlayerState.forSettings(Player.withDelegate(SettingsPlayer()));
    registry = SettingsRegistry(db, ApplicationSettings.entries());
    SettingsAccess.registry = registry;
    ApplicationSettings.authorizePath =
        (path, {directory = false}) async => path;
    api = harness.Harness([SettingsCapability(registry)]);
  });

  tearDown(() async {
    video.dispose();
    preferences.dispose();
    await Future<void>.delayed(Duration.zero);
    await registry.drain();
    SettingsAccess.registry = null;
    ApplicationSettings.authorizePath = null;
    await db.close();
    await root.delete(recursive: true);
    CredentialStore.instance = previousCredentials;
  });

  Future<Map<String, Object?>> call(
      String action, Map<String, Object?> input) async {
    final outcome =
        await api.invokeJson(action, input, harness.Invocation(origin: 'mcp'));
    expect(outcome, isA<harness.Completed>(),
        reason: '$action $input: ${outcome.toEnvelope()}');
    final value = (outcome as harness.Completed).value.toJson();
    expect(
        api.catalog
            .firstWhere((spec) => spec.id == action)
            .output
            .validate(value),
        isEmpty);
    return value;
  }

  test('Classic AI secrets use the vault while public settings retain history',
      () async {
    const secret = 'settings-vault-offline-test-key';
    const ref = CredentialRef('preferences', 'spoiler_ai_api_key');
    final prefs = await SharedPreferences.getInstance();
    await video.setSpoilerAiApiKey(secret);
    expect(await vault.read(ref), secret);
    expect(jsonDecode(prefs.getString(SettingsKeys.spoilerAiApiKey)!),
        ref.placeholder);
    expect(
        await CredentialStore.instance
            .read(prefs, SettingsKeys.spoilerAiApiKey),
        secret);
    await call('settings.set', {
      'key': 'danmaku.spoilerAiModel',
      'value': 'offline-model',
    });
    final history = await registry.history();
    expect(history.single['key'], 'danmaku.spoilerAiModel');
    expect(history.single['changedBy'], 'agent');
    expect(jsonEncode(await db.query('settings_changes')),
        isNot(contains(secret)));
  });

  test('all vault preference keys and composites are forbidden settings',
      () async {
    final denied = {
      ...CredentialStore.scalarKeys,
      ...CredentialStore.compositeKeys.keys,
      'plugin_text_setting_fixture::key',
      'plugin_fixture_custom_value',
      'credential_vault_private_ref',
      'tmdb',
      'metadata.tmdb',
      'agent.token',
      'credentials.custom',
      'next/credentials.json',
      'next/endpoint.json',
    };
    final exposed = (await registry.describe()).map((entry) => entry['key']);
    for (final key in denied) {
      expect(isSettingDenied(key), isTrue, reason: key);
      expect(exposed, isNot(contains(key)));
      for (final action in ['settings.get', 'settings.set', 'settings.reset']) {
        final outcome = await api.invokeJson(
          action,
          {'key': key, if (action == 'settings.set') 'value': 'blocked'},
          harness.Invocation(origin: 'mcp'),
        );
        expect((outcome as harness.Failed).failure.code,
            harness.FailureCode.notFound,
            reason: '$action $key');
      }
      final allowed = registry.entries.first;
      SettingEntry entry({required String key, required String storageKey}) =>
          SettingEntry(
            key: key,
            title: 'Forbidden candidate',
            description: 'Forbidden candidate',
            schema: allowed.schema,
            defaultValue: allowed.defaultValue,
            storageKey: storageKey,
            reader: allowed.reader,
            writer: allowed.writer,
            read: allowed.read,
            write: allowed.write,
            decodeStorage: allowed.decodeStorage,
          );
      expect(() => SettingsRegistry(db, [entry(key: key, storageKey: 'safe')]),
          throwsArgumentError);
      expect(() => SettingsRegistry(db, [entry(key: 'safe', storageKey: key)]),
          throwsArgumentError);
    }
  });

  test('conversion defaults and reset follow Classic language selection',
      () async {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    dispatcher.localeTestValue = const Locale('zh', 'TW');
    addTearDown(dispatcher.clearLocaleTestValue);
    for (final languageMode in ['auto', 'en']) {
      preferences.dispose();
      SharedPreferences.setMockInitialValues({
        SettingsKeys.appLanguageMode: languageMode,
      });
      preferences = SettingsProvider();
      await preferences.ready;
      final expected = languageMode != 'auto';
      final descriptions = await registry.describe(domain: 'danmaku');
      final conversion = descriptions
          .firstWhere((entry) => entry['key'] == 'danmaku.convertToSimplified');
      expect(conversion['default'], expected);
      expect(conversion['value'], preferences.danmakuConvertToSimplified);
      await call('settings.set', {
        'key': 'danmaku.convertToSimplified',
        'value': !expected,
      });
      final reset = await call('settings.reset', {
        'key': 'danmaku.convertToSimplified',
      });
      expect(reset['value'], expected);
      expect(preferences.danmakuConvertToSimplified, expected);
    }
  });

  test('every registered setting uses a real Classic setter and round trips',
      () async {
    // Exercise each real binding independently of its device/menu visibility.
    registry = SettingsRegistry(
        db,
        registry.entries.map((entry) => SettingEntry(
              key: entry.key,
              title: entry.title,
              description: entry.description,
              schema: entry.schema,
              defaultValue: entry.defaultValue,
              storageKey: entry.storageKey,
              reader: entry.reader,
              writer: entry.writer,
              read: entry.read,
              write: entry.write,
              decodeStorage: entry.decodeStorage,
              scope: entry.scope,
              apply: entry.apply,
              validateValue: entry.validateValue,
            )));
    SettingsAccess.registry = registry;
    api = harness.Harness([SettingsCapability(registry)]);
    for (final entry in registry.entries) {
      final initial = await call('settings.get', {'key': entry.key});
      expect(entry.schema.validate(initial['value']), isEmpty,
          reason: entry.key);
      if (entry.key == 'danmaku.spoilerAiApiUrl') {
        await video.setSpoilerAiApiUrl('');
      }
      expect((await call('settings.get', {'key': entry.key}))['value'],
          entry.defaultValue,
          reason: entry.key);
      final value = switch (entry.schema) {
        harness.BooleanSchema() => !(initial['value'] as bool),
        harness.StringSchema(:final values) when values != null =>
          values.firstWhere((v) => v != initial['value'],
              orElse: () => values.first),
        harness.IntegerSchema(:final minimum, :final maximum) =>
          (minimum ?? 0) == initial['value'] ? (maximum ?? 1) : (minimum ?? 0),
        harness.NumberSchema(:final minimum, :final maximum) =>
          (minimum ?? 0.0) == initial['value']
              ? (maximum ?? 1.0)
              : (minimum ?? 0.0),
        harness.ArraySchema() => ['screen this word'],
        _ => entry.defaultValue,
      };
      // Enabling spoiler analysis requires a user-supplied secret configuration.
      if (entry.key == 'danmaku.spoilerPreventionEnabled') {
        await video.setSpoilerAiApiUrl('http://127.0.0.1/offline');
        await video.setSpoilerAiApiKey('offline-test-only');
      }
      final set = await call('settings.set',
          {'key': entry.key, 'value': value, 'reason': 'round trip'});
      expect(set['value'], value, reason: entry.key);
      expect((await call('settings.get', {'key': entry.key}))['value'], value,
          reason: entry.key);
      final restored = await call('settings.reset', {'key': entry.key});
      expect(restored['value'], entry.defaultValue, reason: entry.key);
    }
  });

  test(
      'agent and Classic edits append host-owned provenance and survive reopen',
      () async {
    final changed = await call('settings.set',
        {'key': 'danmaku.opacity', 'value': 0.5, 'reason': '弹幕太吵'});
    expect(video.danmakuOpacity, 0.5);
    expect((changed['provenance'] as Map)['changedBy'], 'agent');
    await video.setDanmakuOpacity(0.7);
    final rows =
        (await call('settings.history', {'key': 'danmaku.opacity'}))['changes']
            as List;
    expect(rows, hasLength(2));
    expect((rows.first as Map)['changedBy'], 'user');
    expect((rows.last as Map)['reason'], '弹幕太吵');
    expect((rows.first as Map)['previousValue'], 0.5);
    await db.close();
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    registry = SettingsRegistry(db, ApplicationSettings.entries());
    SettingsAccess.registry = registry;
    expect((await registry.get('danmaku.opacity'))['revision'], 2);
    expect((await registry.get('danmaku.opacity'))['value'], 0.7);
  });

  test('invalid values and stale concurrent writers do not alter persistence',
      () async {
    for (final value in ['bad', -0.1, 1.1, double.nan, double.infinity]) {
      final outcome = await api.invokeJson(
          'settings.set',
          {'key': 'danmaku.opacity', 'value': value},
          harness.Invocation(origin: 'mcp'));
      expect(outcome, isA<harness.Failed>());
      expect((outcome as harness.Failed).failure.code,
          harness.FailureCode.invalidInput);
    }
    final results = await Future.wait([
      for (final value in [0.4, 0.8])
        api.invokeJson(
            'settings.set',
            {'key': 'danmaku.opacity', 'value': value, 'expectedRevision': 0},
            harness.Invocation(origin: 'mcp')),
    ]);
    expect(results.whereType<harness.Completed>(), hasLength(1));
    expect((results.whereType<harness.Failed>().single).failure.code,
        harness.FailureCode.conflict);
    expect(await registry.history(key: 'danmaku.opacity'), hasLength(1));
  });

  test('old physical values are read before Classic startup migration',
      () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.danmakuSupersample: 1.5,
      SettingsKeys.autoMatchDanmakuOnPlay: false,
      SettingsKeys.externalPlayerPath: '/Applications/VLC.app',
      'anime4k_profile': ' true ',
      'crt_profile': 999,
      'erika_upscaler_mode': -1,
      'subtitle_align_x': -1,
      'subtitle_align_y': 999,
      'subtitle_override_mode': 999,
    });
    final entries = ApplicationSettings.entries();
    Future<Object?> read(String key) =>
        entries.firstWhere((v) => v.key == key).read();
    expect(await read('danmaku.supersample'), 1.5);
    expect(await read('danmaku.skipMatching'), true);
    expect(await read('danmaku.autoLoadStrategy'), 'remoteAndLocal');
    expect(await read('player.externalType'), 'vlc');
    expect(await read('player.anime4kProfile'), 'lite');
    expect(await read('player.crtProfile'), 'off');
    expect(await read('player.erikaUpscalerMode'), 'off');
    expect(await read('subtitle.alignX'), SubtitleAlignX.values.first.name);
    expect(await read('subtitle.alignY'), SubtitleAlignY.values.last.name);
    expect(await read('subtitle.overrideMode'),
        SubtitleStyleOverrideMode.values.last.name);
  });

  test('mesh and migration provenance come from the host invocation', () async {
    await registry.set(
        'danmaku.opacity', 0.6, harness.Invocation(origin: 'mesh:living-room'),
        reason: 'shared preference');
    final prefs = await SharedPreferences.getInstance();
    await SettingsAccess.persist(SettingsKeys.danmakuOpacity,
        () => prefs.setDouble(SettingsKeys.danmakuOpacity, 0.8),
        migration: true);
    final rows = await registry.history(key: 'danmaku.opacity');
    expect(rows.map((v) => v['changedBy']), ['migration', 'mesh:living-room']);
    expect(rows.map((v) => v['revision']), [2, 1]);
  });

  test(
      'invalid discrete values, colors and unauthorized paths fail before writing',
      () async {
    for (final input in [
      {'key': 'danmaku.outlineWidth', 'value': 0.25},
      {'key': 'subtitle.color', 'value': 'blue'},
      {'key': 'subtitle.opacity', 'value': 1.2},
    ]) {
      final outcome = await api.invokeJson(
          'settings.set', input, harness.Invocation(origin: 'mcp'));
      expect((outcome as harness.Failed).failure.code,
          harness.FailureCode.invalidInput);
    }
    ApplicationSettings.authorizePath = (path, {directory = false}) async {
      throw const harness.Failure(
          harness.FailureCode.invalidInput, 'Outside authorized roots.');
    };
    final result = await api.invokeJson(
        'settings.set',
        {'key': 'subtitle.fontDir', 'value': '/outside'},
        harness.Invocation(origin: 'mcp'));
    expect((result as harness.Failed).failure.code,
        harness.FailureCode.invalidInput);
    expect(await registry.history(key: 'subtitle.fontDir'), isEmpty);
  });

  test('remote wire descriptors and coercion keep the existing player behavior',
      () async {
    final playing = _PlayingSettingsState(video.player);
    ApplicationSettings.video = playing;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remote_control_receiver_enabled', true);
    final bridge = PlayerRemoteControlBridge.instance;
    final payload = await bridge.buildPayload(
        paneId: 'danmakuSettings', includeParameters: true);
    final params = payload['parameters'] as List;
    final opacity =
        params.cast<Map>().singleWhere((v) => v['key'] == 'danmaku.opacity');
    expect(opacity, {
      'paneId': 'danmakuSettings',
      'key': 'danmaku.opacity',
      'label': '弹幕透明度',
      'type': 'double',
      'value': 1.0,
      'min': 0,
      'max': 1,
      'step': 0.01,
    });
    final speed = params
        .cast<Map>()
        .singleWhere((v) => v['key'] == 'danmaku.speedMultiplier');
    expect(speed['max'], 3);
    final result = await bridge.executeCommand(
        'set_parameter', {'key': 'danmaku.opacity', 'value': '0.4'});
    expect(result['success'], true);
    expect(playing.danmakuOpacity, 0.4);
    expect((await registry.history(key: 'danmaku.opacity')).single['changedBy'],
        'user');
    await PlayerFactory.saveKernelType(PlayerKernelType.mediaKit);
    final subtitlePayload = await bridge.buildPayload(
        paneId: 'subtitleSettings', includeParameters: true);
    final delay = (subtitlePayload['parameters'] as List)
        .cast<Map>()
        .singleWhere((v) => v['key'] == 'subtitle.delaySeconds');
    expect(delay['step'], 0.1);
    expect(delay['min'], playing.subtitleDelaySliderMinSeconds);
    expect(delay['max'], playing.subtitleDelaySliderMaxSeconds);
    bridge.detach(playing);
    playing.dispose();
    ApplicationSettings.video = video;
    bridge.attach(video);
  });

  test(
      'denylist is absent at runtime and cannot be read, written, reset or searched in history',
      () async {
    final keys = ((await call('settings.describe', {}))['settings'] as List)
        .map((v) => (v as Map)['key'])
        .toSet();
    for (final key in {
      ...settingsDenylist,
      'vault.reference.value',
      'server.password',
      'agent.permissions.shell'
    }) {
      expect(keys, isNot(contains(key)));
      for (final verb in ['get', 'set', 'reset', 'history']) {
        final outcome = await api.invokeJson(
            'settings.$verb',
            {'key': key, if (verb == 'set') 'value': false},
            harness.Invocation(origin: 'mcp'));
        expect(outcome, isA<harness.Failed>());
        expect((outcome as harness.Failed).failure.code,
            harness.FailureCode.notFound);
      }
    }
    final spoof = await api.invokeJson(
        'settings.set',
        {'key': 'danmaku.opacity', 'value': 0.4, 'changedBy': 'user'},
        harness.Invocation(origin: 'mcp'));
    expect(spoof, isA<harness.Failed>());
  });

  test(
      'describe filters domains and keywords, effect and apply modes are explicit',
      () async {
    final descriptions = (await call('settings.describe',
        {'domain': 'subtitle', 'keyword': '透明度'}))['settings'] as List;
    expect(descriptions.map((v) => (v as Map)['key']), ['subtitle.opacity']);
    for (final spec in api.catalog) {
      expect(
          spec.effect,
          ['settings.set', 'settings.reset'].contains(spec.id)
              ? harness.Effect.write
              : harness.Effect.read);
    }
    final broadcasts = <PlayerKernelType>[];
    final subscription = PlayerFactory.onKernelChanged.listen(broadcasts.add);
    final output = await call(
        'settings.set', {'key': 'player.kernel', 'value': 'videoPlayer'});
    await Future<void>.delayed(Duration.zero);
    expect(output['apply'], 'reload_player');
    expect(broadcasts, isEmpty);
    await subscription.cancel();
  });
}
