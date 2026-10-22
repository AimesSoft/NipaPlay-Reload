import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/download_capability.dart';
import 'package:nipaplay/next/capabilities/download_metadata_capability.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/downloads/download_executor.dart';
import 'package:nipaplay/next/downloads/download_service.dart';
import 'package:nipaplay/next/downloads/download_source.dart';
import 'package:nipaplay/next/downloads/http_download_backend.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';

Uint8List bytesOf(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + 7) & 0xff]);

final class Resource {
  Resource(this.bytes);
  final Uint8List bytes;
  bool ranges = true, denyHead = false;
  String? disposition, etag;
  int? status;
  String? redirectTo;

  /// Drop the connection once after this many body bytes.
  int? dropAfter;

  /// Hang (until [release] completes, or forever) after this many body bytes.
  int? holdAt;
  Completer<void>? release;
}

final class TestServer {
  final resources = <String, Resource>{};
  final requests = <({String method, String path, String? range})>[];
  late HttpServer server;
  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((request) async {
      try {
        await _handle(request);
      } catch (_) {
        // The client went away (pause, cancel): not the server's problem.
      }
    });
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;
    final range = request.headers.value('range');
    requests.add((method: request.method, path: path, range: range));
    final res = resources[path];
    if (res == null) {
      response.statusCode = 404;
      await response.close();
      return;
    }
    if (res.redirectTo != null) {
      response.statusCode = 302;
      response.headers.set('location', res.redirectTo!);
      await response.close();
      return;
    }
    if (res.status != null) {
      response.statusCode = res.status!;
      await response.close();
      return;
    }
    if (request.method == 'HEAD' && res.denyHead) {
      response.statusCode = 405;
      await response.close();
      return;
    }
    var start = 0;
    if (res.ranges && range != null) {
      final match = RegExp(r'bytes=(\d+)-').firstMatch(range);
      if (match != null) {
        start = int.parse(match.group(1)!);
        response.statusCode = 206;
        response.headers.set('content-range',
            'bytes $start-${res.bytes.length - 1}/${res.bytes.length}');
      }
    }
    if (res.ranges) response.headers.set('accept-ranges', 'bytes');
    if (res.disposition != null) {
      response.headers.set('content-disposition', res.disposition!);
    }
    if (res.etag != null) response.headers.set('etag', res.etag!);
    response.headers.contentType = ContentType('application', 'octet-stream');
    response.contentLength = res.bytes.length - start;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    var sent = 0;
    while (start + sent < res.bytes.length) {
      if (res.dropAfter != null && sent >= res.dropAfter!) {
        res.dropAfter = null;
        await response.flush();
        // Closing short of Content-Length tears the connection down.
        try {
          await response.close();
        } catch (_) {}
        return;
      }
      if (res.holdAt != null && sent >= res.holdAt!) {
        await (res.release ??= Completer<void>()).future;
        res.holdAt = null;
      }
      final limit = res.holdAt != null && sent < res.holdAt!
          ? start + res.holdAt!
          : res.bytes.length;
      final end = (start + sent + 8192).clamp(0, limit);
      response.add(res.bytes.sublist(start + sent, end));
      sent = end - start;
      await response.flush();
    }
    await response.close();
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  late Directory root, downloadsDirectory;
  late TestServer server;
  late HttpDownloadBackend http;
  late FakeDownloadLibrary library;
  late DownloadExecutor executor;
  late TaskEngine engine;
  late JobStore store;
  late DownloadService downloads;
  late Harness harness;
  var skew = Duration.zero;

  HttpDownloadBackend newBackend() => HttpDownloadBackend(
      defaultDirectory: () async => downloadsDirectory.path,
      stateDirectory: Directory('${root.path}/state'),
      clientFactory: () => HttpClient()..findProxy = (_) => 'DIRECT',
      clock: () => DateTime.now().toUtc().add(skew),
      retryDelay: (_) => const Duration(milliseconds: 20),
      idleTimeout: const Duration(seconds: 5));

