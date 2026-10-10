import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/host.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/danmaku/sources.dart';
import 'package:nipaplay/next/network/dandanplay_gateway.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'danmaku_test_support.dart';

final class _AbortClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await (request as http.Abortable).abortTrigger;
    throw http.RequestAbortedException();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureDanmakuHost host;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    host = FixtureDanmakuHost();
  });
  Matcher status(SourceStatus value) =>
      isA<SourceFailure>().having((e) => e.status, 'status', value);
  test(
      'related items preserve explicit platforms without inventing provenance or origin IDs',
      () async {
    final result = await DandanplayDanmakuSource(host,
            allowedHosts: const ['fixture.invalid'])
        .fetchChunk(
            ddpVideo, const DanmakuChunk(0, 0, 720000), DanmakuCancellation());
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
        DandanplayDanmakuSource(host, allowedHosts: const ['fixture.invalid'])
            .fetchChunk(ddpVideo, const DanmakuChunk(0, 0, 720000),
                DanmakuCancellation()),
        throwsA(status(SourceStatus.schemaChanged)));
    host.responses['dandanplay.comments'] = jsonBytes({'comments': []});
    final result = await DandanplayDanmakuSource(host,
            allowedHosts: const ['fixture.invalid'])
        .fetchChunk(
            ddpVideo, const DanmakuChunk(0, 0, 720000), DanmakuCancellation());
    expect(result.status, SourceStatus.validEmpty);
  });
  test('host gateway profiles reject redirects', () async {
    final requests = <http.Request>[];
    final client = MockClient((r) async {
      requests.add(r);
      return http.Response('{}', 302);
    });
    final transport = HttpDanmakuHost(
        dandanplay: DandanplayGateway(
            client: DandanplayHttpClient(
                inner: client,
                authorization: () =>
                    {'Authorization': 'Bearer fixture-token'})),
        interval: Duration.zero);
    await expectLater(
        transport.request(
            'dandanplay.comments', {'videoId': '7101'}, DanmakuCancellation()),
        throwsA(status(SourceStatus.accessDenied)));
    expect(requests.single.url.path, '/dandanplay/api/v2/comment/7101');
    expect(requests.single.followRedirects, isFalse);
    expect(requests.single.headers.containsKey('Cookie'), isFalse);
    client.close();
  });
  test(
      'HTTP 429 exposes a bounded retry time and malformed response does not leak body',
      () async {
    final client = MockClient((_) async => http.Response(
        'untrusted-response', 429,
        headers: {'retry-after': '5'}));
    final transport = HttpDanmakuHost(
        dandanplay: DandanplayGateway(
            client: DandanplayHttpClient(
                inner: client,
                authorization: () =>
                    {'Authorization': 'Bearer fixture-token'})),
        interval: Duration.zero);
    await expectLater(
        transport.request(
            'dandanplay.comments', {'videoId': '7101'}, DanmakuCancellation()),
        throwsA(status(SourceStatus.rateLimited)));
    client.close();
  });
  test('source-scoped host grants cannot invoke a different source profile',
      () async {
    final scoped = ScopedDanmakuHost(
        host,
        DandanplayDanmakuSource(host, allowedHosts: const ['fixture.invalid'])
            .describe);
    await expectLater(
        scoped.request('youku.minute', {'videoId': 'Xfixture', 'minute': 0},
            DanmakuCancellation()),
        throwsA(isA<Failure>()));
    expect(host.requests, isEmpty);
  });
  test(
      'HTTP timeout aborts its request without pretending the task was cancelled',
      () async {
    final client = _AbortClient();
    final transport = HttpDanmakuHost(
        dandanplay: DandanplayGateway(
            client: DandanplayHttpClient(
                inner: client,
                authorization: () =>
                    {'Authorization': 'Bearer fixture-token'})),
        interval: Duration.zero,
        timeout: const Duration(milliseconds: 1));
    final cancellation = DanmakuCancellation();
    await expectLater(
        transport.request(
            'dandanplay.comments', {'videoId': '7101'}, cancellation),
        throwsA(status(SourceStatus.transportFailed)));
    expect(cancellation.cancelled, false);
    client.close();
  });
}
