// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/next/media/classic_projection.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_capability.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/media/provider_transport.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/media_sources/capability.dart';
import 'package:nipaplay/next/media_sources/service.dart';
import 'package:nipaplay/next/network/dandanplay_gateway.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/jellyfin_episode_mapping_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('X17 real Jellyfin identity binding and Classic readback/undo',
      () async {
    final credentials =
        jsonDecode(File('/tmp/nipa-next/testservers.json').readAsStringSync())
            as Map;
    final jc = credentials['jellyfin'] as Map;
    expect(Uri.parse(jc['base_url'] as String).host, '127.0.0.1');
    expect(Uri.parse(jc['base_url'] as String).port, 8096);
    final oldVault = CredentialStore.instance;
    final oldHttp = HttpOverrides.current;
    final oldDebug = debugPrint;
    final vault = MemoryVault();
    CredentialStore.instance = CredentialStore(vault, desktop: true);
    HttpOverrides.global = _DirectHttp();
    // Classic source clients log catalog metadata; retain only our result lines.
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({
      'server_profiles': '[]',
      'smb_connections': '[]',
      'webdav_connections': '[]'
    });
    PackageInfo.setMockInitialValues(
        appName: 'NipaPlay',
        packageName: 'nipaplay',
        version: 'X17',
        buildNumber: '1',
        buildSignature: '');
    final root = await Directory.systemTemp.createTemp('nipa-x17-live-');
    StorageService.debugAppStorageDirectoryOverride = root;
    final classic = await WatchHistoryDatabase.instance.database;
    final jobs = await SqliteJobStore.open(Directory('${root.path}/next'),
        factory: databaseFactoryFfi);
    final store = IdentityStore(jobs.database, 'x17-live');
    final sources = MediaSourcesService(store);
    await sources.initialize();
    final client = DandanplayHttpClient();
    final dandanplay = DandanplayMetadataProvider(
        HttpMetadataTransport.dandanplay(DandanplayGateway(client: client)));
    final media = MediaService(
        store: store,
        providers: [dandanplay, TmdbMetadataProvider(FixtureTransport('tmdb'))],
        classic: WatchHistoryMetadataPort(changed: () async {}),
        authorizedRoots: () => [],
        durationProbe: (_) =>
            throw StateError('Remote bytes must not be probed'));
    final engine = TaskEngine(
        store: jobs,
        ownerDeviceId: 'x17-live',
        executors: mediaSourcesExecutors(sources));
    sources.engine = engine;
    media.engine = engine;
    final harness = Harness([
      MediaSourcesCapability(sources),
      MediaCapability(media),
      TaskCapability(engine)
    ]);
    await engine.start();
    addTearDown(() async {
      await engine.close();
      await sources.close();
      await store.closeEvents();
      client.close();
      await WatchHistoryDatabase.instance.close();
      StorageService.debugAppStorageDirectoryOverride = null;
      await root.delete(recursive: true);
      CredentialStore.instance = oldVault;
      HttpOverrides.global = oldHttp;
      debugPrint = oldDebug;
    });

    Future<JsonMap> call(String action, JsonMap input) async {
      final outcome = await harness.invokeJson(
          action, input, Invocation(origin: 'x17-live'));
      expect(outcome, isA<Completed>(),
          reason: jsonEncode(outcome.toEnvelope()));
      final value = (outcome as Completed).value.toJson();
      expect(harness.lookup(action)!.spec.output.validate(value), isEmpty);
      return value;
    }

    Future<Job> wait(JsonMap result) async {
      var job = await engine.get(result['jobId'] as String);
      while (!job.state.isTerminal) {
        job = await engine.wait(job.jobId,
            afterRevision: job.revision, timeout: const Duration(seconds: 10));
      }
      expect(job.state, JobState.succeeded,
          reason: jsonEncode(job.receipt?.toJson()));
      return job;
    }

    final added = await call('media.sources.add', {
      'type': 'jellyfin',
      'name': 'X17 isolated Jellyfin',
      'url': jc['base_url'],
      'username': jc['user_name']
    });
    final sourceId = (added['source'] as Map)['sourceId'] as String;
    await wait(await call('media.sources.login', {
      'sourceId': sourceId,
      'method': 'password',
      'password': jc['password']
    }));
    final libraries =
        await call('media.sources.libraries', {'sourceId': sourceId});
    final libraryId = (libraries['libraries'] as List)
        .cast<Map>()
        .singleWhere((row) => row['name'] == '番剧')['id'] as String;
    final browse = await call('media.sources.browse',
        {'sourceId': sourceId, 'parentId': libraryId, 'recursive': true});
    final episodes = (browse['entries'] as List).cast<JsonMap>()
      ..sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));
    expect(episodes, hasLength(6));
    print(
        'X17 live Jellyfin: endpoint=127.0.0.1:8096; login=succeeded; episodes=${episodes.length}; numbers=${episodes.map((e) => e['number']).toList()}; kinds=${episodes.map((e) => e['kind']).toSet().toList()}; scopedFiles=${(await jobs.database.query('media_locations')).length}');

    final dc = credentials['dandanplay'] as Map;
    final login = await DandanplayService.login(
        dc['username'] as String, dc['password'] as String);
    expect(login['success'], true, reason: login['message'] as String?);
    final candidates = await dandanplay.search('莉可丽丝');
    print('X17 live Dandanplay search: ${jsonEncode([
          for (final c in candidates) {'id': c.ref.externalId, 'title': c.title}
        ])}');
    final selected = candidates.singleWhere((c) => c.title == '莉可丽丝');
    final catalogue = await dandanplay.get(selected.ref);
    expect(catalogue.episodes.length, greaterThanOrEqualTo(6));
    final mappingService = JellyfinEpisodeMappingService.instance;
    // Prime the old negative cache before projection.
    expect(
        await mappingService.getAnimeMapping(
            jellyfinSeriesId: episodes.first['seriesId'] as String? ??
                'item:${episodes.first['id']}',
            jellyfinSeasonId: episodes.first['seasonId'] as String?),
        isNull);
    final beforeAnime = await classic.query('jellyfin_dandanplay_mapping');
    final beforeEpisodes = await classic.query('jellyfin_episode_mapping');
    final beforeHistory = await classic.query('watch_history');
    final bind = await call('media.identity.bind_batch', {
      'requestId': 'x17-dandanplay-six',
      'entries': [
        for (var i = 0; i < 6; i++)
          {
            'kind': 'file',
            'entityId': episodes[i]['fileId'],
            'workRef': selected.ref.toJson(),
            'episodeRefs': [catalogue.episodes[i].ref.toJson()],
            'reason': 'X17 explicit temporary Jellyfin episode mapping',
            'evidence': [
              {
                'source': 'live-jellyfin',
                'detail':
                    'Lycoris Recoil episode ${i + 1}, live Dandanplay catalogue ${selected.ref.externalId}'
              }
            ]
          }
      ]
    });
    final readback = <JsonMap>[];
    for (var i = 0; i < 6; i++) {
      final row =
          await mappingService.getEpisodeMapping(episodes[i]['id'] as String);
      expect(row!['dandanplay_episode_id'].toString(),
          catalogue.episodes[i].ref.externalId);
      expect(row['dandanplay_anime_id'].toString(), selected.ref.externalId);
      readback.add({
        'number': i + 1,
        'animeId': row['dandanplay_anime_id'],
        'episodeId': row['dandanplay_episode_id'],
        'confirmed': row['confirmed']
      });
    }
    final animeReadback = await mappingService.getAnimeMapping(
        jellyfinSeriesId: episodes.first['seriesId'] as String? ??
            'item:${episodes.first['id']}',
        jellyfinSeasonId: episodes.first['seasonId'] as String?);
    expect(animeReadback!['dandanplay_anime_id'].toString(),
        selected.ref.externalId);
    expect(await classic.query('watch_history'), beforeHistory);
    print('X17 live bind/readback: ${jsonEncode({
          'acceptedFiles': (bind['entries'] as List).length,
          'classicAnimeRows':
              (await classic.query('jellyfin_dandanplay_mapping')).length,
          'classicEpisodes': readback,
          'primedNegativeCacheBypassed': true,
          'watchHistoryUnchanged': true
        })}');
    final undo = await call('media.identity.unbind_batch', {
      'requestId': 'x17-undo-dandanplay',
      'entries': [
        for (final episode in episodes)
          {
            'entityId': episode['fileId'],
            'reason': 'Undo temporary experiment identities'
          }
      ]
    });
    expect(await classic.query('jellyfin_dandanplay_mapping'), beforeAnime);
    expect(await classic.query('jellyfin_episode_mapping'), beforeEpisodes);
    final outcomes = [
      for (final entry in (undo['entries'] as List).cast<JsonMap>())
        ...(entry['classicProjection'] as List)
    ];
    expect(outcomes, hasLength(6));
    expect(outcomes, everyElement(containsPair('restored', true)));
    expect(
        await mappingService.getEpisodeMapping(episodes.first['id'] as String),
        isNull);
    print(
        'X17 live undo: restored=${outcomes.length}; animeTableEqualsBefore=true; episodeTableEqualsBefore=true; ClassicReadback=null');

    final tmdb = await call('media.identity.bind_batch', {
      'requestId': 'x17-tmdb',
      'entries': [tmdbBinding(episodes.first['fileId'] as String)]
    });
    final identityResult = await call(
        'media.identity.get', {'entityId': episodes.first['fileId']});
    final identity = identityResult['identity'] as Map;
    expect(
        (identity['bindings'] as List)
            .where((b) => b['status'] == 'accepted')
            .single['ref']['provider'],
        'tmdb');
    expect((tmdb['entries'] as List).single['classicProjectionId'], isNull);
    expect(await classic.query('jellyfin_dandanplay_mapping'), beforeAnime);
    expect(await classic.query('jellyfin_episode_mapping'), beforeEpisodes);
    print(
        'X17 live remote + TMDB fixture: binding=accepted; provider=tmdb; localEpisodeLink=true; classicProjectionId=null; ClassicTablesUnchanged=true; metadata=offline-catalogue-fixture');
    await call('media.identity.unbind_batch', {
      'requestId': 'x17-undo-tmdb',
      'entries': [
        {
          'entityId': episodes.first['fileId'],
          'reason': 'Undo temporary TMDB identity'
        }
      ]
    });
    await call('media.identity.bind_batch', {
      'requestId': 'x17-before-classic-rematch',
      'entries': [
        {
          'kind': 'file',
          'entityId': episodes.first['fileId'],
          'workRef': selected.ref.toJson(),
          'episodeRefs': [catalogue.episodes.first.ref.toJson()],
          'reason': 'Temporary mapping before Classic rematch'
        }
      ]
    });
    final manualCatalogue = await mappingService.createOrUpdateAnimeMapping(
        jellyfinSeriesId: episodes.first['seriesId'] as String? ?? '',
        jellyfinSeriesName: 'X17 Classic manual match',
        jellyfinSeasonId: episodes.first['seasonId'] as String?,
        dandanplayAnimeId: int.parse(selected.ref.externalId),
        dandanplayAnimeTitle: catalogue.title);
    await mappingService.recordEpisodeMapping(
        jellyfinEpisodeId: episodes.first['id'] as String,
        jellyfinIndexNumber: 1,
        dandanplayEpisodeId: int.parse(catalogue.episodes[1].ref.externalId),
        mappingId: manualCatalogue);
    expect(
        (await mappingService.getEpisodeMapping(
                episodes.first['id'] as String))!['dandanplay_episode_id']
            .toString(),
        catalogue.episodes[1].ref.externalId);
    final rematched = await classic.query('jellyfin_episode_mapping');
    final withdrawn = await harness.invokeJson(
        'media.identity.unbind_batch',
        {
          'requestId': 'x17-after-classic-rematch',
          'entries': [
            {
              'entityId': episodes.first['fileId'],
              'reason': 'Withdraw Agent identity after Classic manual rematch'
            }
          ]
        },
        Invocation(origin: 'x17-live'));
    expect((withdrawn as Failed).failure.code, FailureCode.conflict);
    expect(await classic.query('jellyfin_episode_mapping'), rematched);
    print(
        'X17 live Classic manual rematch: production recordEpisodeMapping readback=${catalogue.episodes[1].ref.externalId}; Agent undo=conflict; Classic rematch preserved=true');
    expect(await classic.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(await jobs.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    final remaining = await jobs.database.rawQuery(
        "SELECT b.id FROM media_bindings b JOIN media_entities e ON e.id=b.entity_id WHERE e.kind='file' AND b.status='accepted'");
    expect(remaining, isEmpty);
    print(
        'X17 live cleanup: both foreign_key_check=[]; no accepted file bindings remain; temporary directory removed by teardown');
  },
      skip: !const bool.fromEnvironment('NIPA_X17_REAL'),
      timeout: const Timeout(Duration(minutes: 3)));
}

class _DirectHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (url) =>
            ['127.0.0.1', 'localhost', '::1'].contains(url.host)
                ? 'DIRECT'
                : HttpClient.findProxyFromEnvironment(url);
}
