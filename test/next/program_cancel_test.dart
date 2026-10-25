import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/headless/ports.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/programs/runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import 'download_test_support.dart';
import 'media_test_support.dart';

/// Programs Nipa runs end with Next's interface: the whole process tree
/// gets TERM, what ignores it is killed after the grace, and the task says
/// why it ended.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('program-cancel-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<bool> running(int pid) async {
    if (Platform.isWindows) {
      final listed = await Process.run(
          'tasklist.exe', ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV']);
      return listed.stdout.toString().contains('"$pid"');
    }
    return (await Process.run('/bin/ps', ['-o', 'stat=', '-p', '$pid']))
        .stdout
        .toString()
        .trim()
        .replaceFirst(RegExp(r'^Z.*'), '')
        .isNotEmpty;
  }

  Future<void> until(Future<bool> Function() done) async {
    final watch = Stopwatch()..start();
    while (!await done()) {
      if (watch.elapsed > const Duration(seconds: 10)) {
        fail('timed out waiting');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<Job> start(TaskEngine engine, ProgramRuntime programs, String name,
      String command,
      {String? shell}) async {
    final submitted = await programs.submit({
      'title': name,
      'command': command,
      'followup': false,
      if (shell != null) 'shell': shell
    }, Invocation(origin: 'mcp'));
    final id = submitted['jobId'] as String;
    await until(() async => File('${root.path}/$name.started').exists());
    await until(() async => (await engine.get(id)).details['pid'] != null);
    return engine.get(id);
  }

  group('cancelRunning', () {
    late TaskEngine engine;
    late ProgramRuntime programs;
    setUp(() async {
      programs = ProgramRuntime(
          enabled: true, location: HeadlessRepository(root.path));
      engine = TaskEngine(
          store: MemoryJobStore(),
          ownerDeviceId: 'test',
          executors: [programs]);
      programs.engine = engine;
      await engine.start();
    });
    tearDown(() async {
      await programs.close();
      await engine.close();
    });

    test('a program that takes TERM ends on it, its children with it',
        () async {
      final job = await start(engine, programs, 'polite',
          "trap 'echo term > polite.term; exit 0' TERM; "
              "sleep 60 & echo \$! > polite.child; touch polite.started; "
              'while :; do sleep 0.1; done');
      final pid = job.details['pid'] as int;
      final child =
          int.parse((await File('${root.path}/polite.child').readAsString()).trim());
      await programs.cancelRunning(reason: 'next_interface_closed');
      final ended = await engine.get(job.jobId);
      expect(ended.state, JobState.cancelled);
      expect(ended.receipt!.details['cancelReason'], 'next_interface_closed');
      final termination = ended.receipt!.details['termination'] as Map;
      expect(termination['signaled'], containsAll([pid, child]));
      expect(termination['killed'], isEmpty);
      expect(await File('${root.path}/polite.term').exists(), true);
      expect(await running(pid), false);
      expect(await running(child), false);
    }, skip: Platform.isWindows ? 'TERM and its trap are POSIX; see the Windows test below' : null);

    test('on Windows the process tree ends with taskkill, children with it',
        () async {
      final job = await start(
          engine,
          programs,
          'tree',
          r"$c = Start-Process ping -ArgumentList '-n','60','127.0.0.1' -PassThru -WindowStyle Hidden; "
              r"$c.Id | Out-File -Encoding ascii tree.child; "
              r"New-Item tree.started | Out-Null; Start-Sleep 60",
          shell: 'powershell');
      final pid = job.details['pid'] as int;
      final child =
          int.parse((await File('${root.path}/tree.child').readAsString()).trim());
      expect(await running(child), true);
      await programs.cancelRunning(reason: 'next_interface_closed');
      final ended = await engine.get(job.jobId);
      expect(ended.state, JobState.cancelled);
      expect(ended.receipt!.details['cancelReason'], 'next_interface_closed');
      expect((ended.receipt!.details['termination'] as Map)['signal'],
          'taskkill');
      expect(await running(pid), false);
      expect(await running(child), false);
    }, skip: Platform.isWindows ? null : 'taskkill is Windows');

    test('a program that ignores TERM is killed after the grace', () async {
      final job = await start(engine, programs, 'stubborn',
          "trap '' TERM; touch stubborn.started; while :; do sleep 0.1; done");
      final pid = job.details['pid'] as int;
      final watch = Stopwatch()..start();
      await programs.cancelRunning(reason: 'next_interface_closed');
      expect(watch.elapsed, greaterThanOrEqualTo(programStopGrace));
      final ended = await engine.get(job.jobId);
      expect(ended.state, JobState.cancelled);
      expect(ended.receipt!.details['cancelReason'], 'next_interface_closed');
      expect((ended.receipt!.details['termination'] as Map)['killed'],
          contains(pid));
      expect(await running(pid), false);
    }, skip: Platform.isWindows ? 'Windows has no TERM to ignore' : null);

    test('a finished program is left as it ended', () async {
      final submitted = await programs.submit(
          {'title': 'done', 'command': 'exit 0', 'followup': false},
          Invocation(origin: 'mcp'));
      final id = submitted['jobId'] as String;
      await untilState(engine, id, JobState.succeeded);
      await programs.cancelRunning(reason: 'next_interface_closed');
      final job = await engine.get(id);
      expect(job.state, JobState.succeeded);
      expect(job.receipt!.details.containsKey('cancelReason'), false);
      expect(job.receipt!.details.containsKey('termination'), false);
    });
  });

  test('closing Next\'s interface cancels the programs Nipa runs', () async {
    // The harness Nipa's programs run in: here, not the person's.
    final harness = await Directory('${root.path}/harness').create();
    SharedPreferences.setMockInitialValues({'next_harness_path': harness.path});
    sqfliteFfiInit();
    await File('${root.path}/program.json').writeAsString('{"enabled":true}');
    final media = await Directory('${root.path}/media').create();
    final core = NextCore(
      root: root,
      databaseFactory: databaseFactoryFfi,
      downloadBackend: FakeDownloadBackend(root),
      downloadLibrary: FakeDownloadLibrary(),
      isDownloaderEnabled: () async => true,
      loadImportedKeys: () async => {},
      classic: MemoryClassic(),
      authorizedRoots: () => [media.path],
      mediaDurationProbe: (_) async => 1440000,
      mediaSubtitleProbe: (_) async => {'subtitles': <Object?>[]},
      mediaProviders: const [],
    );
    try {
      await core.ready;
      await core.startNipa();
      await core.harnessLocation.ready;
      expect(core.harnessLocation.path, harness.path);
      final submitted = await core.programs.submit({
        'title': 'long',
        'command': Platform.isWindows
            ? 'echo.>"${root.path.replaceAll('/', r'\')}\\long.started" & ping -n 120 127.0.0.1 >nul'
            : 'touch "${root.path}/long.started"; sleep 120',
        'followup': false
      }, Invocation(origin: 'mcp'));
      final id = submitted['jobId'] as String;
      await until(() async => File('${root.path}/long.started').exists());
      await until(() async => (await core.engine.get(id)).details['pid'] != null);
      final pid = (await core.engine.get(id)).details['pid'] as int;

      await core.stopNipa();

      final job = await core.engine.get(id);
      expect(job.state, JobState.cancelled);
      expect(job.receipt!.details['cancelReason'], 'next_interface_closed');
      expect(await running(pid), false);
    } finally {
      await core.close();
    }
  });
}
