import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
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
    // 契约演进：
    //  v1「teardown 超时/失败则中止切换」→ 主线程等旧内核 dispose，MDK -> libmpv
    //     实测卡死闪退（iOS watchdog 10s kill）。
    //  v2「新播放器先就绪，旧内核最后 unawaited 异步销毁」→ 播放中切换时旧内核
    //     仍存活，新内核随即创建并起播，两个原生实例并存导致平台线程死锁（实测
    //     播放中切 libmpv 冻死，而主页无视频怎么切都不闪退）。
    //  v3（当前）「旧内核先强制退出（resetPlayer 停止 + dispose 彻底销毁），
    //     新内核再创建并起播」→ 同一时刻平台线程上只有一个原生实例。
    final source =
        File('lib/utils/player_kernel_manager.dart').readAsStringSync();

    test('swap flow force-quits old kernel before new one starts', () {
      // wrapper：finally 里保留旧实例 dispose 作为幂等兜底（覆盖无视频/异常路径）。
      final wrapperStart =
          source.indexOf('static Future<void> performPlayerKernelHotSwap(');
      final wrapperEnd = source.indexOf(
          'static Future<void> _disposePlayerForHotSwap(');
      final wrapper = source.substring(wrapperStart, wrapperEnd);
      expect(wrapperStart, greaterThanOrEqualTo(0));
      expect(wrapper.contains('} finally {'), isTrue);
      expect(
        wrapper.contains('await performPlayerKernelHotSwapSteps('), isTrue);

      // 步骤本体：顺序必须是 resetPlayer（停止）→ _disposePlayerForHotSwap
      // （强制退出旧内核）→ 创建新播放器实例。
      final stepsStart =
          source.indexOf('static Future<void> performPlayerKernelHotSwapSteps(');
      final stepsEnd = source.indexOf(
          '/// 为VideoPlayerState执行弹幕内核热切换', stepsStart);
      final steps = source.substring(stepsStart, stepsEnd);
      expect(stepsStart, greaterThan(wrapperStart));
      expect(steps.contains('resetPlayer()'), isTrue);
      expect(steps.contains('_disposePlayerForHotSwap('), isTrue);

      final resetIdx = steps.indexOf('await videoPlayerState.resetPlayer();');
      final disposeIdx = steps.indexOf('_disposePlayerForHotSwap(', resetIdx);
      final createIdx = steps.indexOf('videoPlayerState.player = Player();',
          disposeIdx);
      expect(resetIdx, greaterThan(0));
      expect(disposeIdx, greaterThan(resetIdx));
      expect(createIdx, greaterThan(disposeIdx));
    });

    test('old-kernel dispose helper swallows timeout and error', () {
      // 强制退出旧内核的 dispose 助手：超时/失败只记日志（新内核继续播放），
      // 绝不 throw、绝不 rethrow，避免拖垮已经正常起播的新内核。
      final disposeStart =
          source.indexOf('static Future<void> _disposePlayerForHotSwap(');
      final disposeEnd = source.indexOf(
          'static Future<void> performPlayerKernelHotSwapSteps(');
      final dispose = source.substring(disposeStart, disposeEnd);
      expect(disposeStart, greaterThanOrEqualTo(0));
      expect(disposeEnd, greaterThan(disposeStart));
      expect(dispose.contains('on TimeoutException'), isTrue);
      expect(dispose.contains('catch (error)'), isTrue);
      expect(dispose.contains('throw'), isFalse);
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
