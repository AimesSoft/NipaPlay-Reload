import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/download_capability.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/downloads/download_executor.dart';
import 'package:nipaplay/next/downloads/download_service.dart';
import 'package:nipaplay/next/downloads/download_source.dart';
import 'package:nipaplay/next/downloads/file_bindings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';

Map<String, Object?> ref(String type, String id, String scope) => {
      'provider': 'dandanplay',
      'objectType': type,
      'externalId': id,
      'scope': scope
    };

Map<String, Object?> declare(int index, String episode) => {
      'fileIndex': index,
      'workRef': ref('anime', '7', ''),
      'episodeRefs': [ref('episode', episode, 'anime/7')],
    };

void main() {
  late Directory root;
  late FakeDownloadBackend backend;
  late FakeDownloadLibrary library;
  late DownloadExecutor executor;
  late TaskEngine engine;
  late DownloadService downloads;
  late Harness harness;

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-bindings-');
    backend = FakeDownloadBackend(root);
    library = FakeDownloadLibrary()..identify = false;
    final backends = DownloadBackends([backend]);
    executor = DownloadExecutor(
        backends: backends,
        library: library,
        isEnabled: () async => true,
        pollInterval: const Duration(milliseconds: 10));
    engine = TaskEngine(
        store: MemoryJobStore(),
        ownerDeviceId: 'device-test',
        executors: [executor]);
    executor.engine = engine;
    downloads = DownloadService(
        engine: engine,
        executor: executor,
        backends: backends,
        library: library);
    harness = Harness([
      DownloadCapability(
          downloads: downloads,
          sources: DownloadSources(Directory('${root.path}/metadata')))
    ]);
    await engine.start();
  });
  tearDown(() async {
    final jobs = await engine.list();
    await engine.close();
    for (final job in jobs) {
      await executor.quiesce(job.jobId);
    }
    await root.delete(recursive: true);
  });

  /// Two finished, registered videos.
  Future<List<String>> twoFiles() async {
    final paths = <String>[];
    for (final name in ['a.mkv', 'b.mkv']) {
      final file = File('${root.path}/$name')..writeAsBytesSync([1, 2, 3, 4]);
      paths.add(file.path);
    }
    backend.present = true;
    backend.finished = true;
    backend.completed = backend.total;
    backend.overrideFiles = [
      for (final path in paths)
        DownloadFile(
            location: DownloadLocation(path: path, isLocal: true),
            expectedSize: 4,
            completedBytes: 4,
            isVideo: true)
    ];
    for (final entry in paths.indexed) {
      library.media[entry.$2] = {
        'path': entry.$2,
        'fileId': 'file-${entry.$1}',
        'workIds': [],
        'episodes': [],
        'identificationPending': true
      };
    }
    return paths;
  }

  Future<Job> order(List<JsonMap> bindings) async {
    final outcome = await harness.invokeJson(
        'download.add',
        {'source': testRequest.source, 'fileBindings': bindings},
        Invocation(origin: 'mcp', id: 'order-1'));
    expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
    return engine.get(
        (((outcome as Completed).value.toJson())['job'] as Map)['jobId']
            as String);
  }

  Future<Failure> rejected(JsonMap input) async {
    final outcome = await harness.invokeJson(
        'download.add', input, Invocation(origin: 'mcp'));
    expect(outcome, isA<Failed>(), reason: '${outcome.toEnvelope()}');
    expect(await engine.list(type: 'download'), isEmpty);
    return (outcome as Failed).failure;
  }

  List<Map> completedRows(Job job) =>
      (job.checkpoint['completedFiles'] as List).cast<Map>();

  test('a declared file is bound once it is registered, with a stable request',
      () async {
    final paths = await twoFiles();
    final job = await order([declare(0, '101'), declare(1, '102')]);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    expect(library.bindCalls.map((c) => c['requestId']), [
      'download:${job.jobId}:file:0',
      'download:${job.jobId}:file:1',
    ]);
    expect(library.bindCalls.map((c) => c['fileId']), ['file-0', 'file-1']);
    expect(library.bindCalls.first['origin'], 'mcp');
    final rows = completedRows(done);
    expect(rows, hasLength(2));
    expect(rows[0]['binding'], {
      'status': 'bound',
      'workId': 'work-1',
      'releaseId': 'release-1',
      'episodeIds': ['episode-1']
    });
    expect((rows[1]['binding'] as Map)['episodeIds'], ['episode-2']);
    expect(rows[0]['path'], paths[0]);
    expect(library.bindCalls, hasLength(2));
  });

  test('a binding that fails is a fact on the file, not a failed download',
      () async {
    await twoFiles();
    library.bindFailure =
        const Failure(FailureCode.conflict, 'episode refs do not match');
    final job = await order([declare(0, '101')]);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    final rows = completedRows(done);
    expect(rows, hasLength(2));
    final binding = rows[0]['binding'] as Map;
    expect(binding['status'], 'failed');
    expect((binding['error'] as Map)['message'], contains('do not match'));
    expect(rows[1].containsKey('binding'), false);
    // One attempt only: nothing retries it.
    expect(library.bindCalls, hasLength(1));
    expect(done.state, JobState.succeeded);
  });

  test('an unexpected error is recorded as internal and does not stop the rest',
      () async {
    await twoFiles();
    library.bindFailure = StateError('provider exploded');
    final job = await order([declare(0, '101'), declare(1, '102')]);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    final rows = completedRows(done);
    expect(rows.map((r) => (r['binding'] as Map)['status']),
        ['failed', 'failed']);
    expect(((rows[0]['binding'] as Map)['error'] as Map)['code'], 'internal');
    expect(library.bindCalls, hasLength(2));
  });

  test('a file Classic already identified is left alone and reported',
      () async {
    final paths = await twoFiles();
    library.media[paths[0]] = {
      'path': paths[0],
      'fileId': 'file-0',
      'workIds': ['work-classic'],
      'episodes': [
        {'episodeId': 'episode-classic', 'workId': 'work-classic'}
      ],
      'identificationPending': false
    };
    final job = await order([declare(0, '101'), declare(1, '102')]);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    final rows = completedRows(done);
    expect(rows[0]['binding'],
        {'status': 'already_identified', 'existingEpisodeIds': ['episode-classic']});
    expect((rows[1]['binding'] as Map)['status'], 'bound');
    expect(library.bindCalls.map((c) => c['fileId']), ['file-1']);
  });

  test('the file event waits while its binding is pending', () async {
    await twoFiles();
    final gate = Completer<void>();
    library.bindGate = gate.future;
    final job = await order([declare(0, '101')]);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (library.bindCalls.isEmpty) {
      expect(DateTime.now().isBefore(deadline), true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final waiting = await engine.get(job.jobId);
    expect(completedRows(waiting).first['binding'], {'status': 'pending'});
    gate.complete();
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    expect((completedRows(done).first['binding'] as Map)['status'], 'bound');
  });

  test('a binding left pending by a crash is finished again under its request',
      () async {
    final paths = await twoFiles();
    final request = DownloadRequest(
        source: testRequest.source,
        infoHash: testRequest.infoHash,
        title: testRequest.title,
        fileBindings: parseFileBindings([declare(0, '101')]));
    final job = await engine.submit(
        type: 'download',
        title: 'Episode',
        input: {
          ...request.toJson(),
          'completedFiles': [
            {
              'objectId': 'x:0',
              'index': 0,
              'path': paths[0],
              'isVideo': true,
              'local': true,
              'complete': true,
              'verification': 'verified',
              'imported': true,
              'binding': {'status': 'pending'}
            }
          ]
        },
        details: {'backend': const DownloadBackendRef.builtin().toJson()},
        phase: 'downloading');
    final done = await untilState(engine, job.jobId, JobState.succeeded)
        .onError((e, s) async {
      fail('${(await engine.get(job.jobId)).toJson()}');
    });
    final rows = completedRows(done);
    expect(rows, hasLength(2));
    expect((rows[0]['binding'] as Map)['status'], 'bound');
    expect(library.bindCalls.map((c) => c['requestId']),
        ['download:${job.jobId}:file:0']);
  });

  test('declared files that never ran appear in the receipt', () async {
    await twoFiles();
    final job = await order([declare(0, '101'), declare(5, '105')]);
    final done = await untilState(engine, job.jobId, JobState.succeeded);
    expect(done.receipt!.details['unboundDeclarations'], [
      {'fileIndex': 5, 'reason': 'no_such_file'}
    ]);
  });

  group('add rejects what cannot be honoured', () {
    test('duplicate indices, indices outside fileIndices, bad refs, batches',
        () async {
      final source = testRequest.source;
      expect(
          (await rejected({
            'source': source,
            'fileBindings': [declare(0, '1'), declare(0, '2')]
          }))
              .message,
          contains('twice'));
      expect(
          (await rejected({
            'source': source,
            'fileIndices': [1],
            'fileBindings': [declare(0, '1')]
          }))
              .message,
          contains('fileIndices'));
      expect(
          (await rejected({
            'source': source,
            'fileBindings': [
              {
                'fileIndex': 0,
                'workRef': ref('anime', '7', ''),
                'episodeRefs': [
                  ref('episode', '1', 'anime/7'),
                  ref('episode', '1', 'anime/7')
                ]
              }
            ]
          }))
              .message,
          contains('distinct'));
      expect(
          (await rejected({
            'source': source,
            'fileBindings': [
              {'fileIndex': 0, 'workRef': ref('anime', '7', ''), 'episodeRefs': []}
            ]
          }))
              .code,
          FailureCode.invalidInput);
      expect(
          (await rejected({
            'source': source,
            'fileBindings': [
              {
                'fileIndex': 0,
                'workRef': {'provider': 'dandanplay'},
                'episodeRefs': [ref('episode', '1', 'anime/7')]
              }
            ]
          }))
              .code,
          FailureCode.invalidInput);
      expect(
          (await rejected({
            'sources': [source],
            'fileBindings': [declare(0, '1')]
          }))
              .message,
          contains('per torrent'));
    });

    test('a torrent file index beyond the manifest is refused at add',
        () async {
      final bytes = BytesBuilder()
        ..add(ascii.encode(
            'd4:infod6:lengthi4e4:name11:episode.mkv12:piece lengthi16384e6:pieces20:'))
        ..add(List.filled(20, 7))
        ..add(ascii.encode('ee'));
      final torrent = await File('${root.path}/one.torrent')
          .writeAsBytes(Uint8List.fromList(bytes.toBytes()));
      final failure = await rejected({
        'source': torrent.path,
        'fileBindings': [declare(0, '1'), declare(1, '2')]
      });
      expect(failure.message, contains('fileIndex 1 does not exist'));
      final ok = await harness.invokeJson(
          'download.add',
          {
            'source': torrent.path,
            'fileBindings': [declare(0, '1')]
          },
          Invocation(origin: 'mcp'));
      expect(ok, isA<Completed>(), reason: '${ok.toEnvelope()}');
    });
  });

  test('parseFileBindings normalizes and keeps optional fields', () {
    final parsed = parseFileBindings([
      {
        ...declare(2, '9'),
        'releaseRef': ref('anime', '7', ''),
        'reason': 'Matched by title and number'
      }
    ], fileCount: 3, fileIndices: [2]);
    expect(parsed.single['releaseRef'], ref('anime', '7', ''));
    expect(parsed.single['reason'], 'Matched by title and number');
  });
}
