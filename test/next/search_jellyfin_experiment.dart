// Uses only a disposable X56 server and an in-memory vault.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/media_sources/capability.dart';
import 'package:nipaplay/next/media_sources/service.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/library_service.dart';
import 'package:nipaplay/next/ui_data/library_sources.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../security/memory_vault.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'X56 temporary Jellyfin server search is bounded and does not register files',
      () async {
    final session = jsonDecode(
        await File(Platform.environment['NIPA_X56_SESSION']!)
            .readAsString()) as Map;
    expect(Uri.parse(session['baseUrl'] as String).host, '127.0.0.1');
    SharedPreferences.setMockInitialValues({
      'server_profiles': '[]',
      'smb_connections': '[]',
      'webdav_connections': '[]'
    });
    PackageInfo.setMockInitialValues(
        appName: 'NipaPlay',
        packageName: 'nipaplay',
        version: 'X56',
        buildNumber: '1',
        buildSignature: '');
    final previous = CredentialStore.instance,
        previousHttp = HttpOverrides.current;
    final vault = MemoryVault();
    CredentialStore.instance = CredentialStore(vault, desktop: true);
    HttpOverrides.global = _Direct();
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('nipa-x56-search-');
    final jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final store = IdentityStore(jobs.database, 'x56');
    final engine = TaskEngine(store: jobs, ownerDeviceId: 'x56', executors: []);
    final sources = MediaSourcesService(store)..engine = engine;
    final media = MediaService(
        store: store,
        providers: [],
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path]);
    final ui = UiDataService(
        media, engine, StateCapability([]), StateSources(), root, vault);
    final library =
        LibraryDataService(ui, port: ClassicLibrarySources(sources, root));
    ui.libraryData = library;
    addTearDown(() async {
      await ui.close();
      await sources.close();
      await engine.close();
      await jobs.database.close();
      await root.delete(recursive: true);
      CredentialStore.instance = previous;
      HttpOverrides.global = previousHttp;
    });
    await sources.ensureInitialized();
    final source = (await sources.configure({
      'type': 'jellyfin',
      'name': 'X56 CC0',
      'url': session['baseUrl'],
      'username': 'x56'
    }))['source'] as JsonMap;
    final id = source['sourceId'] as String;
    final profile = sources.profiles.getProfileById(sources.key(id))!;
    await sources.server('jellyfin').acceptSession(profile,
        token: session['token'] as String,
        authenticatedUserId: session['userId'] as String,
        authenticatedUsername: 'x56',
        libraryIds: [session['libraryId'] as String]);
    final harness = Harness([MediaSourcesCapability(sources)]);
    expect(harness.lookup('media.sources.search')!.spec.effect, Effect.read);
    if (Platform.environment['NIPA_X56_PHASE'] == 'offline') {
      await _stopAndSearch(sources, id, jobs.database);
      return;
    }
    final before = await jobs.database.rawQuery('SELECT total_changes() AS n');
    String? sourceWorkId;
    for (final query in ['X', 'X56', 'X56 Open', 'Open', '不存在']) {
      final clock = Stopwatch()..start();
      final outcome = await harness.invokeJson(
          'media.sources.search',
          {
            'query': query,
            'sourceIds': [id, 'jellyfin:missing'],
            'limit': 12
          },
          Invocation(origin: 'gui'));
      expect(outcome, isA<Completed>());
      final results = (outcome as Completed).value.toJson()['sources'] as List;
      final result = results.first as Map;
      expect(result['error'], isNull);
      final entries = result['entries'] as List;
      if (query == '不存在') {
        expect(entries, isEmpty);
      } else {
        expect(entries.length, 3);
        sourceWorkId = (entries
                .cast<Map>()
                .singleWhere((e) => e['kind'] == 'Series'))['sourceWorkId']
            as String;
        expect(
            entries.cast<Map>().where((e) => e['playable'] == true).length, 2);
        expect(
            entries
                .cast<Map>()
                .every((e) => e['fileId'] == null && e['workId'] == null),
            true);
      }
      expect((results.last as Map)['error'], isNotNull);
      print(jsonEncode({
        'observation': 'server search',
        'query': query,
        'total': result['total'],
        'returned': entries.length,
        'kinds': entries.cast<Map>().map((e) => e['kind']).toList(),
        'milliseconds': clock.elapsedMicroseconds / 1000,
        'unavailableSibling': (results.last as Map)['error'] != null
      }));
    }
    final limited = await sources.search('Open', sourceIds: [id], limit: 1);
    expect(
        ((limited['sources'] as List).single as Map)['entries'], hasLength(1));
    expect(((limited['sources'] as List).single as Map)['total'], 3);
    expect(await jobs.database.rawQuery('SELECT total_changes() AS n'), before);
    expect(await jobs.database.query('media_entities'), isEmpty);
    expect(await jobs.database.query('media_locations'), isEmpty);
    expect(await jobs.database.query('media_bindings'), isEmpty);
    print(jsonEncode({
      'observation': 'read-only boundary',
      'queries': 6,
      'fileEntities': 0,
      'locations': 0,
      'bindings': 0,
      'totalChangesUnchanged': true,
      'limit1Returned': 1,
      'serverTotal': 3
    }));
    final work = await library.sourceWork(sourceWorkId!);
    expect(work!.title, 'X56 Open Series');
    final episodes = await library.sourceEpisodes(sourceWorkId);
    expect(episodes, hasLength(2));
    print(jsonEncode({
      'observation': 'source search opens Next original work',
      'title': work.title,
      'episodes': episodes.length
    }));
    await _stopAndSearch(sources, id, jobs.database);
  });
}

Future<void> _stopAndSearch(
    MediaSourcesService sources, String id, Database db) async {
  final before = await db.query('media_entities');
  final changes = await db.rawQuery('SELECT total_changes() AS n');
  final stopped = await Process.run('docker', [
    '--context',
    'colima-nipa-test',
    'stop',
    '-t',
    '1',
    'nipa-x56-jellyfin'
  ]);
  expect(stopped.exitCode, 0);
  final offline =
      await sources.search('Open', sourceIds: [id, 'jellyfin:missing']);
  final failed = (offline['sources'] as List).first as Map;
  expect(failed['connectionState'], 'failed');
  expect(failed['total'], isNull);
  expect(failed['error'], isNotNull);
  expect(await db.query('media_entities'), before);
  expect(await db.rawQuery('SELECT total_changes() AS n'), changes);
  print(jsonEncode({
    'observation': 'own server stopped',
    'connectionState': failed['connectionState'],
    'total': failed['total'],
    'errorPresent': true,
    'fileIndexPreserved': true,
    'fileCountBefore': before.length,
    'fileCountAfter': (await db.query('media_entities')).length,
  }));
}

final class _Direct extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
