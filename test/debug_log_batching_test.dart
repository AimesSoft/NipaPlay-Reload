import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/file_log_service_io.dart';

void main() {
  test('stop queued during startup leaves the writer stopped', () async {
    final directory =
        await Directory.systemTemp.createTemp('nipaplay-log-lifecycle-');
    final logs = DebugLogService.forTesting();
    final files = FileLogService.forTesting(logs, directory);
    logs.addLog('startup');
    await Future.wait([files.start(), files.stop()]);
    expect(files.isRunning, isFalse);
    final file = await directory
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .single;
    expect(await file.readAsString(), contains('startup'));
    await directory.delete(recursive: true);
    logs.dispose();
  });

  test('a failed disk batch is retried', () async {
    final directory =
        await Directory.systemTemp.createTemp('nipaplay-log-retry-');
    final logs = DebugLogService.forTesting();
    final files = FileLogService.forTesting(logs, directory);
    await files.start();
    final moved = await directory.rename('${directory.path}-moved');
    logs.addLog('retry-me');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await moved.rename(directory.path);
    for (var i = 0; i < 10; i++) {
      logs.addLog('later-$i');
    }
    await files.stop();
    final file = await directory
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .single;
    expect(await file.readAsString(), contains('retry-me'));
    await directory.delete(recursive: true);
    logs.dispose();
  });

  test('overflow is bounded and shutdown preserves the newest queued entries',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('nipaplay-log-overflow-');
    final logs = DebugLogService.forTesting();
    final files = FileLogService.forTesting(logs, directory);
    await files.start();
    for (var i = 0; i < 6000; i++) {
      logs.addLog('queued-$i');
    }
    await Future.wait([files.stop(), files.stop()]);
    final file = await directory
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .single;
    final content = await file.readAsString();
    expect(content, contains('丢弃 1000 条旧日志'));
    expect(content, contains('queued-5999'));
    expect(content, isNot(contains('queued-999\n')));
    expect(content.split('\n').where((line) => line.contains('queued-')),
        hasLength(5000));
    await directory.delete(recursive: true);
    logs.dispose();
  });

  testWidgets(
      'a burst has one UI notification and every entry reaches the sink',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final service = DebugLogService.forTesting();
    var notifications = 0;
    void listener() => notifications++;
    service.addListener(listener);
    final entries = <LogEntry>[];
    final subscription = service.entries.listen(entries.add);
    for (var i = 0; i < 6000; i++) {
      service.addLog('message $i');
    }
    expect(entries, hasLength(6000));
    expect(service.logCount, 5000);
    expect(service.revision, 6000);
    expect(notifications, 0);
    await tester.pump();
    expect(notifications, 1);
    service.stopCollecting();
    await tester.pump();
    expect(notifications, 2);
    service.clearLogs();
    await tester.pump();
    expect(service.logCount, 0);
    expect(notifications, 3);
    service.removeListener(listener);
    await tester.runAsync(subscription.cancel);
  });

  test('file sink keeps duplicates and flushes new entries when stopped',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('nipaplay-log-batch-');
    final logs = DebugLogService.forTesting();
    final files = FileLogService.forTesting(logs, directory);
    addTearDown(() async {
      await files.stop();
      await directory.delete(recursive: true);
    });
    logs.addLog('initial');
    await Future.wait([files.start(), files.start()]);
    logs.addLog('duplicate');
    logs.addLog('duplicate');
    logs.clearLogs();
    logs.addLog('after clear');
    await files.stop();
    final output =
        await directory.list().where((f) => f is File).cast<File>().single;
    final content = await output.readAsString();
    expect('duplicate'.allMatches(content), hasLength(2));
    expect(content, contains('initial'));
    expect(content, contains('after clear'));
    expect(files.isRunning, isFalse);
  });
}
