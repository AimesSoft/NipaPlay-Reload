import 'package:flutter/material.dart';

class TimelineDanmakuService {
  /// 生成时间轴告知弹幕轨道
  /// 
  /// [videoDuration] 视频总时长
  static Map<String, dynamic> generateTimelineDanmaku(Duration videoDuration) {
    final totalSeconds = videoDuration.inSeconds;
    final List<Map<String, dynamic>> comments = [];

    final percentages = [0.25, 0.50, 0.75, 0.90];
    final labels = ['25%', '50%', '75%', '90%'];

    for (int i = 0; i < percentages.length; i++) {
      final time = totalSeconds * percentages[i];
      final content = '视频播放进度：${labels[i]}';
      
      comments.add({
        'time': time,                 // 时间 (double)
        'type': 'scroll',             // 类型 (string)
        'content': content,           // 内容 (string)
        'color': 'rgb(255,255,255)',  // 颜色 (string)
        // 添加其他兼容性字段
        't': time,
        'c': content,
        'y': 'scroll',
        'r': 'rgb(255,255,255)',
        'p': '', 
        'd': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'size': 25, // 默认字号
        'weight': 1, // 默认权重
      });
    }

    return {
      'name': '时间轴告知',
      'source': 'timeline',
      'count': comments.length,
      'comments': comments,
    };
  }
} 