  Future<void> connect({Duration stallAfter = const Duration(minutes: 5)}) async {
    final backends = DownloadBackends([http]);
    executor = DownloadExecutor(
        backends: backends,
        library: library,
        isEnabled: () async => true,
        pollInterval: const Duration(milliseconds: 10),
        importRetryDelay: const Duration(milliseconds: 100),
        stallAfter: stallAfter);
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'device-test',
        executors: [executor]);
    executor.engine = engine;
    downloads = DownloadService(
        engine: engine,
        executor: executor,
        backends: backends,
        library: library);
    harness = Harness([
      TaskCapability(engine),
      DownloadCapability(
          downloads: downloads,
          sources: DownloadSources(Directory('${root.path}/metadata'))),
      DownloadMetadataCapability(
          DownloadSources(Directory('${root.path}/metadata')),
          () async => true,
          httpBackend: http),
    ]);
    await engine.start();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('next-http-download-');
    downloadsDirectory = await Directory('${root.path}/downloads').create();
    server = TestServer();
    await server.start();
    http = newBackend();
    store = MemoryJobStore();
    library = FakeDownloadLibrary();
    skew = Duration.zero;
    await connect();
  });
  tearDown(() async {
    final jobs = await engine.list();
    await engine.close();
    for (final job in jobs) {
      await executor.quiesce(job.jobId);
    }
    await http.close();
    await server.stop();
    await root.delete(recursive: true);
  });

  Future<JsonMap> call(String action, JsonMap input) async {
    final outcome = await harness.invokeJson(
        action, input, Invocation(origin: 'mcp', id: 'http-test'));
    expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
    final result = (outcome as Completed).value.toJson();
    expect(harness.lookup(action)!.spec.output.validate(result), isEmpty);
    return result;
  }

  Future<String> add(String path, {JsonMap? extra}) async {
    final result = await call('download.add', {
      'source': server.url(path),
      'backend': {'kind': 'http'},
      ...?extra,
    });
    return (result['job'] as Map)['jobId'] as String;
  }

  Future<void> eventually(Future<bool> Function() condition,
      {String? reason}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) fail(reason ?? 'condition never held');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<DownloadSnapshot> snapshot(String jobId) async =>
      (await downloads.snapshot(jobId))!;

  Future<void> bytesAtLeast(String jobId, int bytes) => eventually(
      () async => ((await downloads.snapshot(jobId))?.completed ?? 0) >= bytes,
      reason: 'download never reached $bytes bytes');

  test('a video downloads, is registered and the receipt says it was not checked',
      () async {
    final data = bytesOf(100000);
    server.resources['/media/Sintel.mkv'] = Resource(data);
    final jobId = await add('/media/Sintel.mkv');
    final done = await untilState(engine, jobId, JobState.succeeded);
    final file = File('${downloadsDirectory.path}/Sintel.mkv');
    expect(await file.readAsBytes(), data);
    expect(File('${file.path}.nipaplay-part').existsSync(), false);
    expect(library.scans.single, [file.path]);
    final details = done.receipt!.details;
    expect(details['downloadComplete'], true);
    expect(details['checksum'], {
      'algorithm': 'sha256',
      'requested': false,
      'expected': null,
      'actual': sha256.convert(data).toString(),
      'matched': null,
    });
    final row = (details['files'] as List).single as Map;
    expect(row['imported'], true);
    expect(row['expectedSize'], data.length);
    expect(done.checkpoint['completedFiles'], hasLength(1));
    final read = await call('download.read', {'jobId': jobId});
    final task = read['task'] as Map;
    expect(task['infoHash'], startsWith('http-'));
    expect(task['title'], 'Sintel.mkv');
    expect(task['totalBytes'], data.length);
    expect((task['health'] as Map)['connectedPeers'], isNull);
    expect(((task['health'] as Map)['http'] as Map)['statusCode'], 200);
    expect((task['files'] as List).single['playable'], true);
  });

  test('a zip is reported as it is: not a video, not unpacked, not imported',
      () async {
    server.resources['/Sintel.2010.4k.mkv.zip'] = Resource(bytesOf(5000));
    final jobId = await add('/Sintel.2010.4k.mkv.zip');
    final done = await untilState(engine, jobId, JobState.succeeded);
    final row = (done.receipt!.details['files'] as List).single as Map;
    expect(row['imported'], false);
    expect(row['reason'], 'not_video');
    expect(library.scans, isEmpty);
    expect(downloadsDirectory.listSync().map((e) => e.path.split('/').last),
        ['Sintel.2010.4k.mkv.zip']);
  });

  test('the server names the file; a taken name is never overwritten',
      () async {
    server.resources['/get'] = Resource(bytesOf(10))
      ..disposition = 'attachment; filename="ignored.bin"; filename*=UTF-8\'\'%E5%8F%B2.mkv';
    server.resources['/a%20b.bin'] = Resource(bytesOf(20));
    final existing = File('${downloadsDirectory.path}/a b.bin');
    await existing.writeAsString('mine');
    final first = await add('/get?id=1');
    final second = await add('/a%20b.bin');
    await untilState(engine, first, JobState.succeeded);
    await untilState(engine, second, JobState.succeeded);
    expect(File('${downloadsDirectory.path}/史.mkv').existsSync(), true);
    expect(await existing.readAsString(), 'mine');
    expect((await File('${downloadsDirectory.path}/a b (1).bin').readAsBytes()),
        bytesOf(20));
    // Path traversal in the server's name is cut down to one component.
    server.resources['/x'] = Resource(bytesOf(3))
      ..disposition = 'attachment; filename="../../evil.bin"';
    await untilState(engine, await add('/x'), JobState.succeeded);
    expect(File('${downloadsDirectory.path}/evil.bin').existsSync(), true);
    expect(File('${root.path}/evil.bin').existsSync(), false);
  });

  test('a dropped connection resumes with Range from where it stopped',
      () async {
    final data = bytesOf(200000);
    server.resources['/big.mkv'] = Resource(data)
      ..dropAfter = 60000
      ..etag = '"v1"';
    final jobId = await add('/big.mkv');
    final done = await untilState(engine, jobId, JobState.succeeded);
    expect(await File('${downloadsDirectory.path}/big.mkv').readAsBytes(), data);
    final gets = server.requests.where((r) => r.method == 'GET').toList();
    expect(gets.length, greaterThanOrEqualTo(2));
    expect(gets.first.range, isNull);
    expect(gets[1].range, matches(RegExp(r'^bytes=\d+-$')));
    expect(gets[1].range, isNot('bytes=0-'));
    final task = (await call('download.read', {'jobId': jobId}))['task'] as Map;
    final facts = (task['health'] as Map)['http'] as Map;
    expect(facts['resume'], 'confirmed');
    expect(facts['retries'], greaterThanOrEqualTo(1));
    expect(done.receipt!.details['downloadComplete'], true);
  });

  test('a server without Range starts over and still finishes', () async {
    final data = bytesOf(120000);
    server.resources['/plain.mkv'] = Resource(data)
      ..ranges = false
      ..dropAfter = 50000;
    final jobId = await add('/plain.mkv');
    await untilState(engine, jobId, JobState.succeeded);
    expect(
        await File('${downloadsDirectory.path}/plain.mkv').readAsBytes(), data);
    final task = (await call('download.read', {'jobId': jobId}))['task'] as Map;
    final facts = (task['health'] as Map)['http'] as Map;
    expect(facts['acceptRanges'], isNull);
    expect(facts['resume'], 'ignored');
    final gets = server.requests.where((r) => r.method == 'GET').toList();
    expect(gets.length, greaterThanOrEqualTo(2));
    expect(gets[1].range, startsWith('bytes='));
  });

  test('a matching checksum is recorded as matched', () async {
    final data = bytesOf(30000);
    server.resources['/c.mkv'] = Resource(data);
    final jobId = await add('/c.mkv', extra: {
      'checksum': {
        'algorithm': 'md5',
        'value': md5.convert(data).toString().toUpperCase()
      }
    });
    final done = await untilState(engine, jobId, JobState.succeeded);
    expect(done.receipt!.details['checksum'], {
      'algorithm': 'md5',
      'requested': true,
      'expected': md5.convert(data).toString(),
      'actual': md5.convert(data).toString(),
      'matched': true,
    });
  });

  test('a checksum mismatch fails the task with both values and keeps the data',
      () async {
    final data = bytesOf(30000);
    server.resources['/bad.mkv'] = Resource(data);
    final wrong = sha256.convert(utf8.encode('other')).toString();
    final jobId = await add('/bad.mkv',
        extra: {'checksum': {'algorithm': 'sha256', 'value': wrong}});
    final failed = await untilState(engine, jobId, JobState.failed);
    final checksum = failed.receipt!.details['checksum'] as Map;
    expect(checksum['expected'], wrong);
    expect(checksum['actual'], sha256.convert(data).toString());
    expect(checksum['matched'], false);
    expect(failed.error!.message, contains(wrong));
    expect(failed.error!.message, contains(sha256.convert(data).toString()));
    expect(File('${downloadsDirectory.path}/bad.mkv').existsSync(), false);
    expect(File('${downloadsDirectory.path}/bad.mkv.nipaplay-part').existsSync(),
        true);
    expect(library.scans, isEmpty);
  });

  test('bad checksum input and non-http sources are refused', () async {
    for (final source in [
      'file:///etc/passwd',
      'ftp://example.com/a.mkv',
      'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
      '/tmp/a.torrent'
    ]) {
      final outcome = await harness.invokeJson(
          'download.add',
          {'source': source, 'backend': {'kind': 'http'}},
          Invocation(origin: 'mcp'));
      expect(outcome, isA<Failed>(), reason: source);
      expect((outcome as Failed).failure.code, FailureCode.invalidInput);
    }
    final bad = await harness.invokeJson(
        'download.add',
        {
          'source': server.url('/a'),
          'backend': {'kind': 'http'},
          'checksum': {'algorithm': 'md5', 'value': 'abc'}
        },
        Invocation(origin: 'mcp'));
    expect(bad, isA<Failed>());
    final withBuiltin = await harness.invokeJson(
        'download.add',
        {
          'source': server.url('/a'),
          'backend': {'kind': 'builtin'},
          'checksum': {'algorithm': 'md5', 'value': 'a' * 32}
        },
        Invocation(origin: 'mcp'));
    expect(withBuiltin, isA<Failed>());
    expect(await engine.list(type: 'download'), isEmpty);
    expect(server.requests, isEmpty);
    expect(
        () => HttpDownloadBackend.prepare('file:///tmp/x'), throwsA(isA<Failure>()));
  });

  test('the identity is its own, ignores the fragment and is stable', () {
    final a = HttpDownloadBackend.prepare('http://Example.com:80/a/b.mkv#x');
    final b = HttpDownloadBackend.prepare('http://example.com/a/b.mkv');
    final c = HttpDownloadBackend.prepare('https://example.com/a/b.mkv');
    expect(a.infoHash, b.infoHash);
    expect(a.infoHash, isNot(c.infoHash));
    expect(a.infoHash, matches(RegExp(r'^http-[0-9a-f]{40}$')));
    expect(a.title, 'b.mkv');
  });

  test('pause stops the transfer; resume continues with Range', () async {
    final data = bytesOf(160000);
    final resource = Resource(data)..holdAt = 40000;
    server.resources['/p.mkv'] = resource;
    final jobId = await add('/p.mkv');
    await bytesAtLeast(jobId, 20000);
    await call('download.set_paused', {'jobId': jobId, 'paused': true});
    expect((await engine.get(jobId)).state, JobState.paused);
    final paused = await snapshot(jobId);
    expect(paused.paused, true);
    expect(paused.state, 'paused');
    resource.release!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect((await snapshot(jobId)).completed, paused.completed,
        reason: 'no bytes arrive while paused');
    await call('download.set_paused', {'jobId': jobId, 'paused': false});
    final done = await untilState(engine, jobId, JobState.succeeded);
    expect(await File('${downloadsDirectory.path}/p.mkv').readAsBytes(), data);
    final gets = server.requests.where((r) => r.method == 'GET').toList();
    expect(gets.last.range, 'bytes=${paused.completed}-');
    expect(done.receipt!.details['downloadComplete'], true);
  });

  test('cancel keeps the partial file; remove forgets the session', () async {
    server.resources['/c.mkv'] = Resource(bytesOf(160000))..holdAt = 30000;
    final jobId = await add('/c.mkv');
    await bytesAtLeast(jobId, 15000);
    await engine.cancel(jobId);
    final cancelled = await untilState(engine, jobId, JobState.cancelled);
    expect(cancelled.receipt!.details['reason'], 'cancelled_incomplete');
    expect(
        File('${downloadsDirectory.path}/c.mkv.nipaplay-part').existsSync(), true);
    expect(File('${downloadsDirectory.path}/c.mkv').existsSync(), false);
    expect(library.scans, isEmpty);
    await call('download.remove', {'jobId': jobId});
    expect(await http.list(), isEmpty);
    expect(
        File('${downloadsDirectory.path}/c.mkv.nipaplay-part').existsSync(), true);
  });

  test('delete removes the session, the file and its partial data', () async {
    server.resources['/d.mkv'] = Resource(bytesOf(20000));
    final jobId = await add('/d.mkv');
    await untilState(engine, jobId, JobState.succeeded);
    await downloads.remove(jobId, deleteData: true);
    expect(await http.list(), isEmpty);
    expect(downloadsDirectory.listSync(), isEmpty);
    // While running: the partial file goes too.
    server.resources['/e.mkv'] = Resource(bytesOf(160000))..holdAt = 30000;
    final running = await add('/e.mkv');
    await bytesAtLeast(running, 15000);
    await downloads.remove(running, deleteData: true);
    expect(downloadsDirectory.listSync(), isEmpty);
    expect((await engine.get(running)).state, JobState.cancelled);
  });

  test('a 404 fails the task; the server being down is retried', () async {
    final missing = await add('/nothing.mkv');
    final failed = await untilState(engine, missing, JobState.failed);
    expect(failed.error!.code, FailureCode.notFound);
    expect(failed.error!.retryable, false);
    server.resources['/busy.mkv'] = Resource(bytesOf(10))..status = 503;
    final busy = await add('/busy.mkv');
    await untilState(engine, busy, JobState.waitingRetry);
    await engine.cancel(busy);
  });

  test('five minutes without a byte is a stall, retries do not count as progress',
      () async {
    // The rule itself, with an injected clock.
    final resource = Resource(bytesOf(150000))..holdAt = 20000;
    server.resources['/s.mkv'] = resource;
    final jobId = await add('/s.mkv');
    await bytesAtLeast(jobId, 10000);
    var health = (await snapshot(jobId)).health!;
    expect(health['secondsWithoutProgress'], lessThan(60));
    skew = const Duration(minutes: 6);
    health = (await snapshot(jobId)).health!;
    expect(health['secondsWithoutProgress'], greaterThanOrEqualTo(300));
    expect(health['lastProgressAt'], isNotNull);
    await engine.cancel(jobId);
    await untilState(engine, jobId, JobState.cancelled);
  });

  test('the executor records a stall when the server stops and stays down',
      () async {
    await engine.close();
    await connect(stallAfter: const Duration(seconds: 1));
    final resource = Resource(bytesOf(150000))..dropAfter = 30000;
    server.resources['/t.mkv'] = resource;
    final jobId = await add('/t.mkv');
    await bytesAtLeast(jobId, 20000);
    // From now on every attempt is answered with an error: retries, no bytes.
    resource.status = 503;
    await eventually(() async {
      final job = await engine.get(jobId);
      return (job.checkpoint['stalls'] as List? ?? []).isNotEmpty;
    }, reason: 'no stall was recorded');
    final stall = ((await engine.get(jobId)).checkpoint['stalls'] as List).first
        as Map;
    expect(stall['completedBytes'], greaterThanOrEqualTo(20000));
    expect(stall['connectedPeers'], isNull);
    final health = (await snapshot(jobId)).health!;
    expect(((health['http']) as Map)['lastError'], contains('503'));
    // The server comes back: the stretch closes and the file completes.
    resource.status = null;
    await untilState(engine, jobId, JobState.succeeded);
    expect((await engine.get(jobId)).checkpoint['stalls'], hasLength(1));
  });

  test('a restart resumes the session from the partial file', () async {
    final data = bytesOf(180000);
    final resource = Resource(data)..holdAt = 50000;
    server.resources['/r.mkv'] = resource;
    final jobId = await add('/r.mkv');
    await bytesAtLeast(jobId, 30000);
    final stopped = (await snapshot(jobId)).completed;
    // The process ends: engine and backend go away, the server hangs on.
    await engine.close();
    await executor.quiesce(jobId);
    await http.close();
    resource.holdAt = null;
    resource.release?.complete();
    http = newBackend();
    await connect();
    final done = await untilState(engine, jobId, JobState.succeeded);
    expect(await File('${downloadsDirectory.path}/r.mkv').readAsBytes(), data);
    final gets = server.requests.where((r) => r.method == 'GET').toList();
    expect(gets.last.range, matches(RegExp(r'^bytes=\d+-$')));
    expect(int.parse(gets.last.range!.substring(6, gets.last.range!.length - 1)),
        greaterThanOrEqualTo(stopped - 8192));
    expect(done.receipt!.details['downloadComplete'], true);
  });

  test('preview gives the server facts without creating a task or a file',
      () async {
    final data = bytesOf(4096);
    server.resources['/final/Sintel.mkv'] = Resource(data)
      ..etag = '"abc"'
      ..disposition = 'attachment; filename=Sintel%204K.mkv';
    server.resources['/go'] = Resource(Uint8List(0))
      ..redirectTo = '/final/Sintel.mkv';
    final facts = await call('download.preview',
        {'source': server.url('/go'), 'backend': {'kind': 'http'}});
    expect(facts['statusCode'], 200);
    expect(facts['method'], 'HEAD');
    expect(facts['url'], server.url('/go'));
    expect(facts['finalUrl'], server.url('/final/Sintel.mkv'));
    expect(facts['redirects'], 1);
    expect(facts['contentLength'], data.length);
    expect(facts['contentType'], 'application/octet-stream');
    expect(facts['acceptRanges'], true);
    expect(facts['fileName'], 'Sintel%204K.mkv');
    expect(facts['etag'], '"abc"');
    expect(server.requests.every((r) => r.method == 'HEAD'), true);
    expect(await engine.list(type: 'download'), isEmpty);
    expect(downloadsDirectory.listSync(), isEmpty);
  });

  test('preview falls back to a one-byte Range GET when HEAD is refused',
      () async {
    server.resources['/nohead.bin'] = Resource(bytesOf(5000))..denyHead = true;
    server.resources['/norange.bin'] = Resource(bytesOf(7000))
      ..denyHead = true
      ..ranges = false;
    final facts = await call('download.preview',
        {'source': server.url('/nohead.bin'), 'backend': {'kind': 'http'}});
    expect(facts['method'], 'GET Range 0-0');
    expect(facts['statusCode'], 206);
    expect(facts['contentLength'], 5000);
    expect(facts['acceptRanges'], true);
    expect(facts['fileName'], 'nohead.bin');
    expect(server.requests.map((r) => r.range), [null, 'bytes=0-0']);
    final unranged = await call('download.preview',
        {'source': server.url('/norange.bin'), 'backend': {'kind': 'http'}});
    expect(unranged['statusCode'], 200);
    expect(unranged['acceptRanges'], false);
    expect(unranged['contentLength'], 7000);
    final missing = await call('download.preview',
        {'source': server.url('/missing'), 'backend': {'kind': 'http'}});
    expect(missing['statusCode'], 404);
    final refused = await harness.invokeJson(
        'download.preview',
        {'source': 'file:///etc/hosts', 'backend': {'kind': 'http'}},
        Invocation(origin: 'mcp'));
    expect(refused, isA<Failed>());
  });

  test('createFolderForTask and downloadDirectory place the file', () async {
    server.resources['/folder.mkv'] = Resource(bytesOf(100));
    final elsewhere = await Directory('${root.path}/elsewhere').create();
    final jobId = await add('/folder.mkv', extra: {
      'downloadDirectory': elsewhere.path,
      'createFolderForTask': true
    });
    await untilState(engine, jobId, JobState.succeeded);
    expect(File('${elsewhere.path}/folder/folder.mkv').existsSync(), true);
    await downloads.remove(jobId, deleteData: true);
    expect(Directory('${elsewhere.path}/folder').existsSync(), false);
  });
}
