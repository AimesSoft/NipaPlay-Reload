import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/player/core/arbiter.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/kernel/native.dart';
import 'package:nipaplay/next/system/mdk_native_log.dart';
import 'package:nipaplay/next/system/player_native_log.dart';
import 'package:nipaplay/next/system/runtime_diagnostics.dart';
import 'package:nipaplay/next/system/uncaught_errors.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player/fake_driver.dart';
import 'player_test_support.dart';
import 'test_support.dart';

/// mpv as a kernel instance's handle, recording the log file it is told to
/// write.
class LoggingMpv implements MpvNative {
  final logFiles = <String>[];
  @override
  Future<void> logFile(String path) async => logFiles.add(path);
  @override
  Future<Object?> version() async => null;
  @override
  Future<Map<String, NativeRead>> read(List<String> names) async => {};
  @override
  Future<String?> write(String name, String value) async => null;
  @override
  Future<NativeReply> command(List<String> args,
          {Duration timeout = const Duration(seconds: 10)}) async =>
      (result: null, error: null);
}

/// A Media Kit instance, as the session that plays holds it.
Future<FakeDriver> mediaKitInstance() async {
  final lease = await KernelArbiter().acquire(KernelOwner.next, reason: 'test');
  return FakeDriver(lease, kernel: KernelId.mediaKit, native: LoggingMpv());
}

/// fvp's process-wide MDK log handler, held here.
class FakeLogHandlers implements MdkLogHandlers {
  FakeLogHandlers({this.channelOpen = true, this.current});
  @override
  bool channelOpen;
  @override
  void Function(mdk.LogLevel, String)? current;
  final sets = <void Function(mdk.LogLevel, String)?>[];
  @override
  void set(void Function(mdk.LogLevel, String)? handler) {
    sets.add(handler);
    channelOpen = true;
    current = handler;
  }

