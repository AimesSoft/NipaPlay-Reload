import 'dart:ffi';
import 'package:ffi/ffi.dart';

import '../native_library.dart';
import '../types/native_types.dart';
import '../types/native_result.dart';
import '../types/native_layout_types.dart';
import 'native_bindings.dart';

/// 布局结果（Dart 侧，由 DanmakuLayoutEngine.frame 返回）
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

/// 弹幕条目输入（Dart 侧，传入 DanmakuLayoutEngine.configure）
class DanmakuLayoutInput {
  final double timeSeconds;
  final double textWidth; // ★ Dart 侧 TextPainter 预测量
  final double fontSizeMultiplier;
  final int type; // 0=scroll, 1=top, 2=bottom
  final bool isMe;
  final int stackHash; // text.hashCode ^ time.toInt()

  const DanmakuLayoutInput({
    required this.timeSeconds,
    required this.textWidth,
    required this.fontSizeMultiplier,
    required this.type,
    required this.isMe,
    required this.stackHash,
  });
}

/// C++ 弹幕布局引擎的 Dart FFI 封装
///
/// 负责轨道分配、碰撞检测、yPosition 计算。
/// 文本测量（TextPainter）由调用方在 Dart 侧完成后填入 textWidth。
/// 最终 x 坐标由调用方根据 scrollSpeed + currentTime 计算。
class DanmakuLayoutEngine implements Finalizable {
  NpHandle _handle;
  bool _isReleased = false;
  int _itemCount = 0;

  static final _finalizer = NativeFinalizer(
    NativeLibrary.instance.lookup<
        NativeFunction<Void Function(Pointer<Void>)>>('np_layout_destroy'),
  );

  DanmakuLayoutEngine._(this._handle) {
    _finalizer.attach(this, _handle, detach: this, externalSize: 8192);
  }

  /// 工厂构造：创建 C++ 布局引擎实例
  factory DanmakuLayoutEngine() {
    final handle = NativeBindings.npLayoutCreate();
    if (handle == nullptr) {
      throw const NativeException(
          NpResultCode.errNullPtr, 'failed to create DanmakuLayoutEngine');
    }
    return DanmakuLayoutEngine._(handle);
  }

  /// 配置引擎：Dart 侧预算文本宽度后传入
  ///
  /// [inputs] 弹幕条目列表（textWidth 由 Dart TextPainter 预测量）
  /// [size] 画布尺寸
  /// [fontSize] 基础字号
  /// [displayArea] 显示区域比例 (0.0~1.0)
  /// [scrollDuration] 滚动弹幕持续时间（秒）
  /// [allowStacking] 是否允许堆叠
  /// [baseDanmakuHeight] TextPainter 预测量的弹幕高度
  /// [baseTrackHeight] 预计算的轨道高度
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
    _checkReleased();

    final int count = inputs.length;
    if (count == 0) {
      _itemCount = 0;
      return const NativeResult.ok(null);
    }

    // 分配 C 结构体数组
    final cItems = calloc<NpDanmakuItem>(count);
    try {
      // 填充 C 结构体数组
      for (int i = 0; i < count; i++) {
        final input = inputs[i];
        final item = cItems + i;
        item.ref.timeSeconds = input.timeSeconds;
        item.ref.textWidth = input.textWidth;
        item.ref.fontSizeMultiplier = input.fontSizeMultiplier;
        item.ref.type = input.type;
        item.ref.isMe = input.isMe ? 1 : 0;
        item.ref.stackHash = input.stackHash;
        item.ref.reserved = 0;
      }

      final result = NativeBindings.npLayoutConfigure(
        _handle,
        cItems,
        count,
        width,
        height,
        fontSize,
        displayArea,
        scrollDuration,
        scrollDuration, // staticDuration = scrollDuration（与 Dart 原实现一致）
        allowStacking ? 1 : 0,
        baseDanmakuHeight,
        baseTrackHeight,
      );

      final code = npResultCodeFromInt(result.code);
      if (code != NpResultCode.ok) {
        final msg = result.message != nullptr
            ? result.message.cast<Utf8>().toDartString()
            : null;
        return NativeResult.err(code, msg);
      }

      _itemCount = count;
      return const NativeResult.ok(null);
    } finally {
      calloc.free(cItems);
    }
  }

  /// 每帧调用，同步返回布局结果
  ///
  /// Dart 侧根据返回的 trackIndex / yPosition / scrollSpeed 计算最终 x 坐标
  NativeResult<List<DanmakuLayoutResult>> frame(double currentTime) {
    _checkReleased();

    if (_itemCount == 0) {
      return const NativeResult.ok([]);
    }

    // 预分配输出缓冲区（最多与输入条目数相同）
    final capacity = _itemCount;
    final outputItems = calloc<NpLayoutResult>(capacity);
    final outputCount = calloc<Int32>();
    try {
      final result = NativeBindings.npLayoutFrame(
        _handle,
        currentTime,
        outputItems,
        capacity,
        outputCount,
      );

      final code = npResultCodeFromInt(result.code);
      if (code != NpResultCode.ok) {
        final msg = result.message != nullptr
            ? result.message.cast<Utf8>().toDartString()
            : null;
        return NativeResult.err(code, msg);
      }

      final int count = outputCount.value;
      final List<DanmakuLayoutResult> results = [];

      for (int i = 0; i < count; i++) {
        final ref = (outputItems + i).ref;
        results.add(DanmakuLayoutResult(
          itemIndex: ref.itemIndex,
          trackIndex: ref.trackIndex,
          yPosition: ref.yPosition,
          scrollSpeed: ref.scrollSpeed,
        ));
      }

      return NativeResult.ok(results);
    } finally {
      calloc.free(outputItems);
      calloc.free(outputCount);
    }
  }

  /// 获取已配置的弹幕条目数
  int get itemCount => _itemCount;

  void dispose() {
    if (!_isReleased) {
      _finalizer.detach(this);
      NativeBindings.npLayoutDestroy(_handle);
      _isReleased = true;
    }
  }

  void _checkReleased() {
    if (_isReleased) {
      throw StateError('DanmakuLayoutEngine used after dispose');
    }
  }
}
