import 'dart:ui' as ui;
import 'danmaku_content_item.dart';

class DanmakuItem {
  /// 弹幕内容
  final DanmakuContentItem content;

  /// 弹幕创建时间
  final int creationTime;

  /// 弹幕宽度
  final double width;

  /// 弹幕水平方向位置
  double xPosition;

  /// 弹幕竖直方向位置
  double yPosition;

  /// 弹幕布局缓存
  ui.Paragraph? paragraph;
  ui.Paragraph? strokeParagraph;

  DanmakuItem({
    required this.content,
    required this.creationTime,
    required this.width,
    this.xPosition = 0,
    this.yPosition = 0,
    this.paragraph,
    this.strokeParagraph,
  });
}
