import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/export.dart';
import 'package:nipaplay/next/danmaku/host.dart';
import 'package:nipaplay/next/danmaku/local_source.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/danmaku/sources.dart';
import 'package:nipaplay/next/network/dandanplay_gateway.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/utils/dandanplay_comments.dart';
import 'package:nipaplay/utils/danmaku_parser.dart';
import 'package:nipaplay/utils/local_danmaku_file.dart';
import 'danmaku_test_support.dart';

void main() {
  late DanmakuFixture f;
  setUp(() async {
    f = DanmakuFixture();
    await f.open();
  });
  tearDown(() => f.close());
  JsonMap classic(String platform, String video,
          {String origin = 'auto_remote'}) =>
      {
        'trackId': platform == 'dandanplay' ? 'dandanplay' : 'local-fixture',
        'source': origin == 'local_file' ? 'local' : platform,
        'origin': origin,
        'platform': platform,
        'platformVideoId': video,
        'name': '合成轨道',
        'count': 1,
        'enabled': true,
        'filePath': origin == 'local_file' ? '/fixture/video.xml' : null,
        'bindingId': null
      };
  Future<JsonMap> attach(DanmakuVideo video, {bool refresh = false}) =>
      f.call('danmaku.attach', {
        'current': true,
        'video': video.toJson(),
        'reason': '合成同集证据',
        'requestId': refresh ? 'refresh' : 'attach',
        'refresh': refresh
      });

  test(
      'current and path register location-only identity without a scan or inferred work',
      () async {
    f.player.target = const DanmakuPlaybackTarget('/fixture/unindexed.mkv', 1);
    expect(
        (await f.call('danmaku.tracks', {'current': true}))['tracks'], isEmpty);
    final ids = await Future.wait(List.generate(
        4, (_) => f.identities.ensureFile('/fixture/unindexed.mkv')));
    expect(ids.toSet(), hasLength(1));
    final file = await f.identities.entity(ids.first);
    expect(file['kind'], 'file');
    expect(await f.jobs.database.query('media_entities'), hasLength(1));
    expect(await f.jobs.database.query('media_file_episodes'), isEmpty);
    final result = await f.call('danmaku.attach', {
      'path': '/fixture/unindexed.mkv',
      'video': biliVideo.toJson(),
      'reason': '合成证据',
      'requestId': 'path-attach'
    });
    await f.wait(result['jobId'] as String, JobState.succeeded);
    await f.identities.registerFile('/fixture/unindexed.mkv',
        {'size': 1, 'modifiedAt': 'fixture', 'headMd5': 'fixture'});
    expect((await f.identities.entity(ids.first))['revision'], 0);
    expect(
        (await f.service.store
            .binding(result['bindingId'] as String))['status'],
        'accepted');
  });

  test(
      'Classic dandanplay is reused, restored without network and refreshed only explicitly',
      () async {
    await f.file();
    f.player.classicTracks.add(classic('dandanplay', ddpVideo.videoId));
    final listed = (await f.call('danmaku.tracks', {}))['tracks'] as List;
    expect(listed.single['origin'], 'auto_remote');
    final bound = await attach(ddpVideo);
    expect(bound['status'], 'reused');
    expect(bound['jobId'], isNull);
    expect(f.host.requests, isEmpty);
    await f.service.refreshCurrent();
    await f.service.refreshCurrent();
    expect(f.player.reuseCount, 1);
    f.player.classicCache[ddpVideo.videoId] = {
      ...f.player.classicTracks.single
    };
    f.player.classicTracks.clear();
    await f.reopen();
    await f.service.refreshCurrent();
    expect(f.player.reuseCount, 2);
    expect(f.host.requests, isEmpty);
    final refreshed = await attach(ddpVideo, refresh: true);
    await f.wait(refreshed['jobId'] as String, JobState.succeeded);
    expect(f.host.requests.single['profile'], 'dandanplay.comments');
    expect(refreshed['bindingId'], bound['bindingId']);
  });

  test(
      'known local platform pool prevents remote request even without a platform session',
      () async {
    await f.file();
    f.player.classicTracks
        .add(classic('youku', youkuVideo.videoId, origin: 'local_file'));
    final bound = await attach(youkuVideo);
    expect(bound['status'], 'alreadyExists');
    expect(bound['jobId'], isNull);
    expect(
        await f.service.store
            .bindings((await f.identities.ensureFile('/fixture/video.mkv'))),
        isEmpty);
    expect(f.host.requests, isEmpty);
    final tracks =
        (await f.call('danmaku.tracks', {'current': true}))['tracks'] as List;
    expect(tracks.single['source'], 'local');
    expect(tracks.single['platform'], 'youku');
  });

  test(
      'out-of-local-range failures preserve complete local coverage and load that pool',
      () async {
    await f.file();
    f.player.target = const DanmakuPlaybackTarget('/fixture/video.mkv', 1,
        durationMs: 360000);
    f.host.failures['bilibili.segment:2'] =
        const SourceFailure(SourceStatus.schemaChanged);
    final result = await attach(biliVideo);
    final done = await f.wait(result['jobId'] as String, JobState.succeeded);
    final details = done.receipt!.details;
    expect(details['localRangeComplete'], isTrue);
    expect(details['complete'], isFalse);
    expect(details['status'], 'localRangeComplete');
    expect(details['partial'], isTrue);
    expect((details['outOfRangeFailures'] as List).single['index'], 1);
    expect(details['loaded'], isTrue);
    expect(f.player.data.values.single, hasLength(1));
  });

  test('a segment overlapping the local end still must succeed', () async {
    await f.file();
    f.player.target = const DanmakuPlaybackTarget('/fixture/video.mkv', 1,
        durationMs: 360001);
    f.host.failures['bilibili.segment:2'] =
        const SourceFailure(SourceStatus.schemaChanged);
    final result = await attach(biliVideo);
    final failed = await f.wait(result['jobId'] as String, JobState.failed);
    expect(failed.receipt!.details['localRangeComplete'], isFalse);
    expect(failed.receipt!.details['outOfRangeFailures'], isEmpty);
    expect(f.player.tracks, isEmpty);
  });

  test(
      'File and Episode bindings for the same platform video restore a single stable track',
      () async {
    final fileId = await f.file();
    final first = await attach(biliVideo);
    await f.wait(first['jobId'] as String, JobState.succeeded);
    final db = f.jobs.database;
    await db.insert('media_entities', {
      'id': 'episode-fixture',
      'kind': 'episode',
      'revision': 0,
      'attributes': '{}'
    });
    await db.insert('media_file_episodes', {
      'file_id': fileId,
      'episode_id': 'episode-fixture',
      'relation': 'episode',
      'ordinal': 1
    });
    final second = await f.service.store.attach('episode-fixture', biliVideo,
        '合成关联证据', null, Invocation(origin: 'mcp'));
    final key = (await f.service.store
        .binding(first['bindingId'] as String))['cache_key'] as String;
    await f.service.store.assignCache(second, key, 'fixture-assignment');
    final installed = f.player.installCount;
    await f.service.refreshCurrent();
    await f.service.refreshCurrent();
    expect(f.player.tracks, hasLength(1));
    expect(f.player.installCount, installed);
    f.player.classicTracks.add({
      ...classic('bilibili', '101', origin: 'binding'),
      'bindingId': first['bindingId']
    });
    final listed = (await f.call(
        'danmaku.tracks', {'entityId': 'episode-fixture'}))['tracks'] as List;
    expect(listed, hasLength(1));
    expect(
        listed.single['bindingIds'], containsAll([first['bindingId'], second]));
  });

  test(
      'failed explicit refresh keeps the committed pool and its restoration intact',
      () async {
    await f.file();
    final first = await attach(biliVideo);
    await f.wait(first['jobId'] as String, JobState.succeeded);
    final id = first['bindingId'] as String;
    final oldKey = (await f.service.store.binding(id))['cache_key'] as String;
    f.host.responses['bilibili.segment:1'] = biliSegment(text: '新的合成弹幕');
    f.host.failures['bilibili.segment:2'] =
        const SourceFailure(SourceStatus.schemaChanged);
    final refresh = await attach(biliVideo, refresh: true);
    await f.wait(refresh['jobId'] as String, JobState.failed);
    expect((await f.service.store.binding(id))['cache_key'], oldKey);
    expect((await f.service.store.entries(oldKey)).first.text, '合成弹幕样本内容');
    f.player.tracks.clear();
    await f.service.refreshCurrent();
    expect(f.player.data[id]!.first.text, '合成弹幕样本内容');
  });

  test(
      'Classic and Next normalize related origins identically and retain them through parsing',
      () async {
    final raw = {
      'p': '1,1,255,hash-fixture',
      'm': '合成相关弹幕',
      'cid': 4,
      'source': 'bilibili',
      'sourceVideoId': '101',
      'originalId': 'origin-fixture'
    };
    final normalized = parseDandanplayComment(raw);
    f.host.responses['dandanplay.comments'] = jsonBytes({
      'comments': [raw]
    });
    final result = await DandanplayDanmakuSource(f.host).fetchChunk(ddpVideo,
        const DanmakuChunk(0, 0, 720000), null, DanmakuCancellation());
    final parsed = parseDanmakuListInBackground([normalized]).single;
    expect(parsed['source'], result.entries.single.platform);
    expect(parsed['platformVideoId'], result.entries.single.originVideoId);
    expect(parsed['platformDanmakuId'], result.entries.single.platformId);
    expect(parseDandanplayComment({...raw, 'source': 7})['source'], 'unknown');
    expect(
        restoreDandanplayOrigins([
          {'source': 'dandanplay', 'time': 1, 'content': '旧缓存'}
        ]).single['source'],
        'unknown');
    expect(restoreDandanplayOrigins([normalized]).single['source'], 'bilibili');
  });

  test(
      'local source reads chatserver and chatid and exported raw JSON reimports with origin',
      () async {
    final file = await File('${f.root.path}/fixture.xml').writeAsString(
        '<i><chatserver>youku</chatserver><chatid>Xfixture</chatid><d p="1,1,25,255,0,0,hash,42">合成弹幕</d></i>');
    final source = LocalDanmakuSource((path) async => path);
    final located =
        (await source.resolve(file.path, DanmakuCancellation())).single;
    final localVideo = DanmakuVideo(
        sourceId: 'local',
        videoId: located.videoId,
        title: located.title,
        durationMs: 120000,
        objectType: 'file');
    final result = await source.fetchChunk(localVideo,
        const DanmakuChunk(0, 0, 120000), null, DanmakuCancellation());
    expect(result.entries.single.platform, 'youku');
    expect(result.entries.single.originVideoId, 'Xfixture');
    final unknown = parseLocalDanmakuBytes(
        utf8.encode('<i><d p="1,1,25,255,0,0,hash,42">合成</d></i>'));
    expect(unknown['platform'], 'unknown');
    final rawJson = parseLocalDanmakuBytes(utf8.encode(jsonEncode({
      'comments': [
        {
          'p': '1,1,255,hash',
          'm': '原始 JSON 合成弹幕',
          'source': 'bilibili',
          'sourceVideoId': '101',
          'originalId': 'fixture'
        }
      ]
    })));
    expect(
        parseDanmakuListInBackground(rawJson['comments'] as List)
            .single['content'],
        '原始 JSON 合成弹幕');
    await f.file();
    final attached = await attach(biliVideo);
    await f.wait(attached['jobId'] as String, JobState.succeeded);
    final exporter = DanmakuExporter(f.service.store, (path) async => path);
    final path = '${f.root.path}/export.json';
    await exporter.export(attached['bindingId'] as String, path, 'raw');
    final imported = parseLocalDanmakuBytes(await File(path).readAsBytes());
    expect(imported['platform'], 'bilibili');
    expect(imported['platformVideoId'], '101');
    final parsed = parseDanmakuListInBackground(imported['comments'] as List);
    expect(parsed, hasLength(2));
    expect(parsed.first['content'], '合成弹幕样本内容');
  });

  test('WBI title search is anonymous, signed, bounded and caches public keys',
      () async {
    final requests = <http.Request>[];
    const raw =
        'abcdefghijklmnopqrstuvwxyz012345abcdefghijklmnopqrstuvwxyz012345';
    const order = [
      46,
      47,
      18,
      2,
      53,
      8,
      23,
      32,
      15,
      50,
      10,
      31,
      58,
      3,
      45,
      35,
      27,
      43,
      5,
      49,
      33,
      9,
      42,
      19,
      29,
      28,
      14,
      39,
      12,
      38,
      41,
      13
    ];
    final key = [for (final i in order) raw[i]].join();
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('cookie')));
      expect(request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')));
      if (request.url.path.endsWith('/nav')) {
        return http.Response(
            jsonEncode({
              'code': -101,
              'data': {
                'isLogin': false,
                'wbi_img': {
                  'img_url': 'https://i.example/${raw.substring(0, 32)}.png',
                  'sub_url': 'https://i.example/${raw.substring(32)}.png'
                }
              }
            }),
            200);
      }
      final params = {...request.url.queryParameters};
      final signature = params.remove('w_rid');
      final keys = params.keys.toList()..sort();
      final query = keys
          .map((k) =>
              '${Uri.encodeComponent(k)}=${Uri.encodeComponent(params[k]!)}')
          .join('&');
      expect(signature, md5.convert(utf8.encode('$query$key')).toString());
      expect(params['keyword'], '合成剧集');
      return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'result': [
                {
                  'bvid': 'BVfixture',
                  'title': '<em class="keyword">合成</em> &amp; 剧集'
                }
              ]
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    addTearDown(client.close);
    final host = HttpDanmakuHost(
        publicClient: client,
        dandanplay:
            DandanplayGateway(client: DandanplayHttpClient(inner: client)),
        interval: Duration.zero);
    final source = BilibiliDanmakuSource(
        ScopedDanmakuHost(host, BilibiliDanmakuSource(host).describe));
    expect(source.describe.search, isTrue);
    for (var i = 0; i < 2; i++) {
      final videos = await source.search('合成剧集', DanmakuCancellation());
      expect(videos.single.videoId, 'BVfixture');
      expect(videos.single.objectType, 'bvid');
      expect(videos.single.title, '合成 & 剧集');
    }
    expect(requests, hasLength(3));
  });

  test(
      'URL trailing slash, multipart and season episode selector resolve exact video',
      () async {
    final source = BilibiliDanmakuSource(f.host);
    expect(
        (await source.resolve('https://www.bilibili.com/video/BVfixture/?p=2',
                DanmakuCancellation()))
            .single
            .videoId,
        '102');
    f.host.responses['bilibili.season'] = jsonBytes({
      'code': 0,
      'result': {
        'episodes': [
          {'id': 11, 'cid': 101, 'title': '11', 'duration': 720000},
          {'id': 12, 'cid': 102, 'title': '12', 'duration': 720000}
        ]
      }
    });
    expect(
        (await source.resolve(
                'https://www.bilibili.com/bangumi/play/ss10/?ep_id=12',
                DanmakuCancellation()))
            .single
            .videoId,
        '102');
    expect(
        (await source.resolve('https://www.bilibili.com/bangumi/play/ep11/',
                DanmakuCancellation()))
            .single
            .videoId,
        '101');
  });
}
