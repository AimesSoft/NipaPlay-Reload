import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';

class _StubPlayer extends Fake implements Player {
  _StubPlayer(this._state);

  PlaybackState _state;

  @override
  PlaybackState get state => _state;

  @override
  set state(PlaybackState value) => _state = value;

  @override
  String getPlayerKernelName() => 'MDK';
}

void main() {
  group('waitForPlaybackReady（MDK prepare 就绪门，issue #1010）', () {
    test('媒体解码首帧进入 paused 后放行', () async {
      final player = _StubPlayer(PlaybackState.stopped);
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 25), () {
          player.state = PlaybackState.paused;
        }),
      );
      await waitForPlaybackReady(
        player,
        cancelled: () => false,
        maxPolls: 100,
        pollInterval: const Duration(milliseconds: 10),
      );
    });

    test('媒体直接进入 playing 后放行', () async {
      final player = _StubPlayer(PlaybackState.stopped);
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 25), () {
          player.state = PlaybackState.playing;
        }),
      );
      await waitForPlaybackReady(
        player,
        cancelled: () => false,
        maxPolls: 100,
        pollInterval: const Duration(milliseconds: 10),
      );
    });

    test('prepare 后停在 stopped 必须超时，不得带着元数据放行', () async {
      // issue #1010：切集后新媒体打开失败，MDK 停在 stopped 但 duration>0。
      // 旧就绪判定在该状态下提前放行，updateTexture 等首帧十秒超时后进入
      // 静默恢复级联，播放页无提示退出。
      final player = _StubPlayer(PlaybackState.stopped);
      await expectLater(
        waitForPlaybackReady(
          player,
          cancelled: () => false,
          maxPolls: 3,
          pollInterval: const Duration(milliseconds: 5),
        ),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.message,
            'message',
            contains('stopped'),
          ),
        ),
      );
    });

    test('被更新的播放任务取代（cancelled）时静默返回，不抛错', () async {
      final player = _StubPlayer(PlaybackState.stopped);
      await waitForPlaybackReady(
        player,
        cancelled: () => true,
        maxPolls: 3,
        pollInterval: const Duration(milliseconds: 5),
      );
    });
  });
}
