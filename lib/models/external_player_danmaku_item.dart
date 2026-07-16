
// lib/models/external_player_danmaku_item.dart
// 外部播放器弹幕控制台使用的弹幕模型


/// 外部播放器实际加载的弹幕类型
enum ExternalPlayerDanmakuType {
  scroll,
  top,
  bottom,
}

/// 外部播放器实际加载并可在控制台中显示的一条弹幕
class ExternalPlayerDanmakuItem {
  const ExternalPlayerDanmakuItem({
    required this.id,
    required this.content,
    required this.startTime,
    required this.endTime,
    required this.colorRgb,
    required this.type,
    this.senderId,
    this.source,
  });

  final String id;                       // 当前会话内的稳定标识
  final String content;                  // 实际写入 ASS 的弹幕内容
  final Duration startTime;              // 实际显示开始时间
  final Duration endTime;                // 实际显示结束时间
  final int colorRgb;                    // 0xRRGGBB
  final String? senderId;                // 数据源提供的发送者标识
  final ExternalPlayerDanmakuType type;  // 弹幕类型
  final String? source;                  // 弹幕来源或轨道

  Duration get displayDuration => endTime - startTime;

  /// 当前媒体时间是否处于这条弹幕的实际显示区间
  bool isActiveAt(Duration position) { return position >= startTime && position < endTime; }
}
