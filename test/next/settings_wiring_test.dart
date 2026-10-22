import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'download_test_support.dart';
import 'media_test_support.dart';

/// The settings parts as the application core wires them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, mediaFolder;
  late NextCore core;
  late Harness harness;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-wiring-');
    mediaFolder = await Directory('${root.path}/media').create();
    core = NextCore(
      root: root,
      databaseFactory: databaseFactoryFfi,
      downloadBackend: FakeDownloadBackend(root),
      downloadLibrary: FakeDownloadLibrary(),
      isDownloaderEnabled: () async => true,
      loadImportedKeys: () async => const {},
      downloadRefreshInterval: const Duration(milliseconds: 20),
      classic: MemoryClassic(),
      authorizedRoots: () => [mediaFolder.path],
      mediaDurationProbe: (_) async => 1440000,
      mediaSubtitleProbe: (_) async => {'subtitles': <Object?>[]},
      mediaProviders: [
        TmdbMetadataProvider(FixtureTransport('tmdb')),
        DandanplayMetadataProvider(FixtureTransport('dandanplay')),
      ],
    );
    await core.ready;
    harness = Harness(core.capabilities);
  });
  tearDown(() async {
    await core.close();
    await root.delete(recursive: true);
  });

  test('the core asks the user before an Agent sends keys or traffic elsewhere',
      () async {
    expect(harness.lookup('settings.set.request'), isNotNull);
    final outcome = await harness.invokeJson(
        'settings.set',
        {'key': 'network.bangumiServerUrl', 'value': 'https://bgm.example.org'},
        Invocation(origin: 'mcp'));
    expect(outcome, isA<NeedsDecision>(), reason: '${outcome.toEnvelope()}');
    final get = await harness.invokeJson('settings.get',
        {'key': 'network.bangumiServerUrl'}, Invocation(origin: 'mcp'));
    expect((get as Completed).value.toJson()['value'], '');

    final page = await harness.invokeJson(
        'settings.set',
        {'key': 'network.bangumiServerUrl', 'value': 'https://bgm.example.org'},
        Invocation(origin: 'gui'));
    expect(page, isA<Completed>(), reason: '${page.toEnvelope()}');
    final reset = await harness.invokeJson('settings.reset',
        {'key': 'network.bangumiServerUrl'}, Invocation(origin: 'mcp'));
    expect(reset, isA<Completed>());
  });

  test('the core exposes the preference actions and keeps what a setting claims out of them',
      () async {
    for (final id in [
      'settings.prefs.list',
      'settings.prefs.get',
      'settings.prefs.set',
      'settings.prefs.undo',
      'settings.prefs.history'
    ]) {
      expect(harness.lookup(id), isNotNull, reason: id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_http_proxy', 'http://127.0.0.1:7890');
    await prefs.setString('my_free_note', 'x');
    final listed = await harness.invokeJson('settings.prefs.list',
        {'keyword': 'player_http_proxy'}, Invocation(origin: 'mcp'));
    final row = (((listed as Completed).value.toJson()['prefs']) as List).single as Map;
    expect(row['class'], 'claimed');
    expect(row['claimedBy'], ['network.httpProxy']);
    final refused = await harness.invokeJson(
        'settings.prefs.set',
        {'key': 'player_http_proxy', 'value': 'http://evil.example:1'},
        Invocation(origin: 'mcp'));
    expect(refused, isA<Failed>());
    final open = await harness.invokeJson('settings.prefs.set',
        {'key': 'my_free_note', 'value': 'y'}, Invocation(origin: 'mcp'));
    expect(open, isA<Completed>(), reason: '${open.toEnvelope()}');
    await prefs.reload();
    expect(prefs.getString('player_http_proxy'), 'http://127.0.0.1:7890');
    expect(prefs.getString('my_free_note'), 'x');
  });
}
