import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/probe_process.dart';

void main() {
  late Directory dir;
  late MediaProbeProcess probe;
  Future<void> executable(String body) async {
    final file = File('${dir.path}/nipa_media_probe');
    await file.writeAsString('#!/bin/sh\n$body\n');
    await Process.run('chmod', ['+x', file.path]);
    probe.executable = file.path;
    probe.library = file.path;
  }
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('probe-test-');
    probe = MediaProbeProcess(timeout: const Duration(seconds: 1));
  });
  tearDown(() async { await probe.close(); await dir.delete(recursive: true); });
  test('timeout kills child; next file can be probed and technical facts survive', () async {
    await executable('exec sleep 60');
    await expectLater(probe.run('stuck.mkv'), throwsA(isA<Failure>()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(probe.status()['active'], isEmpty);
    expect((probe.status()['recent'] as List).single['reason'], 'timeout');
    await executable('echo \'{"container":{"ok":true,"value":{"mediaOpen":true,"format":"matroska"}},"tracks":{"ok":true,"value":[{"id":2,"kind":2,"codec":"subrip","language":"chi"}]},"events":[{"ok":true,"value":{"durationMicros":1250000}}]}\'');
    final facts = await probe.run('healthy.mkv');
    expect(facts['durationMs'], 1250);
    expect((facts['subtitles'] as List).single['streamIndex'], 2);
  }, skip: Platform.isWindows);
  test('operator cancels only owned ID; failure keeps original stderr', () async {
    probe = MediaProbeProcess(timeout: const Duration(seconds: 5));
    await executable('exec sleep 60');
    final running = expectLater(probe.run('slow.mkv'), throwsA(isA<Failure>()));
    while ((probe.status()['active'] as List).isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final id = (probe.status()['active'] as List).single['probeId'] as String;
    expect((await probe.cancel(id))['terminated'], true);
    await running;
    await expectLater(probe.cancel('unowned'), throwsA(isA<Failure>()));
    await executable('echo "Invalid data found when processing input" >&2\nexit 1');
    await expectLater(probe.run('bad.mkv'), throwsA(isA<Failure>().having(
      (e) => e.message, 'original error', contains('Invalid data found'))));
  }, skip: Platform.isWindows);
  test('task stop signal terminates probe without indexing late results', () async {
    probe = MediaProbeProcess(timeout: const Duration(seconds: 5));
    await executable('exec sleep 60');
    final stop = Completer<void>();
    final running = expectLater(probe.run('cancel.mkv', stopRequested: stop.future), throwsA(isA<Failure>()));
    while ((probe.status()['active'] as List).isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    stop.complete();
    await running;
    expect((probe.status()['recent'] as List).single['reason'], 'cancelled');
  }, skip: Platform.isWindows);
}
