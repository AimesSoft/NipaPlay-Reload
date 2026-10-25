import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/download_capability.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/downloads/download_executor.dart';
import 'package:nipaplay/next/downloads/download_service.dart';
import 'package:nipaplay/next/downloads/download_source.dart';
import 'package:nipaplay/next/downloads/qbittorrent_download_backend.dart';
import 'package:nipaplay/next/harness_hooks.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';
import 'fake_qbittorrent.dart';

const hash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const magnetLink = 'magnet:?xt=urn:btih:$hash&dn=Show';
const seedbox = {'kind': 'qbittorrent', 'id': 'seedbox'};

void main() {
  late Directory root;
  late FakeQbittorrent fake;
  late SqliteJobStore store;
  late TaskEngine engine;
  late DownloadExecutor executor;
  late DownloadService downloads;
  late FakeDownloadLibrary library;
  late Harness harness;
  late HarnessHooks hooks;
  late QbittorrentDownloadBackend backend;

  Future<void> connect({bool local = false}) async {
    backend = QbittorrentDownloadBackend(
        id: 'seedbox',
        name: 'Seedbox',
        address: fake.address,
        local: local,
        login: () async => QbittorrentLogin(fake.username, fake.password),
        pollInterval: const Duration(milliseconds: 20),
        connectTimeout: const Duration(seconds: 1));
    final backends = DownloadBackends([backend]);
    executor = DownloadExecutor(
        backends: backends,
        library: library,
        isEnabled: () async => true,
        pollInterval: const Duration(milliseconds: 20),
        importRetryDelay: const Duration(milliseconds: 60));
    hooks = HarnessHooks();
    engine = TaskEngine(
        store: store,
        ownerDeviceId: 'device-test',
        executors: [executor, hooks]);
    executor.engine = engine;
    hooks.engine = engine;
    await Directory('${root.path}/hooks').create();
    for (final event in ['download.file_completed', 'download.completed']) {
      final program = File('${root.path}/hooks/$event');
      await program.writeAsString('#!/bin/sh\ncat > /dev/null\n');
      expect((await Process.run('chmod', ['755', program.path])).exitCode, 0);
    }
    hooks.enable(root, File('${root.path}/endpoint.json'));
    downloads = DownloadService(
        engine: engine,
        executor: executor,
        backends: backends,
        library: library);
    harness = Harness([
      TaskCapability(engine),
      DownloadCapability(
          downloads: downloads,
          sources: DownloadSources(Directory('${root.path}/metadata')))
    ]);
    await engine.start();
  }

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('qbit-flow-');
    store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    library = FakeDownloadLibrary();
    fake = FakeQbittorrent();
    await fake.start();
    fake.magnetContents[hash] = (
      name: 'Show',
      files: [('Show/ep1.mkv', 1000), ('Show/notes.txt', 10)]
    );
  });

  tearDown(() async {
    final jobs = await engine.list();
    await hooks.disable();
    await engine.close();
    for (final job in jobs) {
      await executor.quiesce(job.jobId);
    }
    await backend.close();
    await fake.stop();
    await root.delete(recursive: true);
  });

  Future<JsonMap> call(String action, JsonMap input) async {
    final outcome = await harness.invokeJson(
        action, input, Invocation(origin: 'mcp', id: 'qbit-test'));
    expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
    final result = (outcome as Completed).value.toJson();
    expect(harness.lookup(action)!.spec.output.validate(result), isEmpty);
    return result;
  }

  Future<Failure> fails(String action, JsonMap input) async {
    final outcome = await harness.invokeJson(
        action, input, Invocation(origin: 'mcp', id: 'qbit-test'));
    expect(outcome, isA<Failed>(), reason: '${outcome.toEnvelope()}');
    return (outcome as Failed).failure;
  }

  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) throw StateError('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('a download on another machine finishes there and is reported where it is',
      () async {
    await connect();
    final added = await call('download.add', {
      'source': magnetLink,
      'backend': seedbox,
      'downloadDirectory': '/seed/dl',
      'category': 'anime',
    });
    final jobId = (added['job'] as Map)['jobId'] as String;
    expect((added['job'] as Map)['backend'], seedbox);
    await until(() =>
        fake.torrents[hash]?.hasMetadata == true &&
        fake.requests.contains('GET /api/v2/torrents/files'));
    expect(fake.torrents[hash]!.savePath, '/seed/dl');
    expect(fake.torrents[hash]!.category, 'anime');

    // Pause and resume go to that qBittorrent.
    await call('download.set_paused', {'jobId': jobId, 'paused': true});
    expect(fake.torrents[hash]!.paused, isTrue);
    await call('download.set_paused', {'jobId': jobId, 'paused': false});
    expect(fake.torrents[hash]!.paused, isFalse);

    // Half of the video: the task says so, and says it is not here.
    fake.torrents[hash]!.files[0].progress = 0.5;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final partial = await call('download.read', {'jobId': jobId});
    final task = partial['task'] as Map;
    expect(task['local'], isFalse);
    expect(task['outputDirectory'], '/seed/dl');
    final video = (task['files'] as List).first as Map;
    expect(video['path'], '/seed/dl/Show/ep1.mkv');
    expect(video['local'], isFalse);
    expect(video['completedBytes'], 500);
    expect(video['playable'], isFalse);

    fake.finish(hash);
    final done = await untilState(engine, jobId, JobState.succeeded);
    final files = (done.receipt!.details['files'] as List).cast<Map>();
    expect(files.map((f) => f['path']),
        ['/seed/dl/Show/ep1.mkv', '/seed/dl/Show/notes.txt']);
    expect(files.map((f) => f['local']), [false, false]);
    expect(files[0]['actualSize'], 1000);
    expect(files[0]['reason'], 'requires_transfer');
    expect(files[0]['imported'], isFalse);
    expect(files[1]['reason'], 'not_video');
    expect(done.receipt!.details['outputDirectory'], '/seed/dl');
    expect(library.scans, isEmpty, reason: 'nothing is imported from elsewhere');
    expect(done.details['backend'], seedbox);

    final completed = (done.checkpoint['completedFiles'] as List).cast<Map>();
    expect(completed.map((f) => f['path']), contains('/seed/dl/Show/ep1.mkv'));
    expect(completed.map((f) => f['local']), everyElement(false));

    // The hooks hear of it, with the downloader and the path there.
    await hooks.taskChanged(done);
    await hooks.drain();
    final runs = [
      for (final job in await engine.list(type: 'harness.hook')) job.input
    ];
    final fileEvent =
        runs.singleWhere((r) => r['event'] == 'download.file_completed' &&
            ((r['data'] as Map)['file'] as Map)['index'] == 0);
    final data = fileEvent['data'] as Map;
    expect(data['backend'], seedbox);
    expect(data['infoHash'], hash);
    expect((data['file'] as Map)['local'], false);
    expect((data['file'] as Map)['path'], '/seed/dl/Show/ep1.mkv');
    final finished =
        runs.singleWhere((r) => r['event'] == 'download.completed');
    expect(((finished['data'] as Map)['backend']), seedbox);
    expect(((finished['data'] as Map)['receipt'] as Map)['details']['outputDirectory'],
        '/seed/dl');

    // Nothing transfers by itself, and nothing here pretends to read it.
    final import = await fails('download.import', {'jobId': jobId});
    expect(import.code, FailureCode.conflict);
  });

  test('a qBittorrent that goes off and comes back does not lose the download',
      () async {
    await connect();
    final added = await call(
        'download.add', {'source': magnetLink, 'backend': seedbox});
    final jobId = (added['job'] as Map)['jobId'] as String;
    await until(() => fake.torrents[hash]?.hasMetadata == true);
    final port = fake.server.port;
    await fake.stop();
    await untilState(engine, jobId, JobState.waitingRetry);
    final waiting = await engine.get(jobId);
    expect(waiting.error?.code, FailureCode.unavailable);
    await fake.start(port);
    fake.finish(hash);
    await untilState(engine, jobId, JobState.succeeded);
  });

  test('a qBittorrent on this computer is read from disk and imported like any download',
      () async {
    final dir = await Directory('${root.path}/dl').create();
    await Directory('${dir.path}/Show').create();
    await File('${dir.path}/Show/ep1.mkv').writeAsBytes(List.filled(1000, 1));
    await File('${dir.path}/Show/notes.txt').writeAsBytes(List.filled(10, 1));
    await connect(local: true);
    final added = await call('download.add', {
      'source': magnetLink,
      'backend': seedbox,
      'downloadDirectory': dir.path,
      'createFolderForTask': true,
    });
    final jobId = (added['job'] as Map)['jobId'] as String;
    await until(() => fake.torrents[hash]?.hasMetadata == true);
    expect(fake.torrents[hash]!.contentLayout, 'Subfolder');
    fake.finish(hash);
    final done = await untilState(engine, jobId, JobState.succeeded);
    final files = (done.receipt!.details['files'] as List).cast<Map>();
    expect(files[0]['local'], isTrue);
    expect(files[0]['imported'], isTrue);
    expect(library.scans.single, ['${dir.path}/Show/ep1.mkv']);
  });

  test('which qBittorrent, and what only a qBittorrent can take, are checked',
      () async {
    await connect();
    var failure = await fails('download.add',
        {'source': magnetLink, 'backend': {'kind': 'qbittorrent'}});
    expect(failure.code, FailureCode.invalidInput);
    expect(failure.message, contains('seedbox'));
    failure = await fails('download.add',
        {'source': magnetLink, 'backend': {'kind': 'qbittorrent', 'id': 'nope'}});
    expect(failure.code, FailureCode.unavailable);
    failure = await fails('download.add', {
      'source': magnetLink,
      'backend': {'kind': 'http'},
      'category': 'x'
    });
    expect(failure.code, FailureCode.invalidInput);
    expect(fake.torrents, isEmpty);
  });

  test('speed limits of a chosen qBittorrent', () async {
    await connect();
    final set = await call('download.limits.set',
        {'backend': seedbox, 'downloadBytesPerSecond': 300000});
    expect(fake.downloadLimit, 300000);
    expect(set['backend'], seedbox);
    expect((set['actual'] as Map)['downloadBytesPerSecond'], 300000);
    final read = await call('download.limits.get', {'backend': seedbox});
    expect((read['actual'] as Map)['downloadBytesPerSecond'], 300000);
    final bad = await fails('download.limits.set',
        {'backend': {'kind': 'qbittorrent'}, 'downloadBytesPerSecond': 1});
    expect(bad.code, FailureCode.invalidInput);
  });
}
