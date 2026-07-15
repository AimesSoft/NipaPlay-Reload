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

  group('hot-swap teardown gate', () {
    test('timeout aborts before assigning a replacement player', () async {
      final delegate = _ControlledAsyncPlayerDelegate();
      final player = Player.withDelegate(delegate);
      final state = _HotSwapVideoPlayerState(player);

      await expectLater(
        PlayerKernelManager.performPlayerKernelHotSwap(
          state,
          playerDisposalTimeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(delegate.disposeAsyncCalls, 1);
      expect(state.replacementAssignments, 0);
      delegate.completeDisposal();
      await player.disposeAsync();
    });

    test('teardown failure aborts before assigning a replacement player',
        () async {
      final delegate = _ControlledAsyncPlayerDelegate();
      final player = Player.withDelegate(delegate);
      final state = _HotSwapVideoPlayerState(player);
      final swap = PlayerKernelManager.performPlayerKernelHotSwap(
        state,
        playerDisposalTimeout: const Duration(seconds: 1),
      );
      final expectation = expectLater(swap, throwsStateError);

      delegate.failDisposal(StateError('native teardown failed'));
      await expectation;

      expect(delegate.disposeAsyncCalls, 1);
      expect(state.replacementAssignments, 0);
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
