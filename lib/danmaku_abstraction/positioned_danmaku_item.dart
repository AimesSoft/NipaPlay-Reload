import 'danmaku_content_item.dart';

/// Mutable layout result for a danmaku item.
///
/// x/y/offstageX are intentionally mutable so layout results can be reused
/// across frames without creating new objects every tick.
class PositionedDanmakuItem {
  final DanmakuContentItem content;
  double x;
  double y;
  double offstageX;
  final double time; // The original time of the danmaku

  /// 滚动弹幕的水平移动速度（像素/秒）。
  /// Painter 利用此值做增量定位，避免绝对位置计算在倍速下因帧间隔
  /// 抖动而产生视觉跳跃。非滚动弹幕此值为 0。
  double scrollSpeed;

  /// 弹幕文本宽度（像素）。Painter 利用此值做视口剔除，
  /// 跳过完全不可见的弹幕，避免无谓的 Paragraph 查找与绘制。
  double width;

  /// DFM 原始类型码：1 = ScrollRL（向左），6 = ScrollLR（向右），
  /// 4/5 = 顶部/底部静态。供序列化层据此给原生渲染器发送带符号的
  /// scroll_speed（RL 负、LR 正、静态 0），让原生端在两次提交帧之间
  /// 做 `x_render = x_submit + scroll_speed * dt` 插值。非 DFM 来源默认 0
  /// （不插值，行为不变）。
  int typeCode;

  /// Painter 增量定位使用的显示 X 坐标。
  /// 初始值为 NaN，Painter 首次渲染时从 [x] 初始化；
  /// 之后每帧按 `displayX -= scrollSpeed * dt` 递减，
  /// 消除绝对位置 `x = width - speed * elapsed` 在高倍速下的帧间隔抖动。
  /// 非 Next Canvas Painter 的消费者无需读写此字段。
  double displayX = double.nan;

  PositionedDanmakuItem({
    required this.content,
    required this.x,
    required this.y,
    required this.offstageX,
    required this.time,
    this.scrollSpeed = 0.0,
    this.width = 0.0,
    this.typeCode = 0,
  });
}
