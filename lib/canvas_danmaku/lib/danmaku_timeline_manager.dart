import 'package:flutter/material.dart';
import 'danmaku_content_item.dart';

/// 弹幕时间轴管理器
///
/// 负责处理时间轴跳转时的弹幕状态计算，
/// 确保跳转后能立即显示所有应该在屏幕上的弹幕。
class DanmakuTimelineManager {
  /// 筛选出在指定时间点应该显示的弹幕列表
  ///
  /// [allDanmaku]: 所有的弹幕原始数据
  /// [currentTimeSeconds]: 当前的视频播放时间（秒）
  /// [scrollDanmakuDuration]: 滚动弹幕的持续时间（秒）
  /// [staticDanmakuDuration]: 静态弹幕的持续时间（秒）
  static List<Map<String, dynamic>> getDanmakuForTimeJump({
    required List<Map<String, dynamic>> allDanmaku,
    required double currentTimeSeconds,
    int scrollDanmakuDuration = 10,
    int staticDanmakuDuration = 5,
  }) {
    // 筛选出在当前时间点应该显示的弹幕
    var visibleDanmakuData = allDanmaku.where((danmaku) {
      final danmakuTime = (danmaku['time'] ?? 0.0) as double;
      
      // 🔥 关键修复：弹幕的出现时间必须在 (当前时间 - 持续时间) 和 当前时间 之间
      // 这样才能确保筛选出的是当前正在屏幕上运动的弹幕
      final double startTime = currentTimeSeconds - scrollDanmakuDuration;
      final double endTime = currentTimeSeconds;

      return danmakuTime >= startTime && danmakuTime <= endTime;
      
    }).toList();

    // 按照原始时间顺序排序，确保轨道分配的确定性
    visibleDanmakuData.sort((a, b) {
      final timeA = (a['time'] ?? 0.0) as double;
      final timeB = (b['time'] ?? 0.0) as double;
      return timeA.compareTo(timeB);
    });

    return visibleDanmakuData;
  }
} 