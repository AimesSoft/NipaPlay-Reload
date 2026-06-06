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

  // 缓存的帧输出缓冲区，避免每帧 calloc/free 引起堆碎片化与尾延迟飙升
  Pointer<NpLayoutResult>? _outputItemsPtr;
  Pointer<NpFrameRawOutput>? _rawOutputPtr;
  Pointer<Int32>? _outputCountPtr;
  int _outputCapacity = 0;

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

    // 若弹幕数量增大导致现有输出缓冲区不足，则重新分配
    if (count > _outputCapacity) {
      if (_outputItemsPtr != null) calloc.free(_outputItemsPtr!);
      if (_rawOutputPtr != null) calloc.free(_rawOutputPtr!);
      if (_outputCountPtr != null) calloc.free(_outputCountPtr!);
      _outputItemsPtr = calloc<NpLayoutResult>(count);
      _rawOutputPtr = calloc<NpFrameRawOutput>(count);
      _outputCountPtr = calloc<Int32>();
      _outputCapacity = count;
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

    // 复用 configure() 时分配的输出缓冲区，避免每帧 calloc/free
    final outputItems = _outputItemsPtr!;
    final outputCount = _outputCountPtr!;
    final capacity = _outputCapacity;

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
  }

  /// 零分配帧查询：执行 FFI 调用后仅返回可见条目数，
  /// 调用方通过 [outputItemsPtr] 直接从 native 缓冲区读取字段，
  /// 避免每帧创建 List + N 个 Dart 对象。
  NativeResult<int> frameRaw(double currentTime) {
    _checkReleased();

    if (_itemCount == 0) {
      return const NativeResult.ok(0);
    }

    // ⚠️ Bug fix: was calling npLayoutFrame (V1 path outputting NpLayoutResult),
    // but this method's index accessors (rawItemIndex/rawTrackIndex/rawYPosition/rawScrollSpeed)
    // read from _outputItemsPtr (NpLayoutResult buffer), so npLayoutFrame is correct here.
    // For V2 zero-copy path with pre-computed x/offstageX/textWidth/type,
    // use frameRawData() which calls npLayoutFrameRaw into _rawOutputPtr.
    final result = NativeBindings.npLayoutFrame(
      _handle,
      currentTime,
      _outputItemsPtr!,
      _outputCapacity,
      _outputCountPtr!,
    );

    final code = npResultCodeFromInt(result.code);
    if (code != NpResultCode.ok) {
      final msg = result.message != nullptr
          ? result.message.cast<Utf8>().toDartString()
          : null;
      return NativeResult.err(code, msg);
    }

    return NativeResult.ok(_outputCountPtr!.value);
  }

  /// 索引访问器：frameRaw() 调用后，直接从 native 缓冲区读取字段，
  /// 避免创建中间 List + DanmakuLayoutResult 对象
  int rawItemIndex(int i) => (_outputItemsPtr! + i).ref.itemIndex;
  int rawTrackIndex(int i) => (_outputItemsPtr! + i).ref.trackIndex;
  double rawYPosition(int i) => (_outputItemsPtr! + i).ref.yPosition;
  double rawScrollSpeed(int i) => (_outputItemsPtr! + i).ref.scrollSpeed;

  /// 零拷贝帧查询 V2：C++ 端预计算 x / offstageX / textWidth / type，
  /// Dart 侧无需回查 _items[] 数组做 elapsed/switch/除法运算。
  /// 返回可见条目数，调用方通过 rawX/rawYPosition 等索引访问器读取。
  NativeResult<int> frameRawData(double currentTime) {
    _checkReleased();

    if (_itemCount == 0) {
      return const NativeResult.ok(0);
    }

    final result = NativeBindings.npLayoutFrameRaw(
      _handle,
      currentTime,
      _rawOutputPtr!,
      _outputCapacity,
      _outputCountPtr!,
    );

    final code = npResultCodeFromInt(result.code);
    if (code != NpResultCode.ok) {
      final msg = result.message != nullptr
          ? result.message.cast<Utf8>().toDartString()
          : null;
      return NativeResult.err(code, msg);
    }

    return NativeResult.ok(_outputCountPtr!.value);
  }

  /// 索引访问器 V2：frameRawData() 调用后，直接从 NpFrameRawOutput 缓冲区读取。
  /// C++ 端已预计算 x / offstageX / textWidth / type，
  /// Dart 侧无需回查 _items[] 数组，无需 elapsed/switch/除法运算。
  double rawYPositionV2(int i) => (_rawOutputPtr! + i).ref.yPosition;
  double rawX(int i) => (_rawOutputPtr! + i).ref.x;
  double rawScrollSpeedV2(int i) => (_rawOutputPtr! + i).ref.scrollSpeed;
  double rawOffstageX(int i) => (_rawOutputPtr! + i).ref.offstageX;
  double rawTextWidth(int i) => (_rawOutputPtr! + i).ref.textWidth;
  int rawItemIndexV2(int i) => (_rawOutputPtr! + i).ref.itemIndex;
  int rawType(int i) => (_rawOutputPtr! + i).ref.type;

  /// 获取已配置的弹幕条目数
  int get itemCount => _itemCount;

  void dispose() {
    if (!_isReleased) {
      _finalizer.detach(this);
      NativeBindings.npLayoutDestroy(_handle);
      // 释放缓存的帧输出缓冲区
      if (_outputItemsPtr != null) {
        calloc.free(_outputItemsPtr!);
        _outputItemsPtr = null;
      }
      if (_rawOutputPtr != null) {
        calloc.free(_rawOutputPtr!);
        _rawOutputPtr = null;
      }
      if (_outputCountPtr != null) {
        calloc.free(_outputCountPtr!);
        _outputCountPtr = null;
      }
      _outputCapacity = 0;
      _isReleased = true;
    }
  }

  void _checkReleased() {
    if (_isReleased) {
      throw StateError('DanmakuLayoutEngine used after dispose');
    }
  }
}
