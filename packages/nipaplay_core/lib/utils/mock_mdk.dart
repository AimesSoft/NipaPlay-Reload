// lib/utils/mock_mdk.dart

// 这是一个模拟实现，用于在Web平台上提供与 `fvp/mdk.dart` 相同的 API。
// 在Web上，没有 MDK，因此我们返回一个默认值。

int version() {
  return 0;
}

class Player {
  Player();
}

class PlaybackState {
  static const stopped = 0;
  static const paused = 1;
  static const playing = 2;
}

class MediaType {
  static const unknown = 0;
  static const video = 1;
  static const audio = 2;
  static const subtitle = 3;
} 