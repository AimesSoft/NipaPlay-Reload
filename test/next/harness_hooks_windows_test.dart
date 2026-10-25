import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/harness_hooks.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:path/path.dart' as ppath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/platform.dart';

/// Windows has no shebang and no execute bit: a hook is run by its extension
/// (.py with `python`, .cmd and .bat through cmd.exe, .exe directly), the
/// event arrives on standard input as UTF-8 and the program's output is read
/// back as UTF-8, whatever the console code page is (GBK on a Chinese system).
void main() {
  late Directory root, repository;
  late SqliteJobStore store;
  late HarnessHooks hooks;
  late TaskEngine engine;

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('hook-windows-');
    repository = await Directory(ppath.join(root.path, 'harness')).create();
    await Directory(ppath.join(repository.path, 'hooks')).create();
    store = await SqliteJobStore.open(Directory(ppath.join(root.path, 'state')),
        factory: databaseFactoryFfi);
    hooks = HarnessHooks(timeout: const Duration(seconds: 20));
    engine =
        TaskEngine(store: store, ownerDeviceId: 'test', executors: [hooks]);
    hooks.engine = engine;
    hooks.enable(
        repository, File(ppath.join(root.path, 'private', 'endpoint.json')));
    await engine.start();
  });

  tearDown(() async {
    await hooks.disable();
    await engine.close();
    await store.database.close();
    await deleteTestDirectory(root);
  });

  Future<Job> run(String extension, String text,
      {String path = r'D:\媒体\番剧 第1话.mkv'}) async {
    await File(ppath.join(repository.path, 'hooks', 'playback.started$extension'))
        .writeAsString(text);
    final job = (await hooks.emit('playback.started', path, {'path': path}))!;
    var latest = await engine.get(job.jobId);
    while (!latest.state.isTerminal) {
      latest = await engine.wait(job.jobId,
          afterRevision: latest.revision, timeout: const Duration(seconds: 3));
    }
    return latest;
  }

  test('a .py hook reads the event and speaks UTF-8 whatever the code page',
      () async {
    final job = await run('.py', '''
import json, sys
event = json.load(sys.stdin)
with open("received.txt", "w", encoding="utf-8") as out:
    out.write(event["data"]["path"])
print("收到 " + event["data"]["path"])
''');
    expect(job.state, JobState.succeeded,
        reason: jsonEncode(job.receipt?.toJson()));
    expect(job.receipt!.details['exitCode'], 0);
    expect(
        await File(ppath.join(repository.path, 'received.txt'))
            .readAsString(encoding: utf8),
        r'D:\媒体\番剧 第1话.mkv');
    expect(job.receipt!.details['stdoutTail'], contains(r'收到 D:\媒体\番剧 第1话.mkv'));
  }, skip: Platform.isWindows ? null : 'Windows hooks');

  test('a .cmd hook runs through cmd.exe with the event on standard input',
      () async {
    final job = await run('.cmd', '@echo off\r\n'
        'findstr "^" > received.json\r\n'
        'echo done %NIPAPLAY_HOOK:~0,4%\r\n');
    expect(job.state, JobState.succeeded,
        reason: jsonEncode(job.receipt?.toJson()));
    final received = jsonDecode(await File(
                ppath.join(repository.path, 'received.json'))
            .readAsString(encoding: utf8))
        as Map;
    expect(received['event'], 'playback.started');
    expect((received['data'] as Map)['path'], r'D:\媒体\番剧 第1话.mkv');
    expect(job.receipt!.details['stdoutTail'], contains('done'));
  }, skip: Platform.isWindows ? null : 'Windows hooks');

  test('a hook file without a runnable extension is not run', () async {
    // Windows has no execute bit: only .exe, .cmd, .bat and .py are programs.
    await File(ppath.join(repository.path, 'hooks', 'playback.started'))
        .writeAsString('#!/bin/sh\nexit 0\n');
    expect(await hooks.emit('playback.started', '/a.mkv', {'path': '/a.mkv'}),
        isNull);
    final row = ((await hooks.status())['hooks'] as List)
        .cast<Map>()
        .firstWhere((row) => row['event'] == 'playback.started');
    expect(row['program'], isNull);
  }, skip: Platform.isWindows ? null : 'Windows hooks');
}
