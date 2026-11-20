import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class _OpacityState extends Fake implements VideoPlayerState {
  _OpacityState(this.danmakuOpacity);

  @override
  final double danmakuOpacity;
}

void main() {
  test('弹幕透明度设为 0.5 时，渲染器拿到的就是 0.5，不再平方', () {
    expect(_OpacityState(0.5).mappedDanmakuOpacity, 0.5);
  });

  test('0.7 不再变成 0.49，两端取值保持不变', () {
    expect(_OpacityState(0.7).mappedDanmakuOpacity, 0.7);
    expect(_OpacityState(0.0).mappedDanmakuOpacity, 0.0);
    expect(_OpacityState(1.0).mappedDanmakuOpacity, 1.0);
  });
}
