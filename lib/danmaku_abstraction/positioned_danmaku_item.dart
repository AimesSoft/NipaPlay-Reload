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

  PositionedDanmakuItem({
    required this.content,
    required this.x,
    required this.y,
    required this.offstageX,
    required this.time,
  });
}
