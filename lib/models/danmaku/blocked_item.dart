
// lib/models/danmaku/blocked_item.dart
// 弹幕屏蔽项目


/// 弹幕屏蔽规则类型.
enum BlockedItemType {
  keyword,
  regex,
  userId,
}

/// 弹幕屏蔽项目
class BlockedDanmakuItem {

  final String value;
  final BlockedItemType type;

  const BlockedDanmakuItem({
    required this.value,
    required this.type,
  });
}
