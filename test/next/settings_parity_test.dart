import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as harness;
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/next/danmaku/sidecar.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/settings/capability.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/settings/system_settings.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:nipaplay/media_library/adaptive_media_collection_view.dart'
    show MediaCollectionSort;
import 'package:nipaplay/services/media_server_device_id_service.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late MediaFixture media;
  late SubtitleLibrary subtitles;
  late SettingsRegistry registry;
  late harness.Harness api;

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('nipa-parity-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path);
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    media = MediaFixture();
    await media.open();
    subtitles = SubtitleLibrary(media.service, media.root);
    registry = SettingsRegistry(db, SystemSettings(
            SidecarIndexer(DanmakuStore(media.identities), () async {}),
            subtitles)
        .entries());
    SettingsAccess.registry = registry;
    api = harness.Harness([SettingsCapability(registry)]);
  });

  tearDown(() async {
    await MediaServerDeviceIdService.instance.setCustomDeviceId(null);
    await registry.drain();
    SettingsAccess.registry = null;
    await subtitles.close();
    await media.close();
    await db.close();
    await root.delete(recursive: true);
  });

  Future<Map<String, Object?>> call(String action, Map<String, Object?> input,
      {String origin = 'mcp'}) async {
    final outcome =
        await api.invokeJson(action, input, harness.Invocation(origin: origin));
    expect(outcome, isA<harness.Completed>(),
        reason: '$action $input: ${outcome.toEnvelope()}');
    return (outcome as harness.Completed).value.toJson();
  }

  Future<harness.Failure> rejected(String key, Object? value) async {
    final outcome = await api.invokeJson('settings.set',
        {'key': key, 'value': value}, harness.Invocation(origin: 'mcp'));
    expect(outcome, isA<harness.Failed>(), reason: '$key=$value');
    return (outcome as harness.Failed).failure;
  }

  test('the Bangumi server reads, writes and resets with the address in use',
      () async {
    final first = await call('settings.get', {'key': 'network.bangumiServerUrl'});
    expect(first['value'], '');
    expect(first['effective'], NetworkSettings.bangumiDefaultServer);
    expect(first['effectiveState'], 'same');

    final set = await call('settings.set', {
      'key': 'network.bangumiServerUrl',
      'value': 'bgm.example.org/',
      'reason': 'mirror'
    });
    expect(set['value'], 'https://bgm.example.org');
    expect(set['effective'], 'https://bgm.example.org');
    expect(set['revision'], 1);
    expect(await NetworkSettings.getBangumiServer(), 'https://bgm.example.org');

    for (final bad in [
      'https://user:pass@bgm.example.org',
      'https://bgm.example.org/?token=1',
      'https://bgm.example.org/#x',
      'ftp://bgm.example.org',
      NetworkSettings.bangumiDefaultServer,
    ]) {
      expect((await rejected('network.bangumiServerUrl', bad)).code,
          harness.FailureCode.invalidInput,
          reason: bad);
    }
    final reset = await call('settings.reset', {'key': 'network.bangumiServerUrl'});
    expect(reset['value'], '');
    expect(reset['effective'], NetworkSettings.bangumiDefaultServer);
    final history = await registry.history(key: 'network.bangumiServerUrl');
    expect(history.map((row) => row['value']), ['', 'https://bgm.example.org']);
  });

  test('a user changing the Bangumi server in Classic is recorded as the user',
      () async {
    await NetworkSettings.setBangumiServer('https://bgm.example.net');
    await registry.drain();
    final history = await registry.history(key: 'network.bangumiServerUrl');
    expect(history.single['changedBy'], 'user');
    expect(history.single['value'], 'https://bgm.example.net');
    await NetworkSettings.resetBangumiServer();
    await registry.drain();
    expect(
        (await registry.history(key: 'network.bangumiServerUrl')).first['value'],
        '');
  });

  test('the media server device ID is the custom one or the generated one',
      () async {
    final before = await call('settings.get', {'key': 'network.mediaServerDeviceId'});
    expect(before['value'], '');
    final generated = before['effective'] as String;
    expect(generated, contains('NipaPlay'));
    expect(before['effectiveDetail'], contains('generated'));

    final set = await call('settings.set',
        {'key': 'network.mediaServerDeviceId', 'value': ' my-device '});
    expect(set['value'], 'my-device');
    expect(set['effective'], 'my-device');
    expect(set['effectiveDetail'], contains('custom'));

    expect((await rejected('network.mediaServerDeviceId', 'a"b')).code,
        harness.FailureCode.invalidInput);
    expect((await rejected('network.mediaServerDeviceId', 'x' * 129)).code,
        harness.FailureCode.invalidInput);

    final restored =
        await call('settings.reset', {'key': 'network.mediaServerDeviceId'});
    expect(restored['value'], '');
    expect(restored['effective'], generated);
    expect(
        (await registry.history(key: 'network.mediaServerDeviceId'))
            .map((row) => row['value']),
        ['', 'my-device']);
  });

  test('the user changing the device ID in Classic is recorded', () async {
    await MediaServerDeviceIdService.instance.setCustomDeviceId('from-ui');
    await registry.drain();
    final history = await registry.history(key: 'network.mediaServerDeviceId');
    expect(history.single['changedBy'], 'user');
    expect(history.single['value'], 'from-ui');
  });

  test('sort, filter and layout preferences read and write Classic\'s keys',
      () async {
    final prefs = await SharedPreferences.getInstance();
    expect((await call('settings.get', {'key': 'appearance.classicLocalLibrarySort'}))['value'],
        'nameAscending');
    await call('settings.set',
        {'key': 'appearance.classicLocalLibrarySort', 'value': 'sizeDescending'});
    expect(prefs.getInt('library_sort_option'), 5);
    prefs.setInt('library_sort_option', 9);
    expect((await call('settings.get', {'key': 'appearance.classicLocalLibrarySort'}))['value'],
        'nameAscending');

    await call('settings.set',
        {'key': 'appearance.collectionSort.webdav', 'value': 'recentlyAdded'});
    expect(prefs.getString('library_collection_sort_v1_webdav'), 'recentlyAdded');
    expect((await call('settings.get', {'key': 'appearance.collectionSort.local'}))['value'],
        'comprehensive');

    await call('settings.set',
        {'key': 'appearance.unwatchedOnly.jellyfin', 'value': true});
    await call('settings.set',
        {'key': 'appearance.unwatchedOnly.shared', 'value': true});
    expect(prefs.getBool('network_media_unwatched_only_jellyfin'), true);
    expect(prefs.getBool('shared_library_unwatched_only'), true);
    expect((await call('settings.get', {'key': 'appearance.unwatchedOnly.emby'}))['value'],
        false);

    await call('settings.set',
        {'key': 'appearance.largeScreenLayout', 'value': true});
    expect(prefs.getBool('nipaplay_use_large_screen_layout'), true);
    final layout = await call('settings.get', {'key': 'appearance.largeScreenLayout'});
    expect(layout['apply'], 'restart_app');
    expect(layout['effective'], isNull);
    expect(layout['effectiveReason'], 'held_by_main_page');

    final sorted =
        await call('settings.get', {'key': 'appearance.classicLocalLibrarySort'});
    expect(sorted['effectiveReason'], 'loaded_when_page_created');
  });

  test('the option names match the Classic enums they stand for', () {
    expect(collectionSortOptions,
        MediaCollectionSort.values.map((e) => e.name).toList());
    expect(collectionSortSources,
        UnifiedMediaLibrarySource.values.map((e) => e.name).toList());
  });

  test('Jellyfin and Emby default quality and transcoding go through Classic\'s providers',
      () async {
    final prefs = await SharedPreferences.getInstance();
    for (final server in ['jellyfin', 'emby']) {
      final quality = await call('settings.get', {'key': 'playback.${server}DefaultQuality'});
      expect(quality['value'], 'bandwidth5m');
      expect((await call('settings.get', {'key': 'playback.${server}Transcoding'}))['value'],
          false);
      await call('settings.set',
          {'key': 'playback.${server}DefaultQuality', 'value': 'bandwidth10m'});
      expect(prefs.getString('${server}_default_quality'), '4');
      expect(prefs.getString('${server}_enable_transcoding'), 'true');
      await call('settings.set', {'key': 'playback.${server}Transcoding', 'value': false});
      // Classic puts the quality back to original when transcoding goes off.
      expect(prefs.getString('${server}_default_quality'), '7');
      expect(
          (await call('settings.get', {'key': 'playback.${server}DefaultQuality'}))['value'],
          'original');
    }
    expect((await rejected('playback.jellyfinDefaultQuality', 'ultra')).code,
        harness.FailureCode.invalidInput);
  });
}
