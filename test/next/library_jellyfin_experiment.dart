// Explicit disposable-server experiment. Session file contains test-only credentials.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/ui_capability.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/media_sources/service.dart';
import 'package:nipaplay/next/mesh/library.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/library.dart';
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
      'X48 real temporary Jellyfin source page, images, identities and readable playback',
      () async {
    final bindOnly = Platform.environment['NIPA_X48_PHASE'] == 'bound';
    final session = jsonDecode(
        await File(Platform.environment['NIPA_X48_SESSION']!)
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
        version: 'X48',
        buildNumber: '1',
        buildSignature: '');
    sqfliteFfiInit();
    final savedVault = CredentialStore.instance;
    final savedHttp = HttpOverrides.current;
    final vault = MemoryVault();
    CredentialStore.instance = CredentialStore(vault, desktop: true);
    HttpOverrides.global = _Direct();
    final root = await Directory.systemTemp.createTemp('nipa-x48-jellyfin-ui-');
    final jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    final identities = IdentityStore(jobs.database, 'x48');
    final engine = TaskEngine(store: jobs, ownerDeviceId: 'x48', executors: []);
    final transport = FixtureTransport('tmdb');
    void removeArtwork(Object? value) {
      if (value is Map) {
        value.remove('poster_path');
        value.remove('backdrop_path');
        value.remove('still_path');
        for (final child in value.values) removeArtwork(child);
      } else if (value is List) {
        for (final child in value) removeArtwork(child);
      }
    }

    for (final value in transport.responses.values) removeArtwork(value);
    final media = MediaService(
        store: identities,
        providers: [TmdbMetadataProvider(transport)],
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path],
        durationProbe: (_) async => 2000);
    final sources = MediaSourcesService(identities);
    sources.engine = engine;
    await sources.ensureInitialized();
    final source = (await sources.configure({
      'type': 'jellyfin',
      'name': 'X48 CC0',
      'url': session['baseUrl'],
      'username': 'x48'
    }))['source'] as JsonMap;
    final sourceId = source['sourceId'] as String;
    final profile = sources.profiles.getProfileById(sources.key(sourceId))!;
    await sources.server('jellyfin').acceptSession(profile,
        token: session['token'] as String,
        authenticatedUserId: session['userId'] as String,
        authenticatedUsername: 'x48',
        libraryIds: [session['libraryId'] as String]);
    final state = StateCapability([
      StateView(
          name: 'library.files',
          description: 'indexed files',
          fields: const ObjectSchema({}, additionalProperties: true),
          read: (_, __) async => [
                for (final r in await jobs.database.rawQuery(
                    'SELECT f.id AS fileId,f.attributes,l.locator,l.source,l.available,'
                    'fe.episode_id AS episodeId,fe.start_ms AS startMs,fe.end_ms AS endMs,r.parent_id AS workId FROM media_entities f '
                    'JOIN media_locations l ON l.file_id=f.id LEFT JOIN media_file_episodes fe ON fe.file_id=f.id '
                    'LEFT JOIN media_entities e ON e.id=fe.episode_id LEFT JOIN media_entities r ON r.id=e.parent_id'))
                  {...r, 'available': r['available'] == 1, 'progress': null}
              ])
    ]);
    final ui = UiDataService(media, engine, state, StateSources(), root, vault);
    final library =
        LibraryDataService(ui, port: ClassicLibrarySources(sources, root));
    ui.libraryData = library;
    final mesh = MeshRuntime(root: root, vault: vault, token: () async => null);
    ui.meshLibrary = MeshLibrary(ui, mesh);
    await ui.meshLibrary!.start();
    addTearDown(() async {
      await ui.close();
      await engine.close();
      await sources.close();
      await mesh.close();
      await jobs.database.close();
      await root.delete(recursive: true);
      CredentialStore.instance = savedVault;
      HttpOverrides.global = savedHttp;
    });
    final menu = await library.sources();
    final page = await library.page(sourceId);
    final slice =
        await library.items(page.categories.single.categoryId, limit: 1);
    final work = (slice.items.single as UiWorkItem).work;
    if (Platform.environment['NIPA_X48_PHASE'] == 'next') {
      expect(work.next, isNotNull);
      expect(work.next!.number, 1);
      expect(work.next!.playable, true);
      expect(work.episodeCount, isNull);
      final ref =
          await library.validatedSourceRef(work.next!.episodeId, 'episode');
      var bytes = 0;
      sources.playItem = (row, itemId, position) async {
        final client = HttpClient()..findProxy = (_) => 'DIRECT';
        final request = await client
            .getUrl(Uri.parse(JellyfinService.instance.getStreamUrl(itemId)));
        request.headers.set('Range', 'bytes=0-63');
        final response = await request.close();
        expect(response.statusCode, 206);
        await for (final chunk in response) bytes += chunk.length;
        client.close();
        return {'bytes': bytes};
      };
      await sources.play(ref![0], ref[1], expectedServerId: ref[2]);
      expect(bytes, 64);
      print(jsonEncode({
        'observation': 'bounded server series next plays',
        'number': work.next!.number,
        'playable': work.next!.playable,
        'episodeCount': work.episodeCount,
        'bytes': bytes
      }));
      return;
    }
    if (Platform.environment['NIPA_X48_PHASE'] == 'paging') {
      final seriesId = sourceEntityRef(work.workId, 'work')![1];
      final a = await library.port!
          .browse(sourceId, seriesId, recursive: true, offset: 0, limit: 1);
      final b = await library.port!
          .browse(sourceId, seriesId, recursive: true, offset: 1, limit: 1);
      final c = await library.port!
          .browse(sourceId, seriesId, recursive: true, offset: 2, limit: 1);
      expect((a['entries'] as List).length, 1);
      expect((b['entries'] as List).length, 1);
      expect(c['entries'], isEmpty);
      expect(a['total'], 2);
      expect(b['total'], 2);
      expect(((a['entries'] as List).single as Map)['id'],
          isNot(((b['entries'] as List).single as Map)['id']));
      print(jsonEncode({
        'observation': 'real server pagination',
        'offsets': [0, 1, 2],
        'limit': 1,
        'sizes': [
          (a['entries'] as List).length,
          (b['entries'] as List).length,
          (c['entries'] as List).length
        ],
        'total': a['total']
      }));
      return;
    }
    final episodes = await ui.episodes(work.workId);
    expect(episodes.length, 2);
    expect(work.artwork.poster, isNotNull);
    expect(await File(work.artwork.poster!).exists(), true);
    if (!bindOnly)
      print(jsonEncode({
        'observation': 'real Jellyfin original',
        'menu': menu.map((s) => s.name).toList(),
        'categories': page.categories.map((c) => c.title).toList(),
        'total': slice.total,
        'work': work.title,
        'episodes': episodes.map((e) => e.number).toList(),
        'localPoster': await File(work.artwork.poster!).exists(),
        'identityBindingsBefore':
            (await jobs.database.query('media_bindings')).length
      }));
    final last = await library.items(page.categories.single.categoryId,
        offset: 1, limit: 1);
    expect(last.items, isEmpty);
    expect(last.total, 1);
    final sorts = (await SharedPreferences.getInstance());
    await sorts.setString(
        'jellyfin_library_sort_settings',
        jsonEncode({
          session['libraryId']: {
            'sortBy': 'DateCreated',
            'sortOrder': 'Descending'
          }
        }));
    expect((await library.page(sourceId)).categories.single.sorts.first.id,
        'DateCreated:Descending');
    // The ui.open resolver uses the existing source activation/play path. Read
    // real HTTP video bytes here, without attaching a user's desktop player.
    if (!bindOnly) {
      var byteCount = 0;
      sources.playItem = (row, itemId, position) async {
        final url = JellyfinService.instance.getStreamUrl(itemId);
        final client = HttpClient()..findProxy = (_) => 'DIRECT';
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('Range', 'bytes=0-127');
        final response = await request.close();
        expect(response.statusCode, 206);
        await for (final chunk in response) byteCount += chunk.length;
        client.close();
        return {
          'sourceId': row['sourceId'],
          'itemId': itemId,
          'bytes': byteCount
        };
      };
      final open = Harness([
        UiCapability(
            media: () => media,
            resolveEntity: (id) async {
              final ref = await library.validatedSourceRef(id, 'episode');
              if (ref == null) return null;
              return {
                'sourcePlayback': await sources.play(ref[0], ref[1],
                    expectedServerId: ref.length == 3 ? ref[2] : null)
              };
            })
      ]);
      final played = await open.invokeJson('ui.open',
          {'entityId': episodes.first.episodeId}, Invocation(origin: 'gui'));
      expect(played, isA<Completed>());
      expect(byteCount, 128);
      print(jsonEncode({
        'observation': 'ui.open source episode with real server Range',
        'bytes': byteCount,
        'identityRequired': false
      }));
    }
    final indexed = await library.port!.browse(
        sourceId, sourceEntityRef(work.workId, 'work')![1],
        recursive: true);
    final remoteFile =
        ((indexed['entries'] as List).first as Map)['fileId'] as String;
    final localVideo =
        await File('${root.path}/local.mkv').writeAsBytes([1, 2, 3]);
    final localFile = await identities.ensureFile(localVideo.path);
    await media.bindBatch({
      'requestId': 'x48-shared-identity',
      'entries': [
        tmdbBinding(remoteFile),
        tmdbBinding(localFile, episodes: [2])
      ]
    }, Invocation(origin: 'harness_cli:x48'));
    await ui.meshLibrary!.refresh();
    await library.mutate(
        'put',
        [
          {
            'sourceId': 'local',
            'categoryId': 'bound',
            'title': '用户选的作品',
            'content': {
              'kind': 'condition',
              'filter': {
                'sourceIds': ['local', sourceId],
                'types': ['series']
              }
            }
          }
        ],
        Invocation(origin: 'harness_cli:x48'));
    final bound = await library.items('bound', limit: 5);
    expect(bound.total, 1);
    expect((await ui.episodes(work.workId)).length, 2);
    if (!bindOnly) {
      var read = 0;
      sources.playItem = (row, itemId, position) async {
        final client = HttpClient()..findProxy = (_) => 'DIRECT';
        final request = await client
            .getUrl(Uri.parse(JellyfinService.instance.getStreamUrl(itemId)));
        request.headers.set('Range', 'bytes=0-63');
        final response = await request.close();
        expect(response.statusCode, 206);
        await for (final chunk in response) read += chunk.length;
        client.close();
        return {'bytes': read, 'sourceId': row['sourceId'], 'itemId': itemId};
      };
      final remoteEpisode =
          (await ui.episodes((bound.items.single as UiWorkItem).work.workId))
              .firstWhere((e) => e.number == 1);
      final bridge = Harness([
        UiCapability(
            media: () => media,
            resolveEntity: (id) async {
              final result = await ui.meshLibrary!.open(id);
              final source = result!['sourceInfo'] as Map;
              return {
                'sourcePlayback': await sources.play(
                    source['sourceId'] as String, source['itemId'] as String,
                    expectedServerId: source['serverId'] as String?,
                    startPositionMs: result['resumeMs'] as int?)
              };
            })
      ]);
      expect(
          await bridge.invokeJson('ui.open',
              {'entityId': remoteEpisode.episodeId}, Invocation(origin: 'gui')),
          isA<Completed>());
      expect(read, 64);
      await expectLater(
          sources.play(sourceId, 'same-id',
              expectedServerId: 'different-server'),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.conflict)));
      print(jsonEncode({
        'observation':
            'bound merged episode routes through the same source play action',
        'rangeBytes': read,
        'wrongServerRejectedBeforePlayback': true
      }));
    }
    print(jsonEncode({
      'observation':
          'accepted identity merges local and Jellyfin in one condition',
      'total': bound.total,
      'sourceFacts': jsonDecode(
          (await jobs.database.query('next_library_index')).single['facts']
              as String),
      'unboundSecondEpisodeStillInOriginal':
          (await ui.episodes(work.workId)).length == 2
    }));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

final class _Direct extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
