
// lib/models/danmaku/ass_danmaku.dart
// 保存 弹幕数据 -> ASS 字幕文本 的结果

import 'package:nipaplay/constants/danmaku/ass_kind.dart';


/// 实际写入 ASS 的单条弹幕事件
class AssDanmakuEvent {

  const AssDanmakuEvent({
    required this.content,
    required this.startSeconds,
    required this.endSeconds,
    required this.colorRgb,
    required this.type,
  });

  final String      content;      // 弹幕文本内容
  final double      startSeconds; // 弹幕开始时间 (单位: 秒)
  final double      endSeconds;   // 弹幕结束时间 (单位: 秒)
  final int         colorRgb;     // 弹幕颜色 (RGB)
  final DanmakuKind type;         // 弹幕类型
}

/// ASS 文本及与其逐条对应的实际弹幕事件,
/// 表示一次弹幕转 ASS 的完整结果
class DanmakuAssConversionResult {
  const DanmakuAssConversionResult({
    required this.ass,    // 生成的完整 ASS 字幕文本
    required this.events, // 真正写入 ASS 的弹幕事件清单
  });

  final String ass;
  final List<AssDanmakuEvent> events;
}
