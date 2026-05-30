import 'dart:ffi';

/// NpDanmakuItem — 弹幕条目输入结构
/// 对应 C++ 侧的 NpDanmakuItem
/// 字段顺序必须与 C 结构体完全一致，Dart FFI 按声明顺序排列
final class NpDanmakuItem extends Struct {
  @Double()
  external double timeSeconds;

  @Double()
  external double textWidth;

  @Double()
  external double fontSizeMultiplier;

  @Int32()
  external int type; // 0=scroll, 1=top, 2=bottom

  @Int32()
  external int isMe; // 0=false, 1=true

  @Int32()
  external int stackHash; // Dart 预计算: text.hashCode ^ time.toInt()

  @Int32()
  external int reserved; // 对齐保留
}

/// NpLayoutResult — 布局结果输出结构
/// 对应 C++ 侧的 NpLayoutResult
final class NpLayoutResult extends Struct {
  @Double()
  external double yPosition;

  @Double()
  external double scrollSpeed;

  @Int32()
  external int itemIndex;

  @Int32()
  external int trackIndex;
}
