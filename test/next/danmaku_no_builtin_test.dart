import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/export.dart';
import 'package:nipaplay/next/danmaku/host.dart';
import 'package:nipaplay/next/danmaku/local_source.dart';
import 'package:nipaplay/next/danmaku/runtime.dart';
import 'package:nipaplay/next/danmaku/sources.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/network/dandanplay_gateway.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'danmaku_test_support.dart';

final class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('gateway, adjacent local file and import persist playable pools',
      () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <JsonMap>[];
    server.listen((request) async {
      requests.add({
        'path': request.uri.path,
        'authenticated': request.headers.value('Authorization') ==
            'Bearer synthetic-loopback-token',
        'withRelated': request.uri.queryParameters['withRelated']
      });
      final episode = {'episodeId': 7101, 'episodeTitle': '合成集'};
      final anime = {
        'animeTitle': '合成作品',
        'episodes': [episode]
      };
      final payload = switch (request.uri.path) {
        '/dandanplay/api/v2/search/episodes' => {
            'animes': [anime]
          },
        '/dandanplay/api/v2/bangumi/7001' => {'bangumi': anime},
        '/dandanplay/api/v2/comment/7101' => {
            'comments': [
              {'cid': 1, 'p': '1,1,16777215,hash', 'm': '回环网关弹幕'}
            ]
          },
        _ => throw StateError('Unexpected gateway path ${request.uri.path}')
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(payload));
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}/dandanplay';
    await NetworkSettings.setDandanplayServer(base);
    final client = DandanplayHttpClient(
        inner: IOClient(_DirectHttpOverrides().createHttpClient(null)),
        authorization: () =>
            {'Authorization': 'Bearer synthetic-loopback-token'});
    addTearDown(client.close);
    final host = HttpDanmakuHost(
        dandanplay: DandanplayGateway(client: client), interval: Duration.zero);
    final declaration =
        DandanplayDanmakuSource(host, allowedHosts: const ['127.0.0.1']);
    void registerSources() => f.service.sources
      ..clear()
      ..addAll({
        'dandanplay': DandanplayDanmakuSource(
            ScopedDanmakuHost(host, declaration.describe),
            allowedHosts: const ['127.0.0.1']),
        'local': LocalDanmakuSource((path) async => path)
      });
    registerSources();
    final videoPath = '${f.root.path}/video.mkv';
    final fileId = await f.file(path: videoPath);
    final sources = (await f.call('danmaku.sources', {}))['sources'] as List;
    expect(sources.map((s) => (s as Map)['sourceId']), ['dandanplay', 'local']);
    expect(sources.every((s) => !(s as Map).containsKey('sessionAvailable')),
        true);
    final search = await f
        .call('danmaku.search', {'sourceId': 'dandanplay', 'query': '合成作品'});
    expect(search['results'], hasLength(1));
    final episodes = await f
        .call('danmaku.episodes', {'sourceId': 'dandanplay', 'workId': '7001'});
    expect(episodes['results'], hasLength(1));
    final resolved = await f
        .call('danmaku.resolve', {'sourceId': 'dandanplay', 'locator': '7101'});
    final ddp = await f.call('danmaku.attach', {
      'entityId': fileId,
      'video': {...resolved['video'] as Map, 'durationMs': 120000},
      'reason': '回环证据',
      'requestId': 'gateway'
    });
    await f.wait(ddp['jobId'] as String, JobState.succeeded);
    expect(requests, hasLength(3));
    expect(requests.every((r) => r['authenticated'] == true), true);
    expect(requests.last['withRelated'], 'true');
    final xml = await File('${f.root.path}/video.xml').writeAsString(
        '<i><chatserver>youku</chatserver><chatid>Xlocal</chatid>'
        '<d p="1,1,25,255,0,0,hash,42">视频旁本地弹幕</d></i>');
    final local = await f
        .call('danmaku.resolve', {'sourceId': 'local', 'locator': xml.path});
    final attached = await f.call('danmaku.attach', {
      'entityId': fileId,
      'video': {...local['video'] as Map, 'durationMs': 120000},
      'reason': '视频旁文件',
      'requestId': 'local'
    });
    await f.wait(attached['jobId'] as String, JobState.succeeded);
    final importedFile =
        await File('${f.root.path}/browser.json').writeAsString(jsonEncode([
      {'sourceTimeMs': 1250, 'text': '交入弹幕', 'mode': 5, 'colorRgb': 255}
    ]));
    final imported = await f.call('danmaku.import', {
      'filePath': importedFile.path,
      'platform': 'bilibili',
      'platformVideoId': 'BVbrowser',
      'entityId': fileId
    });
    expect(imported['count'], 1);
    expect(imported['loaded'], true);
    await xml.delete();
    await importedFile.delete();
    await f.reopen();
    registerSources();
    await f.service.refreshCurrent();
    expect(f.player.data.values.map((entries) => entries.single.text).toSet(),
        {'回环网关弹幕', '视频旁本地弹幕', '交入弹幕'});
    expect(requests, hasLength(3));
    // ignore: avoid_print
    print('X6 retained: sources=[dandanplay,local]; gateway requests=3; '
        'paths=${requests.map((r) => r['path']).join(',')}; '
        'authenticated=true; local=1; import=1; reopened playable pools=3; '
        'source files removed; restore network requests=0');
  });

  test('legacy platform facts survive reopening without registered sources',
      () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final fileId = await f.file();
    final legacyVideos = [
      const DanmakuVideo(
          sourceId: 'youku',
          videoId: 'Xlegacy',
          title: '旧优酷',
          durationMs: 120000),
      const DanmakuVideo(
          sourceId: 'bilibili',
          videoId: '101',
          title: '旧 B 站',
          durationMs: 720000,
          objectType: 'cid')
    ];
    final ids = <String>[];
    for (final video in legacyVideos) {
      final id = await f.service.store
          .attach(fileId, video, '历史证据', null, Invocation(origin: 'mcp'));
      ids.add(id);
      final key = stableMediaId('danmaku-cache', [
        video.sourceId,
        video.videoId,
        '1',
        video.sourceId == 'youku'
            ? ['openapi.youku.com', 'acs.youku.com']
            : ['api.bilibili.com'],
        video.sourceId == 'youku'
            ? jsonEncode(
                {'namespace': 'next.platform-session', 'key': 'youku.v1'})
            : 'public',
        'related=true'
      ]);
      await f.service.store.saveChunk(
          key,
          DanmakuChunk(0, 0, video.durationMs),
          DanmakuChunkResult([
            DanmakuEntry(
                sourceId: video.sourceId,
                videoId: video.videoId,
                platform: video.sourceId,
                originVideoId: video.videoId,
                platformId: '9007199254740993',
                sourceTimeMs: 1000,
                text: '旧 ${video.sourceId} 弹幕',
                mode: 5,
                colorRgb: 255)
          ]));
      await f.service.store
          .assignCache(id, key, 'legacy-fetch-${video.sourceId}');
      final date = DateTime.utc(2025);
      final job = Job(
          jobId: 'legacy-fetch-${video.sourceId}',
          type: 'danmaku.fetch',
          title: 'Historical fetch',
          state: JobState.succeeded,
          phase: 'verify',
          progress: JobProgress(completed: 1, total: 1, unit: 'chunks'),
          createdAt: date,
          updatedAt: date,
          ownerDeviceId: 'fixture-device',
          revision: 0,
          sideEffectCommitted: true,
          input: {
            'video': video.toJson(),
            'credentialRef': 'old-opaque-reference'
          },
          checkpoint: {
            'cacheKey': key,
            'completedChunks': [0]
          },
          receipt: JobReceipt(
              verification: VerificationLevel.verified,
              details: {'cacheKey': key, 'complete': true}));
      await f.jobs.commit(
          job,
          JobEvent(
              jobId: job.jobId,
              revision: job.revision,
              kind: 'succeeded',
              at: date,
              snapshot: job.toJson()),
          expectedRevision: null);
    }
    await f.jobs.database.update('danmaku_cache_chunks',
        {'fetched_at': DateTime.utc(2025).toIso8601String()});
    const tables = [
      'danmaku_bindings',
      'danmaku_cache_chunks',
      'media_external_objects',
      'danmaku_binding_events',
      'jobs',
      'job_events'
    ];
    final before = {
      for (final table in tables) table: await f.jobs.database.query(table)
    };
    await f.reopen();
    final runtime = await DanmakuRuntime.create(f.identities,
        authorizeLocalFile: (path) async => path);
    addTearDown(runtime.close);
    f.service.sources
      ..clear()
      ..addAll(runtime.service.sources);
    await f.service.refreshCurrent();
    expect(f.player.data, hasLength(2));
    for (final table in tables) {
      expect(await f.jobs.database.query(table), before[table]);
    }
    final tracks = (await f
        .call('danmaku.tracks', {'entityId': fileId}))['tracks'] as List;
    expect(tracks.map((t) => (t as Map)['platform']).toSet(),
        {'youku', 'bilibili'});
    expect(tracks.every((t) => (t as Map)['loaded'] == true), true);
    for (final video in legacyVideos) {
      for (final action in [
        'danmaku.resolve',
        'danmaku.fetch',
        'danmaku.attach'
      ]) {
        final input = switch (action) {
          'danmaku.resolve' => {
              'sourceId': video.sourceId,
              'locator': video.videoId
            },
          'danmaku.fetch' => {
              'video': video.toJson(),
              'requestId': 'legacy-refresh'
            },
          _ => {
              'entityId': fileId,
              'video': video.toJson(),
              'reason': '刷新',
              'requestId': 'legacy-refresh',
              'refresh': true
            }
        };
        final outcome = await f.harness
            .invokeJson(action, input, Invocation(origin: 'mcp'));
        expect((outcome as Failed).failure.code, FailureCode.notFound);
      }
    }
    expect(await f.jobs.list(), hasLength(2));
    for (final table in tables) {
      expect(await f.jobs.database.query(table), before[table]);
    }
    final exporter = DanmakuExporter(f.service.store, (path) async => path);
    f.service.exporter = exporter;
    for (var i = 0; i < ids.length; i++) {
      final result = await f.call('danmaku.export', {
        'bindingId': ids[i],
        'path': '${f.root.path}/old-$i.json',
        'view': 'raw'
      });
      expect(result['count'], 1);
      final entry = f.player.data[ids[i]]!.single;
      expect(entry.toPlayer()['source'], legacyVideos[i].sourceId);
      expect(entry.toPlayer()['platformDanmakuId'], '9007199254740993');
      await f.call('danmaku.update', {
        'changes': [
          {
            'bindingId': ids[i],
            'expectedRevision': 0,
            'offsetMs': 1500,
            'displayFold': false
          }
        ]
      });
      expect(f.player.loaded(ids[i])!['offsetMs'], 1500);
      expect(f.player.data[ids[i]]!.single.sourceTimeMs, 1000);
    }
    expect(await f.jobs.database.query('danmaku_cache_chunks'),
        before['danmaku_cache_chunks']);
    final date = DateTime.now().toUtc();
    final pending = Job(
        jobId: 'legacy-pending-youku',
        type: 'danmaku.fetch',
        title: 'Interrupted historical fetch',
        state: JobState.interrupted,
        phase: 'fetch',
        progress: JobProgress(completed: 1, total: 2, unit: 'chunks'),
        createdAt: date,
        updatedAt: date,
        ownerDeviceId: 'fixture-device',
        revision: 0,
        sideEffectCommitted: true,
        input: {
          'video': legacyVideos.first.toJson(),
          'bindingId': ids.first,
          'credentialRef': 'old-opaque-reference',
          'startMs': 0,
          'endMs': 120000
        },
        checkpoint: {
          'cacheKey': (await f.service.store.binding(ids.first))['cache_key'],
          'completedChunks': [0]
        });
    await f.jobs.commit(
        pending,
        JobEvent(
            jobId: pending.jobId,
            revision: 0,
            kind: 'interrupted',
            at: date,
            snapshot: pending.toJson()),
        expectedRevision: null);
    await f.reopen();
    final stopped = await f.wait(pending.jobId, JobState.failed);
    expect(stopped.error!.code, FailureCode.notFound);
    expect(stopped.input, pending.input);
    expect(stopped.checkpoint, pending.checkpoint);
    expect(await f.jobs.database.query('danmaku_cache_chunks'),
        before['danmaku_cache_chunks']);
    await f.service.refreshCurrent();
    expect(f.player.data, hasLength(2));
    // ignore: avoid_print
    print('X6 legacy: platforms=[youku,bilibili]; reopened bindings=2; '
        'expired cache rows=2; unchanged fact tables=6; loaded tracks=2; '
        'resolve/fetch/attach refresh=not_found (6 calls); new jobs=0; '
        'exports=2; offset/displayFold updates=2; original sourceTimeMs=1000; '
        'old pending fetch=failed/not_found; checkpoint and cache preserved');
  });
}