  /// MDK writing a line.
  void emit(mdk.LogLevel level, String line) => current?.call(level, line);
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
      final kernel = LoggingMpv();
      final log = PlayerNativeLog()..attach();
      final file = await log.startFile(kernel.logFile, directory);
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
      // A kernel that keeps no such log gives nothing to write through.
      expect(await PlayerNativeLog().startFile(null, directory), isNull);
    });

    test('the log file is refused while Next records nothing', () async {
      final directory = await Directory.systemTemp.createTemp('pf-cap-');
      addTearDown(() => directory.delete(recursive: true));
      final driver = await mediaKitInstance();
      final harness = Harness([
        RuntimeDiagnosticsCapability(
            errors: UncaughtErrors(directory),
            log: PlayerNativeLog(),
            kernel: () => driver,
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

  group('unread', () {
    test('an unclean exit is unread until diagnostics.errors returns it, '
        'across restarts; a summary reads nothing', () async {
      final directory = await Directory.systemTemp.createTemp('pf-unread-');
      addTearDown(() => directory.delete(recursive: true));
      final flutterBefore = FlutterError.onError;
      final dispatcherBefore = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = flutterBefore;
        PlatformDispatcher.instance.onError = dispatcherBefore;
      });
      final crashed = UncaughtErrors(directory);
      await crashed.attach();
      await crashed.read(summaryOnly: true);
      final next = UncaughtErrors(directory);
      await next.attach();
      addTearDown(next.detach);
      addTearDown(crashed.detach);
      final driver = await mediaKitInstance();
      final harness = Harness([
        RuntimeDiagnosticsCapability(
            errors: next,
            log: PlayerNativeLog(),
            kernel: () => driver,
            logDirectory: directory)
      ]);
      Future<Map> summary() async =>
          (await invokeCompleted(harness, 'diagnostics.errors',
              {'summaryOnly': true}))['uncleanExits'] as Map;
      expect(await summary(), containsPair('unread', 1));
      expect(await summary(), containsPair('unread', 1));
      next.record('flutter', 'first', null);
      next.record('flutter', 'first', null);
      next.record('isolate', 'second', null);
      final counts = await invokeCompleted(
          harness, 'diagnostics.errors', {'summaryOnly': true});
      expect(counts['thisRun'], {'errors': 2, 'occurrences': 3});
      expect(counts.containsKey('records'), isFalse);
      await invokeCompleted(harness, 'diagnostics.errors', {'kind': 'uncaught_error'});
      expect(await summary(), containsPair('unread', 1),
          reason: 'only what is returned becomes read');
      final listed = await invokeCompleted(
          harness, 'diagnostics.errors', {'kind': 'unclean_exit'});
      expect((listed['records'] as List), hasLength(1));
      expect(await summary(), containsPair('unread', 0));
      expect(await summary(), containsPair('total', 1));
      expect(((await UncaughtErrors(directory).read(summaryOnly: true))[
          'uncleanExits'] as Map)['unread'], 0);
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
  group('MDK log', () {
    test('each line still reaches the handler that was there, as it came, '
        'and that handler is back once Next is off', () {
      final heard = <(mdk.LogLevel, String)>[];
      void original(mdk.LogLevel level, String line) => heard.add((level, line));
      final handlers = FakeLogHandlers(current: original);
      final log = MdkNativeLog(handlers, environment: const {});
      final lines = <(String, String)>[];
      log.attach((level, text) => lines.add((level, text)));
      expect(handlers.current, isNot(original));
      handlers.emit(mdk.LogLevel.warning, 'avcodec: corrupted frame\n');
      expect(heard, [(mdk.LogLevel.warning, 'avcodec: corrupted frame\n')]);
      expect(lines, [('warning', 'avcodec: corrupted frame')]);
      log.detach();
      expect(handlers.current, original);
      handlers.emit(mdk.LogLevel.info, 'after');
      expect(heard.last, (mdk.LogLevel.info, 'after'));
      expect(lines, hasLength(1));
    });

    test('where MDK was silent it stays silent once Next is off; with '
        'MDK_LOG it is left alone', () {
      final silent = FakeLogHandlers(channelOpen: false);
      final log = MdkNativeLog(silent, environment: const {});
      final lines = <String>[];
      log.attach((_, text) => lines.add(text));
      silent.emit(mdk.LogLevel.error, 'open failed');
      expect(lines, ['open failed']);
      log.detach();
      expect(silent.current, isNull);

      final stderr = FakeLogHandlers(channelOpen: false);
      final untouched =
          MdkNativeLog(stderr, environment: const {'MDK_LOG': '1'});
      untouched.attach((_, __) {});
      expect(stderr.sets, isEmpty);
      expect(untouched.notAttached, 'mdk_log_env');
      untouched.detach();
      expect(stderr.sets, isEmpty);
    });

    test('Erika\'s own log ring is copied in, incrementally, as no one '
        'player\'s', () async {
      final log = PlayerNativeLog()..attach();
      addTearDown(log.detach);
      final asked = <int?>[];
      var ring = <Map<String, Object?>>[
        {
          'seq': 0,
          'unixMs': 1792500000000,
          'level': 'warn',
          'source': 'erika',
          'event': 'video_decoder_changed',
          'count': 1,
          'data': {
            'event': 'video_decoder_changed',
            'stage': 'hwaccel_videotoolbox_to_software',
          },
        },
        {
          'seq': 1,
          'unixMs': 1792500000100,
          'level': 'error',
          'source': 'ffmpeg',
          'event': null,
          'count': 3,
          'message': 'Failed setup for format videotoolbox_vld',
        },
      ];
      Future<Map<String, Object?>?> read(int? since) async {
        asked.add(since);
        return {
          'schema': 1,
          'oldestSeq': ring.first['seq'],
          'nextSeq': (ring.last['seq'] as int) + 1,
          'ffmpegCapture': 'bundled',
          'entries': [
            for (final entry in ring)
              if (since == null || (entry['seq'] as int) >= since) entry
          ],
        };
      }

      await PlayerNativeLogTap.engineLog!('erika', read);
      final first = log.read(currentInstance: 7);
      final lines = (first['lines'] as List).cast<Map>();
      expect(lines.map((l) => l['source']), ['engine', 'ffmpeg']);
      expect(lines.first, allOf(containsPair('kernel', 'erika'),
          containsPair('level', 'warn'), containsPair('currentPlayer', null)));
      expect(lines.first['text'], contains('hwaccel_videotoolbox_to_software'));
      expect(lines.first['at'],
          DateTime.utc(2026, 10, 20, 12, 40).toIso8601String(),
          reason: 'the time Erika wrote the entry');
      expect(lines.last, containsPair('repeated', 3));
      expect(first['erikaLog'],
          {'nextSeq': 2, 'missed': 0, 'ffmpegCapture': 'bundled'});

      // The next copy asks from where the last stopped; entries that left
      // the ring meanwhile are counted, not invented.
      ring = [
        {'seq': 5, 'level': 'info', 'source': 'erika', 'count': 1,
          'message': 'seek'},
      ];
      await log.pullEngineLog('erika', read);
      expect(asked, [null, 2]);
      final second = log.read(afterSequence: first['nextSequence'] as int);
      expect((second['lines'] as List).single['text'], 'seek');
      expect((second['erikaLog'] as Map)['missed'], 3);
      // Other kernels keep no such log.
      await log.pullEngineLog('mdk', read);
      expect(asked, hasLength(2));
    });

    test('player_log shows MDK lines as no one player\'s', () async {
      final handlers = FakeLogHandlers(current: (_, __) {});
      final log = PlayerNativeLog(
          mdk: MdkNativeLog(handlers, environment: const {}))
        ..attach();
      handlers.emit(mdk.LogLevel.error, 'tcp: Connection refused\n');
      final read = log.read(currentInstance: 7);
      expect(read['mdkLog'], {'reading': true, 'reason': null});
      expect((read['lines'] as List).single, allOf(
          containsPair('kernel', 'mdk'),
          containsPair('source', 'log'),
          containsPair('level', 'error'),
          containsPair('currentPlayer', null),
          containsPair('text', 'tcp: Connection refused')));
      await log.detach();
      expect(handlers.sets.last, isNotNull, reason: 'the original is back');
    });
  });
}
