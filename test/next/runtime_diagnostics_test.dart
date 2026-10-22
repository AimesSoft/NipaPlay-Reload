import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/system/player_native_log.dart';
import 'package:nipaplay/next/system/runtime_diagnostics.dart';
import 'package:nipaplay/next/system/uncaught_errors.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';
import 'test_support.dart';

/// Classic's Media Kit kernel as a test double that records the log file
/// mpv is told to write.
class LoggingKernel extends ClassicKernel {
  final logFiles = <String>[];
  @override
  Future<void> setNativeLogFile(String path) async => logFiles.add(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('player native log', () {
    test('keeps kernel lines only while attached, pages and redacts them',
        () async {
      final log = PlayerNativeLog(capacity: 3);
      PlayerNativeLogTap.observer?.call('mdk', 1, 'event', 'x', 'unheard');
      expect(log.read()['lines'], isEmpty);
      log.attach();
      addTearDown(log.detach);
      for (final (level, text) in [
        ('error', 'Failed to open https://h.example/v.mkv?api_key=SECRET'),
        ('warn', 'h264: corrupted macroblock'),
        ('error', 'tcp: Connection refused'),
        ('info', 'Playing: file'),
      ]) {
        PlayerNativeLogTap.observer!('media_kit', 7, level, 'ffmpeg', text);
      }
      final all = log.read(currentInstance: 7);
      expect(all['evicted'], 1);
      expect((all['lines'] as List).map((l) => l['level']),
          ['warn', 'error', 'info']);
      expect((all['lines'] as List).every((l) => l['currentPlayer'] == true),
          isTrue);
      final errors = log.read(levels: ['error'], limit: 5);
      expect((errors['lines'] as List).single['text'], 'tcp: Connection refused');
      final after = log.read(afterSequence: 3);
      expect((after['lines'] as List).single['text'], 'Playing: file');
      log.add('media_kit', 7, 'error', 'file',
          'Failed to open https://h.example/v.mkv?api_key=SECRET');
      expect('${log.read(contains: 'Failed')}', isNot(contains('SECRET')));
      await log.detach();
      expect(PlayerNativeLogTap.observer, isNull);
      expect(log.recording, isFalse);
    });

    test('mpv writes its full log to a file only when asked, and stops',
        () async {
      final directory = await Directory.systemTemp.createTemp('pf-log-');
      addTearDown(() => directory.delete(recursive: true));
      final kernel = LoggingKernel();
      final player = Player.withDelegate(kernel);
      final log = PlayerNativeLog()..attach();
      final file = await log.startFile(player, directory);
      expect(file, isNotNull);
      expect(kernel.logFiles, [file!.path]);
      await file.writeAsString(
          ['[cplayer] Opening', 'https://h.example/v?api_key=SECRET', 'done']
              .join('\n'));
      final page = await PlayerNativeLog.readFile(file, limit: 2);
      expect((page['lines'] as List).length, 2);
      expect(page['nextCursor'], 2);
      expect('$page', isNot(contains('SECRET')));
      await log.detach();
      expect(kernel.logFiles.last, '');
      final without = Player.withDelegate(ClassicKernel());
      expect(await PlayerNativeLog().startFile(without, directory), isNull);
    });

    test('the log file is refused while Next records nothing', () async {
      final directory = await Directory.systemTemp.createTemp('pf-cap-');
      addTearDown(() => directory.delete(recursive: true));
      final harness = Harness([
        RuntimeDiagnosticsCapability(
            errors: UncaughtErrors(directory),
            log: PlayerNativeLog(),
            player: () => Player.withDelegate(LoggingKernel()),
            logDirectory: directory)
      ]);
      await invokeFailed(harness, 'diagnostics.player_log_file',
          {'enabled': true}, FailureCode.unavailable);
      final read = await invokeCompleted(harness, 'diagnostics.player_log', {});
      expect(read['recording'], isFalse);
      expect(read['kernel'], {'id': 'media_kit', 'name': 'Media Kit'});
    });
  });

  group('uncaught errors', () {
    test('wraps the handlers it finds, records and restores them', () async {
      final directory = await Directory.systemTemp.createTemp('pf-errors-');
      addTearDown(() => directory.delete(recursive: true));
      final flutterBefore = FlutterError.onError;
      final dispatcherBefore = PlatformDispatcher.instance.onError;
      final seen = <FlutterErrorDetails>[];
      FlutterError.onError = seen.add;
      addTearDown(() {
        FlutterError.onError = flutterBefore;
        PlatformDispatcher.instance.onError = dispatcherBefore;
      });
      PlatformDispatcher.instance.onError = null;
      final errors = UncaughtErrors(directory, appVersion: '1.0')
        ..context = () => {'status': 'playing', 'path': '/media/a.mkv'};
      await errors.attach();
      final details = FlutterErrorDetails(
          exception: StateError('layout broke'),
          stack: StackTrace.current,
          library: 'rendering library');
      FlutterError.onError!(details);
      expect(seen.single, same(details));
      expect(PlatformDispatcher.instance.onError!(
          ArgumentError('lost future'), StackTrace.current), isFalse);
      await errors.detach();
      expect(FlutterError.onError == seen.add, isTrue);
      expect(PlatformDispatcher.instance.onError, isNull);
      final read = await errors.read();
      final records = (read['records'] as List).cast<Map>();
      expect(records.map((r) => r['channels']), containsAll([
        ['flutter'],
        ['platform_dispatcher']
      ]));
      final flutter = records.firstWhere(
          (r) => (r['channels'] as List).contains('flutter'));
      expect(flutter['message'], contains('layout broke'));
      expect(flutter['library'], 'rendering library');
      expect(flutter['playback'], {'status': 'playing', 'path': '/media/a.mkv'});
      expect(flutter['appVersion'], '1.0');
      expect(read['recording'], isFalse);
    });

    test('the same error counts; a second channel is the same occurrence',
        () async {
      final directory = await Directory.systemTemp.createTemp('pf-count-');
      addTearDown(() => directory.delete(recursive: true));
      final errors = UncaughtErrors(directory);
      final stack = StackTrace.fromString('#0 main (file:///a.dart:1:1)');
      errors.record('platform_dispatcher', 'boom https://h/x?token=SECRET', stack);
      final same = errors.record('isolate', 'boom https://h/x?token=SECRET', stack);
      expect(same['channels'], ['platform_dispatcher', 'isolate']);
      expect(same['count'], 1);
      expect(errors.record('platform_dispatcher', 'boom https://h/x?token=SECRET',
          stack)['count'], 2);
      expect('${await errors.read()}', isNot(contains('SECRET')));
    });

    test('a run that ended outside the exit path is reported once, with what '
        'it played; an exit or Next turned off is not', () async {
      final directory = await Directory.systemTemp.createTemp('pf-exit-');
      addTearDown(() => directory.delete(recursive: true));
      final flutterBefore = FlutterError.onError;
      final dispatcherBefore = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = flutterBefore;
        PlatformDispatcher.instance.onError = dispatcherBefore;
      });
      Future<List<Map>> exits() async =>
          ((await UncaughtErrors(directory).read(kind: 'unclean_exit'))['records']
                  as List)
              .cast<Map>();

      final crashed = UncaughtErrors(directory, appVersion: '1.0');
      await crashed.attach();
      crashed.notePlayback({'status': 'playing', 'path': '/media/b.mkv'});
      crashed.record('flutter', 'once', null);
      crashed.record('flutter', 'once', null);
      // That run ends here: no exiting(), no detach() before the next start.
      await crashed.read();

      final next = UncaughtErrors(directory);
      await next.attach();
      final reported = await exits();
      expect(reported, hasLength(1));
      expect(reported.single['playback'],
          {'status': 'playing', 'path': '/media/b.mkv'});
      expect(reported.single['appVersion'], '1.0');
      // Only releases this test's port; the next run has been checked.
      await crashed.detach();
      await next.exiting();
      await next.detach();

      final third = UncaughtErrors(directory);
      await third.attach();
      expect(await exits(), hasLength(1));
      await third.detach();
      final counted = (await UncaughtErrors(directory)
              .read(kind: 'uncaught_error'))['records'] as List;
      expect(counted.single['message'], 'once');
      expect(counted.single['count'], 2);
    });
  });

  group('Classic with Next off', () {
    test('nothing listens to the kernels and no handler is wrapped', () {
      final flutterBefore = FlutterError.onError;
      expect(PlayerNativeLogTap.observer, isNull);
      final unattached = UncaughtErrors(Directory.systemTemp);
      expect(unattached.recording, isFalse);
      expect(FlutterError.onError == flutterBefore, isTrue);
    });
  });
}
