/// Web stub for DanmakuLayoutEngine.
///
/// Provides the same public API as [danmaku_layout_io.dart] without
/// any `dart:ffi` / `package:ffi` imports, so it compiles on Web.
/// On Web the engine is never actually used
/// (nipaplay_next_engine.dart guards with `kIsWeb`), so all method
/// bodies simply throw.

// ──── NpResultCode (mirror of types/native_types.dart, no FFI) ────

enum NpResultCode {
  ok,
  errInvalidArg,
  errNullPtr,
  errOom,
  errInternal,
  errNotFound,
}

NpResultCode npResultCodeFromInt(int code) {
  return switch (code) {
    0 => NpResultCode.ok,
    1 => NpResultCode.errInvalidArg,
    2 => NpResultCode.errNullPtr,
    3 => NpResultCode.errOom,
    4 => NpResultCode.errInternal,
    5 => NpResultCode.errNotFound,
    _ => NpResultCode.errInternal,
  };
}

// ──── NativeResult / NativeException (mirror of types/native_result.dart) ────

class NativeResult<T> {
  final T? value;
  final NpResultCode code;
  final String? errorMessage;

  const NativeResult.ok(T v)
      : value = v,
        code = NpResultCode.ok,
        errorMessage = null;

  const NativeResult.err(this.code, [this.errorMessage]) : value = null;

  bool get isOk => code == NpResultCode.ok;

  T get requireValue =>
      isOk ? value! : throw NativeException(code, errorMessage);
}

class NativeException implements Exception {
  final NpResultCode code;
  final String? message;

  const NativeException(this.code, [this.message]);

  @override
  String toString() =>
      'NativeException($code${message != null ? ": $message" : ""})';
}

// ──── DanmakuLayoutResult ────

class DanmakuLayoutResult {
  final int itemIndex;
  final int trackIndex;
  final double yPosition;
  final double scrollSpeed;

  const DanmakuLayoutResult({
    required this.itemIndex,
    required this.trackIndex,
    required this.yPosition,
    required this.scrollSpeed,
  });
}

// ──── DanmakuLayoutInput ────

class DanmakuLayoutInput {
  final double timeSeconds;
  final double textWidth;
  final double fontSizeMultiplier;
  final int type;
  final bool isMe;
  final int stackHash;

  const DanmakuLayoutInput({
    required this.timeSeconds,
    required this.textWidth,
    required this.fontSizeMultiplier,
    required this.type,
    required this.isMe,
    required this.stackHash,
  });
}

// ──── DanmakuLayoutEngine (stub — never called on Web) ────

/// Stub implementation for Web platforms.
/// The real engine requires dart:ffi which is unavailable on Web.
/// [NipaPlayNextEngine._tryInitNativeEngine] guards with `kIsWeb`,
/// so this class is never actually instantiated on Web.
class DanmakuLayoutEngine {
  int _itemCount = 0;

  int get itemCount => _itemCount;

  NativeResult<void> configure({
    required List<DanmakuLayoutInput> inputs,
    required double width,
    required double height,
    required double fontSize,
    required double displayArea,
    required double scrollDuration,
    required bool allowStacking,
    required double baseDanmakuHeight,
    required double baseTrackHeight,
  }) {
    throw UnsupportedError('DanmakuLayoutEngine is not available on Web');
  }

  NativeResult<List<DanmakuLayoutResult>> frame(double currentTime) {
    throw UnsupportedError('DanmakuLayoutEngine is not available on Web');
  }

  void dispose() {}
}
