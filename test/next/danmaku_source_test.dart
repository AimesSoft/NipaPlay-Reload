import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/next/danmaku/host.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/danmaku/sources.dart';
import 'danmaku_test_support.dart';

final class _AbortClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await (request as http.Abortable).abortTrigger;
    throw http.RequestAbortedException();
  }
}

void main() {
  late FixtureDanmakuHost host;
  setUp(() => host = FixtureDanmakuHost());
  Matcher status(SourceStatus value) =>
      isA<SourceFailure>().having((e) => e.status, 'status', value);
  test(
      'related items preserve explicit platforms without inventing provenance or origin IDs',
      () async {
    final result = await DandanplayDanmakuSource(host).fetchChunk(ddpVideo,
        const DanmakuChunk(0, 0, 720000), null, DanmakuCancellation());
    expect(result.entries.map((e) => e.platform),
        ['bilibili', 'acfun', 'unknown']);
    expect(result.entries.first.platformId, '9007199254740993');
    expect(result.entries.first.sourceEntryId, '1');
    expect(result.entries[1].platformId, isNull);
    expect(result.entries.last.sender, isNull);
    expect(result.coverage, 'relatedPool');
    expect(result.entries.last.toPlayer()['source'], 'unknown');
  });
  test('missing comments are a schema failure, not a valid empty pool',
      () async {
    host.responses['dandanplay.comments'] = jsonBytes({'success': true});
    await expectLater(
        DandanplayDanmakuSource(host).fetchChunk(ddpVideo,
            const DanmakuChunk(0, 0, 720000), null, DanmakuCancellation()),
        throwsA(status(SourceStatus.schemaChanged)));
    host.responses['dandanplay.comments'] = jsonBytes({'comments': []});
    final result = await DandanplayDanmakuSource(host).fetchChunk(ddpVideo,
        const DanmakuChunk(0, 0, 720000), null, DanmakuCancellation());
    expect(result.status, SourceStatus.validEmpty);
  });
  test('Bilibili resolves every part and URL p selects the exact part',
      () async {
    final source = BilibiliDanmakuSource(host);
    expect(
        await source.resolve('BVfixture', DanmakuCancellation()), hasLength(2));
    final chosen = await source.resolve(
        'https://www.bilibili.com/video/BVfixture?p=2', DanmakuCancellation());
    expect(chosen.single.videoId, '102');
    expect(chosen.single.durationMs, 420000);
  });
  test(
      'Bilibili protobuf retains IDs above JS precision, modes and source milliseconds',
      () {
    final entry = decodeBilibili(biliSegment(mode: 6), biliVideo).single;
    expect(entry.platformId, '9007199254740993');
    expect(entry.sourceTimeMs, 1000);
    expect(entry.mode, 6);
    expect(entry.toPlayer()['type'], 'scroll');
    expect(entry.toPlayer()['originalMode'], 6);
    final wireId = bytesField(1, [
      8,
      ...varint(BigInt.parse('9223372036854775807')),
      ...numberField(2, 0),
      ...numberField(3, 1),
      ...numberField(4, 25),
      ...numberField(5, 255),
      ...bytesField(7, utf8.encode('合成'))
    ]);
    expect(decodeBilibili(wireId, biliVideo).single.platformId,
        '9223372036854775807');
  });
  test(
      'protobuf skips unknown fields but rejects truncation, JSON and oversized varints',
      () {
    expect(
        decodeBilibili([
          ...biliSegment(),
          ...bytesField(9, [1, 2])
        ], biliVideo),
        hasLength(1));
    expect(decodeBilibili([], biliVideo), isEmpty);
    for (final bytes in [
      [10, 127, 1],
      [8, ...List.filled(11, 128)],
      jsonBytes({'code': -403})
    ]) {
      expect(() => decodeBilibili(bytes, biliVideo),
          throwsA(status(SourceStatus.schemaChanged)));
    }
  });
  test(
      'segment plans use half-open ranges and do not add an extra exact-end minute',
      () {
    final source = YoukuDanmakuSource(host);
    expect(source.planFetch(youkuVideo, 0, 120000).map((c) => c.index), [0, 1]);
    expect(
        source.planFetch(youkuVideo, 60000, 120000).map((c) => c.index), [1]);
    expect(
        () => source.planFetch(youkuVideo, 120000, 120000), throwsA(anything));
  });
  test(
      'Youku valid empty requires business success and both nested result fields',
      () async {
    final source = YoukuDanmakuSource(host);
    for (final payload in [
      <String, Object?>{},
      {
        'ret': ['SUCCESS::ok'],
        'data': {}
      },
      {
        'ret': ['SUCCESS::ok'],
        'data': {'result': '{}'}
      },
      {
        'ret': ['SUCCESS::ok'],
        'data': {
          'result': jsonEncode({'data': {}})
        }
      }
    ]) {
      host.responses['youku.minute:0'] = jsonBytes(payload);
      await expectLater(
          source.fetchChunk(
              youkuVideo,
              const DanmakuChunk(0, 0, 60000),
              const DanmakuAccess('session-ref-fixture'),
              DanmakuCancellation()),
          throwsA(status(SourceStatus.schemaChanged)));
    }
    host.responses['youku.minute:0'] = jsonBytes(youkuPayload([]));
    expect(
        (await source.fetchChunk(
                youkuVideo,
                const DanmakuChunk(0, 0, 60000),
                const DanmakuAccess('session-ref-fixture'),
                DanmakuCancellation()))
            .status,
        SourceStatus.validEmpty);
  });
  test('Youku token expiry stops fetching and never becomes an empty success',
      () async {
    host.responses['youku.minute:0'] = jsonBytes({
      'ret': ['FAIL_SYS_TOKEN_EXOIRED::expired'],
      'data': {}
    });
    await expectLater(
        YoukuDanmakuSource(host).fetchChunk(
            youkuVideo,
            const DanmakuChunk(0, 0, 60000),
            const DanmakuAccess('session-ref-fixture'),
            DanmakuCancellation()),
        throwsA(status(SourceStatus.authenticationRequired)));
  });
  test(
      'Youku uses millisecond time and does not turn its format into Bilibili identity',
      () async {
    final entry = (await YoukuDanmakuSource(host).fetchChunk(
            youkuVideo,
            const DanmakuChunk(0, 0, 60000),
            const DanmakuAccess('session-ref-fixture'),
            DanmakuCancellation()))
        .entries
        .single;
    expect(entry.platform, 'youku');
    expect(entry.toPlayer()['source'], 'youku');
    expect(entry.sourceTimeMs, 1000);
    expect(entry.mode, 5);
    expect(entry.sender, isNull);
  });
  test('missing Youku catalogue videos is a schema failure', () async {
    host.responses['youku.episodes'] = jsonBytes({'total': 0});
    await expectLater(
        YoukuDanmakuSource(host)
            .listEpisodes('show-fixture', 1, DanmakuCancellation()),
        throwsA(status(SourceStatus.schemaChanged)));
  });
  test(
      'host fixed profiles send only public requests and reject redirects and missing session channel',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((r) async {
      requests.add(r);
      return http.Response('{}', 302);
    });
    final transport = HttpDanmakuHost(
        publicClient: client,
        dandanplayClient: client,
        dandanplayBase: () async => Uri.https('example.invalid'),
        dandanplayHeaders: (_) async => {},
        interval: Duration.zero);
    await expectLater(
        transport.request('bilibili.segment',
            {'videoId': '101', 'segmentIndex': 1}, null, DanmakuCancellation()),
        throwsA(status(SourceStatus.accessDenied)));
    expect(requests.single.url.host, 'api.bilibili.com');
    expect(requests.single.followRedirects, isFalse);
    expect(requests.single.headers.containsKey('Cookie'), isFalse);
    await expectLater(
        transport.request('youku.minute', {'videoId': 'Xfixture', 'minute': 0},
            const DanmakuAccess('session-ref-fixture'), DanmakuCancellation()),
        throwsA(status(SourceStatus.authenticationRequired)));
    expect(requests, hasLength(1));
    client.close();
  });
  test(
      'HTTP 429 exposes a bounded retry time and malformed response does not leak body',
      () async {
    final client = MockClient((_) async => http.Response(
        'untrusted-response', 429,
        headers: {'retry-after': '5'}));
    final transport = HttpDanmakuHost(
        publicClient: client,
        dandanplayClient: client,
        dandanplayBase: () async => Uri.https('example.invalid'),
        dandanplayHeaders: (_) async => {},
        interval: Duration.zero);
    await expectLater(
        transport.request('bilibili.segment',
            {'videoId': '101', 'segmentIndex': 1}, null, DanmakuCancellation()),
        throwsA(status(SourceStatus.rateLimited)));
    client.close();
  });
  test('source-scoped host grants cannot invoke a different source profile',
      () async {
    final scoped =
        ScopedDanmakuHost(host, BilibiliDanmakuSource(host).describe);
    await expectLater(
        scoped.request('youku.minute', {'videoId': 'Xfixture', 'minute': 0},
            const DanmakuAccess('session-ref-fixture'), DanmakuCancellation()),
        throwsA(anything));
    expect(host.requests, isEmpty);
    expect(scoped.sessionAvailable('youku'), false);
  });
  test(
      'HTTP timeout aborts its request without pretending the task was cancelled',
      () async {
    final client = _AbortClient();
    final transport = HttpDanmakuHost(
        publicClient: client,
        dandanplayClient: client,
        dandanplayBase: () async => Uri.https('example.invalid'),
        dandanplayHeaders: (_) async => {},
        interval: Duration.zero,
        timeout: const Duration(milliseconds: 1));
    final cancellation = DanmakuCancellation();
    await expectLater(
        transport.request('bilibili.segment',
            {'videoId': '101', 'segmentIndex': 1}, null, cancellation),
        throwsA(status(SourceStatus.transportFailed)));
    expect(cancellation.cancelled, false);
    client.close();
  });
  test('protobuf omitted scalar values retain protocol defaults at zero time',
      () {
    final message = bytesField(1, [...bytesField(7, utf8.encode('零时刻合成弹幕'))]);
    final entry = decodeBilibili(message, biliVideo).single;
    expect(entry.sourceTimeMs, 0);
    expect(entry.colorRgb, 0);
    expect(entry.platformId, isNull);
  });
}
