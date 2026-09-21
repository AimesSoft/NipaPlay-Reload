import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/player_kernel_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class _SyncPlayerDelegate extends Fake implements AbstractPlayer {
  int disposeCalls = 0;

  @override
  double get volume => 0.5;

  @override
  set volume(double value) {}

  @override
  void dispose() {
    disposeCalls++;
  }
}

class _ControlledAsyncPlayerDelegate extends Fake
    implements AbstractPlayer, AsyncDisposablePlayer {
  final Completer<void> _disposeCompleter = Completer<void>();
  int disposeCalls = 0;
  int disposeAsyncCalls = 0;

  @override
  double get volume => 0.5;

  @override
  set volume(double value) {}

  @override
  void dispose() {
    disposeCalls++;
  }

  @override
  Future<void> disposeAsync() {
    disposeAsyncCalls++;
    return _disposeCompleter.future;
  }

  void completeDisposal() {
    if (!_disposeCompleter.isCompleted) {
      _disposeCompleter.complete();
    }
  }

  void failDisposal(Object error) {
    if (!_disposeCompleter.isCompleted) {
      _disposeCompleter.completeError(error);
    }
  }
}

class _HotSwapVideoPlayerState extends Fake implements VideoPlayerState {
  _HotSwapVideoPlayerState(this._player);

  Player _player;
  int replacementAssignments = 0;

  @override
  bool get isDisposed => false;

  @override
  String? get currentVideoPath => null;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => Duration.zero;

  @override
  double get progress => 0;

  @override
  double get playbackRate => 1;

  @override
  PlayerStatus get status => PlayerStatus.idle;

  @override
  Player get player => _player;

  @override
  set player(Player value) {
    replacementAssignments++;
    _player = value;
  }

  @override
  String? get animeTitle => null;

  @override
  String? get episodeTitle => null;

  @override
  int? get animeId => null;

  @override
  int? get episodeId => null;
}

void main() {
  group('Player disposal lifecycle', () {
    test('synchronous delegates are disposed exactly once', () async {
      final delegate = _SyncPlayerDelegate();
      final player = Player.withDelegate(delegate);

      player.dispose();
      player.dispose();
      await player.disposeAsync();

      expect(delegate.disposeCalls, 1);
    });

    test('async and sync entry points share one teardown future', () async {
      final delegate = _ControlledAsyncPlayerDelegate();
      final player = Player.withDelegate(delegate);

      final firstDisposal = player.disposeAsync();
      player.dispose();
      final secondDisposal = player.disposeAsync();

      expect(identical(firstDisposal, secondDisposal), isTrue);
      expect(delegate.disposeAsyncCalls, 1);
      expect(delegate.disposeCalls, 0);

      delegate.completeDisposal();
      await Future.wait(<Future<void>>[firstDisposal, secondDisposal]);
    });

    test('failed async disposal remains memoized', () async {
      final delegate = _ControlledAsyncPlayerDelegate();
      final player = Player.withDelegate(delegate);
      final firstDisposal = player.disposeAsync();
      final expectation = expectLater(firstDisposal, throwsStateError);

      delegate.failDisposal(StateError('teardown failed'));
      await expectation;
      await expectLater(player.disposeAsync(), throwsStateError);

      expect(delegate.disposeAsyncCalls, 1);
      expect(delegate.disposeCalls, 0);
    });
  });

  group('hot-swap teardown schedule', () {
    // 旧契约「teardown 超时/失败则中止切换」会让主线程等旧内核 dispose，
    // MDK -> libmpv 实测卡死闪退（iOS watchdog 10s kill）。新契约：新播放
    // 器先就绪，旧内核在 finally 里 unawaited 异步销毁，超时/异常只记日志。
    final source =
        File('lib/utils/player_kernel_manager.dart').readAsStringSync();

    test('swap flow schedules teardown without awaiting it', () {
      final wrapperStart =
          source.indexOf('static Future<void> performPlayerKernelHotSwap(');
      final wrapperEnd =
          source.indexOf('_scheduleOldPlayerTeardown(', wrapperStart);
      final wrapper = source.substring(wrapperStart, wrapperEnd);
      expect(wrapperStart, greaterThanOrEqualTo(0));
      expect(wrapper.contains('} finally {'), isTrue);
      expect(
        wrapper.contains('await performPlayerKernelHotSwapSteps('), isTrue);

      // 步骤本体不得 dispose 旧播放器（disposeAsync 只允许出现在后台
      // teardown 调度里）。
      final stepsStart =
          source.indexOf('static Future<void> performPlayerKernelHotSwapSteps(');
      final stepsEnd = source.indexOf('/// 为VideoPlayerState执行弹幕内核热切换',
          stepsStart);
      final steps = source.substring(stepsStart, stepsEnd);
      expect(stepsStart, greaterThan(wrapperStart));
      expect(steps.contains('disposeAsync'), isFalse);
      expect(steps.contains('resetPlayer()'), isTrue);
    });

    test('background teardown swallows timeout and error', () {
      final scheduleStart =
          source.indexOf('static void _scheduleOldPlayerTeardown(');
      final scheduleEnd = source.indexOf('/// 为VideoPlayerState执行播放器内核热切换',
          scheduleStart);
      final schedule = source.substring(scheduleStart, scheduleEnd);
      expect(scheduleStart, greaterThanOrEqualTo(0));
      expect(schedule.contains('unawaited('), isTrue);
      expect(schedule.contains('on TimeoutException'), isTrue);
      expect(schedule.contains('catch (error)'), isTrue);
      // 超时/失败分支只 debugPrint，不 throw、不 rethrow。
      expect(schedule.contains('throw'), isFalse);
      expect(schedule.contains('Error.throwWithStackTrace'), isFalse);
    });
  });

  test('desktop fullscreen callback checks disposal after awaiting', () {
    final source = File('lib/utils/video_player_state.dart').readAsStringSync();
    const signature = 'Future<void> _refreshFullscreenStateFromWindowManager({';
    final methodStart = source.indexOf(signature);
    final methodEnd = source.indexOf('void onWindowBlur()', methodStart);

    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);
    final awaitIndex = method.indexOf('await windowManager.isFullScreen()');
    final disposedGuardIndex = method.indexOf('if (_isDisposed');
    final notifyIndex = method.indexOf('_notifyListeners()');

    expect(awaitIndex, greaterThanOrEqualTo(0));
    expect(disposedGuardIndex, greaterThan(awaitIndex));
    expect(notifyIndex, greaterThan(disposedGuardIndex));
  });
}
