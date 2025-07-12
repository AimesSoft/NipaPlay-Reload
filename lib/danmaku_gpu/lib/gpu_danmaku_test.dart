import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/video_player_state.dart';

/// GPU弹幕测试工具
class GPUDanmakuTest {
  static void analyzeDanmakuData(BuildContext context, double currentTimeSeconds) {
    final videoState = context.read<VideoPlayerState>();
    final activeList = videoState.getActiveDanmakuList(currentTimeSeconds);
    
    print('=== GPU弹幕数据分析 ===');
    print('当前时间: $currentTimeSeconds 秒');
    print('活跃弹幕总数: ${activeList.length}');
    
    Map<String, int> typeCount = {};
    Map<String, List<String>> typeSamples = {};
    
    for (int i = 0; i < activeList.length && i < 10; i++) { // 只看前10条
      final danmaku = activeList[i];
      final danmakuTime = (danmaku['time'] ?? 0.0) as double;
      final danmakuTypeRaw = danmaku['type'];
      final timeDiff = currentTimeSeconds - danmakuTime;
      
      // 弹幕文本字段名为 'content'
      final danmakuText = danmaku['content']?.toString() ?? '';
      
      // 类型标识符
      String danmakuTypeStr = danmakuTypeRaw.toString();
      
      // 判断是否为顶部弹幕
      bool isTopDanmaku = false;
      if (danmakuTypeRaw is String) {
        isTopDanmaku = (danmakuTypeRaw == 'top');
        danmakuTypeStr = '$danmakuTypeRaw (${isTopDanmaku ? "顶部" : "其他"})';
      } else if (danmakuTypeRaw is int) {
        isTopDanmaku = (danmakuTypeRaw == 5);
        danmakuTypeStr = '$danmakuTypeRaw (${isTopDanmaku ? "顶部" : "其他"})';
      }
      
      // 打印完整数据结构
      print('弹幕 #$i:');
      print('  -> 完整数据: $danmaku');
      print('  -> 类型原始值: $danmakuTypeRaw (${danmakuTypeRaw.runtimeType})');
      print('  -> 是否顶部弹幕: $isTopDanmaku');
      print('  -> 内容: "$danmakuText"');
      print('  -> 时间差: ${timeDiff.toStringAsFixed(2)}s');
      
      // 统计类型
      typeCount[danmakuTypeStr] = (typeCount[danmakuTypeStr] ?? 0) + 1;
      
      // 收集样本
      if (typeSamples[danmakuTypeStr] == null) {
        typeSamples[danmakuTypeStr] = [];
      }
      if (typeSamples[danmakuTypeStr]!.length < 3) {
        typeSamples[danmakuTypeStr]!.add(danmakuText);
      }
    }
    
    print('\n类型统计:');
    typeCount.forEach((type, count) {
      print('  $type: $count 条');
      if (typeSamples[type] != null) {
        print('    样本: ${typeSamples[type]!.join(", ")}');
      }
    });
    
    print('==================');
  }
} 