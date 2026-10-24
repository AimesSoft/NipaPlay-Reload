import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as harness;
import 'package:nipaplay/next/danmaku/sidecar.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/settings/application_settings.dart';
import 'package:nipaplay/next/settings/capability.dart';
import 'package:nipaplay/next/settings/effective.dart';
import 'package:nipaplay/next/settings/effective_value.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/settings/system_settings.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'media_test_support.dart';
import 'settings_registry_test.dart' show SettingsPlayer;

SettingEntry _fixed(String key, String storage, String apply,
        {required Object? Function() current}) =>
    SettingEntry(
        key: key,
        title: key,
        description: 'fixture',
        schema: const harness.StringSchema(),
        defaultValue: '',
        storageKey: storage,
        reader: 'test',
        writer: 'test',
        read: () async => current(),
        write: (_) async {},
        decodeStorage: (v) => v,
        apply: apply);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late VideoPlayerState video;
  late SettingsProvider preferences;
  late CredentialStore previousCredentials;
  var startupWindow = 'maximized';
  late MediaFixture media;
  late SubtitleLibrary subtitles;

  Future<SettingsRegistry> open(List<SettingEntry> extra) async {
    final registry = SettingsRegistry(db, [
      ...ApplicationSettings.entries(),
      ...SystemSettings(
              SidecarIndexer(DanmakuStore(media.identities), () async {}),
              subtitles)
          .entries(),
      ...extra,
    ]);
    SettingsAccess.registry = registry;
    return registry;
  }

  setUp(() async {
    sqfliteFfiInit();
    previousCredentials = CredentialStore.instance;
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    root = await Directory.systemTemp.createTemp('nipa-effective-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path);
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    preferences = SettingsProvider();
    await preferences.ready;
    video = VideoPlayerState.forSettings(Player.withDelegate(SettingsPlayer()));
    startupWindow = 'maximized';
    media = MediaFixture();
    await media.open();
    subtitles = SubtitleLibrary(media.service, media.root);
  });

  tearDown(() async {
    await subtitles.close();
    await media.close();
    video.dispose();
    preferences.dispose();
    await Future<void>.delayed(Duration.zero);
    await SettingsAccess.registry?.drain();
    SettingsAccess.registry = null;
    await db.close();
    await root.delete(recursive: true);
    CredentialStore.instance = previousCredentials;
  });

  test('stored and effective values come side by side with a state', () async {
    final registry = await open([]);
    final plain = await registry.get('player.fastPlaybackStartup');
    expect(plain['value'], false);
    expect(plain['effective'], false);
    expect(plain['effectiveState'], 'same');
    expect(plain['effectiveSource'], 'storage');

    await registry.set(
        'subtitle.opacity', 0.4, harness.Invocation(origin: 'mcp'));
    final live = await registry.get('subtitle.opacity');
    expect(live['value'], 0.4);
    expect(live['effective'], 0.4);
    expect(live['effectiveState'], 'same');
    expect(live['effectiveSource'], 'live');
    expect(live['effectiveReason'], isNull);
  });

  test('an asynchronous session probe reports the running Erika upscaler',
      () async {
    final previous = EffectiveRules.sessionPlayer;
    addTearDown(() => EffectiveRules.sessionPlayer = previous);
    EffectiveRules.sessionPlayer = (entry, stored) async {
      if (entry.key != 'player.erikaUpscalerMode') return null;
      await Future<void>.delayed(Duration.zero);
      return const Effective.differs('artCnnC4F32', 'runtime_adjusted',
          '正在播放的 Erika 实例当前请求 artCnnC4F32；存储值 off 会用于新实例。');
    };
    final registry = await open([]);
    final row = await registry.get('player.erikaUpscalerMode');
    expect(row['value'], 'off');
    expect(row['effective'], 'artCnnC4F32');
    expect(row['effectiveState'], 'differs');
    expect(row['effectiveSource'], 'live');
    expect(row['effectiveReason'], 'runtime_adjusted');
    expect(row['effectiveDetail'], contains('正在播放的 Erika 实例'));
  });

  test('a stored value the running player does not hold says so', () async {
    final registry = await open([]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitle_opacity', 0.9);
    final row = await registry.get('subtitle.opacity');
    expect(row['value'], 0.9);
    expect(row['effective'], 1.0);
    expect(row['effectiveState'], 'differs');
    expect(row['effectiveReason'], 'runtime_adjusted');
    expect(row['effectiveDetail'], contains('differs'));
  });

  test('the running kernel is read, and a stored one waits for the next open',
      () async {
    final registry = await open([]);
    final prefs = await SharedPreferences.getInstance();
    // PlayerKernelType.mediaKit
    await prefs.setInt('player_kernel_type', 2);
    final row = await registry.get('player.kernel');
    expect(row['value'], 'mediaKit');
    expect(row['effective'], 'mdk');
    expect(row['effectiveState'], 'differs');
    expect(row['effectiveReason'], 'reload_required');
    expect(row['apply'], 'reload_player');
  });

  test(
      'a setting Next saved waits as reload_required and is same once a '
      'player is built from it', () async {
    DeferredReloads.reset();
    await PlayerFactory.saveKernelType(PlayerKernelType.erika);
    addTearDown(() async {
      DeferredReloads.reset();
      await PlayerFactory.saveKernelType(PlayerKernelType.mdk);
    });
    final registry = await open([]);
    await registry.set('player.erikaAndroidOutputMode', 'extendedLinearHdr',
        harness.Invocation(origin: 'mcp'));
    var row = await registry.get('player.erikaAndroidOutputMode');
    expect(row['value'], 'extendedLinearHdr');
    expect(row['effective'], 'sdr');
    expect(row['effectiveState'], 'differs');
    expect(row['effectiveReason'], 'reload_required');
    expect(row['effectiveDetail'], contains('reopened once on a new player'));

    // The player the next media opens on is built from the stored values.
    DeferredReloads.built(PlayerKernelType.erika, PlayerKernelType.erika);
    row = await registry.get('player.erikaAndroidOutputMode');
    expect(row['effective'], 'extendedLinearHdr');
    expect(row['effectiveState'], 'same');
    expect(row['effectiveReason'], isNull);

    await registry.set(
        'player.kernel', 'mediaKit', harness.Invocation(origin: 'mcp'));
    row = await registry.get('player.kernel');
    expect(row['effective'], 'mdk');
    expect(row['effectiveState'], 'differs');
    expect(row['effectiveReason'], 'reload_required');
    expect(row['effectiveDetail'], contains('not interrupted'));
    DeferredReloads.built(PlayerKernelType.mediaKit, PlayerKernelType.mediaKit);
    expect(DeferredReloads.pendingFor(PlayerKernelType.mediaKit), false);
  });

  test('reload settings without a probe are unknown, not copied from storage',
      () async {
    final registry = await open([]);
    final row = await registry.get('player.customUserAgent');
    expect(row['effective'], isNull);
    expect(row['effectiveState'], 'unknown');
    expect(row['effectiveReason'], 'applies_at_next_open');
    expect(row['effectiveDetail'], isNotEmpty);
  });

  test('a setting another one switches off is inactive with the reason',
      () async {
    final registry = await open([]);
    await registry.set(
        'player.useHardwareDecoder', false, harness.Invocation(origin: 'mcp'));
    final hwdec = await registry.get('player.hwdecMode');
    expect(hwdec['effective'], isNull);
    expect(hwdec['effectiveState'], 'inactive');
    expect(hwdec['effectiveReason'], 'overridden');
    expect(hwdec['effectiveDetail'], contains('player.useHardwareDecoder'));

    // MDK does not scale subtitles.
    final scale = await registry.get('subtitle.scale');
    expect(scale['effectiveState'], 'inactive');
    expect(scale['effectiveReason'], 'kernel_unsupported');

    final external = await registry.get('player.externalPath');
    expect(external['effectiveState'], 'inactive');
    expect(external['effectiveReason'], 'inactive_dependency');
  });

  test('restart-only settings show what the application loaded', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('desktop_startup_window_state', 'maximized');
    final registry = await open([
      _fixed('general.startupWindowState', 'desktop_startup_window_state',
          'restart_app',
          current: () => startupWindow),
      _fixed('diagnostics.fixturePage', 'fixture_page', 'restart_app',
          current: () => 'x'),
    ]);
    expect((await registry.get('general.startupWindowState'))['effectiveState'],
        'same');
    startupWindow = 'windowed';
    final row = await registry.get('general.startupWindowState');
    expect(row['value'], 'windowed');
    expect(row['effective'], 'maximized');
    expect(row['effectiveState'], 'differs');
    expect(row['effectiveReason'], 'restart_required');
    expect(row['effectiveSource'], 'startup');
    startupWindow = 'maximized';
    expect((await registry.get('general.startupWindowState'))['effectiveState'],
        'same');
    // A restart-only setting with no recorded loaded value is not guessed.
    final other = await registry.get('diagnostics.fixturePage');
    expect(other['effective'], isNull);
    expect(other['effectiveState'], 'unknown');
    expect(other['effectiveReason'], 'no_runtime_probe');
  });

  test('settings read when a window is created have no single running value',
      () async {
    final registry = await open([]);
    final row = await registry.get('diagnostics.logViewerAutoScroll');
    expect(row['effective'], isNull);
    expect(row['effectiveState'], 'unknown');
    expect(row['effectiveReason'], 'loaded_when_page_created');
  });

  test('without a player the running value is unknown with the reason',
      () async {
    final registry = await open([]);
    ApplicationSettings.video = null;
    final row = await registry.get('subtitle.opacity');
    expect(row['effective'], isNull);
    expect(row['effectiveState'], 'unknown');
    expect(row['effectiveReason'], 'player_not_attached');
  });

  test('set, describe and the action output carry the effective fields',
      () async {
    final registry = await open([]);
    final api = harness.Harness([SettingsCapability(registry)]);
    final outcome = await api.invokeJson(
        'settings.set',
        {'key': 'danmaku.opacity', 'value': 0.5},
        harness.Invocation(origin: 'mcp'));
    expect(outcome, isA<harness.Completed>(),
        reason: '${outcome.toEnvelope()}');
    final set = (outcome as harness.Completed).value.toJson();
    expect(set['effective'], 0.5);
    expect(set['effectiveState'], 'same');
    final described = await api.invokeJson(
        'settings.describe',
        {
          'keys': ['danmaku.opacity'],
          'fields': ['key', 'value', 'effective', 'effectiveState']
        },
        harness.Invocation(origin: 'mcp'));
    final row =
        ((described as harness.Completed).value.toJson()['settings'] as List)
            .single as Map;
    expect(row, {
      'key': 'danmaku.opacity',
      'value': 0.5,
      'effective': 0.5,
      'effectiveState': 'same'
    });
  });

  test('the log viewer defaults are the window\'s own', () async {
    final registry = await open([]);
    final byKey = {for (final e in registry.entries) e.key: e};
    expect(byKey['diagnostics.logViewerAutoScroll']!.defaultValue, false);
    expect(byKey['diagnostics.logViewerShowTimestamp']!.defaultValue, true);
    expect((await registry.get('diagnostics.logViewerAutoScroll'))['value'],
        false);
    expect((await registry.get('diagnostics.logViewerShowTimestamp'))['value'],
        true);
    final api = harness.Harness([SettingsCapability(registry)]);
    await registry.set('diagnostics.logViewerAutoScroll', true,
        harness.Invocation(origin: 'mcp'));
    final reset = await api.invokeJson(
        'settings.reset',
        {'key': 'diagnostics.logViewerAutoScroll'},
        harness.Invocation(origin: 'mcp'));
    expect((reset as harness.Completed).value.toJson()['value'], false);
  });
}
