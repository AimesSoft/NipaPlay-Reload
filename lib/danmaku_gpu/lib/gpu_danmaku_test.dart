import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/video_player_state.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'gpu_danmaku_base_renderer.dart';
import 'gpu_danmaku_config.dart';
import 'gpu_danmaku_item.dart';

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

  /// 测试合并弹幕转换逻辑
  static void testMergeDanmakuConversion() {
    print('=== 测试合并弹幕转换逻辑 ===');
    
    // 创建一个测试渲染器
    final config = GPUDanmakuConfig();
    final renderer = TestRenderer(config: config);
    
    // 创建一个合并弹幕项目
    final mergedItem = GPUDanmakuItem(
      text: '测试弹幕',
      color: Colors.white,
      type: DanmakuItemType.top,
      timeOffset: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      fontSizeMultiplier: 1.5,
      countText: 'x3',
      isMerged: true,
      mergeCount: 3,
    );
    
    print('原始合并弹幕:');
    print('  文本: ${mergedItem.text}');
    print('  字体倍率: ${mergedItem.fontSizeMultiplier}');
    print('  计数文本: ${mergedItem.countText}');
    
    // 测试开启合并弹幕时的显示属性
    renderer.setMergeDanmaku(true);
    final mergedProps = renderer.getDanmakuDisplayProperties(mergedItem);
    print('\n开启合并弹幕时的显示属性:');
    print('  字体倍率: ${mergedProps['fontSizeMultiplier']}');
    print('  计数文本: ${mergedProps['countText']}');
    
    // 测试关闭合并弹幕时的显示属性
    renderer.setMergeDanmaku(false);
    final normalProps = renderer.getDanmakuDisplayProperties(mergedItem);
    print('\n关闭合并弹幕时的显示属性:');
    print('  字体倍率: ${normalProps['fontSizeMultiplier']}');
    print('  计数文本: ${normalProps['countText']}');
    
    print('==================');
  }

  /// 测试合并弹幕显示逻辑
  static void testMergeDanmakuDisplayLogic() {
    print('=== 测试合并弹幕显示逻辑 ===');
    
    // 模拟弹幕数据
    final List<Map<String, dynamic>> testDanmakuList = [
      {
        'content': '测试弹幕1',
        'time': 10.0,
        'type': 'top',
        'color': 'rgb(255,255,255)',
        'isMerged': true,
        'mergeCount': 3,
        'isFirstInGroup': true,
        'groupContent': '测试弹幕1',
      },
      {
        'content': '测试弹幕1',
        'time': 10.1,
        'type': 'top',
        'color': 'rgb(255,255,255)',
        'isMerged': true,
        'mergeCount': 3,
        'isFirstInGroup': false,
        'groupContent': '测试弹幕1',
      },
      {
        'content': '测试弹幕1',
        'time': 10.2,
        'type': 'top',
        'color': 'rgb(255,255,255)',
        'isMerged': true,
        'mergeCount': 3,
        'isFirstInGroup': false,
        'groupContent': '测试弹幕1',
      },
      {
        'content': '单独弹幕',
        'time': 11.0,
        'type': 'top',
        'color': 'rgb(255,255,255)',
        'isMerged': false,
        'mergeCount': 1,
        'isFirstInGroup': true,
        'groupContent': '单独弹幕',
      },
    ];
    
    print('原始弹幕列表:');
    for (int i = 0; i < testDanmakuList.length; i++) {
      final danmaku = testDanmakuList[i];
      print('  弹幕 $i: "${danmaku['content']}" - 合并:${danmaku['isMerged']} - 首条:${danmaku['isFirstInGroup']}');
    }
    
    // 测试开启合并弹幕时的显示逻辑
    print('\n开启合并弹幕时的显示逻辑:');
    for (int i = 0; i < testDanmakuList.length; i++) {
      final danmaku = testDanmakuList[i];
      final isMerged = danmaku['isMerged'] == true;
      final isFirstInGroup = danmaku['isFirstInGroup'] == true;
      
      if (isMerged && !isFirstInGroup) {
        print('  弹幕 $i: 跳过（合并弹幕但不是首条）');
      } else {
        print('  弹幕 $i: 显示 "${danmaku['content']}"');
      }
    }
    
    // 测试关闭合并弹幕时的显示逻辑
    print('\n关闭合并弹幕时的显示逻辑:');
    for (int i = 0; i < testDanmakuList.length; i++) {
      final danmaku = testDanmakuList[i];
      print('  弹幕 $i: 显示 "${danmaku['content']}"（转换为普通弹幕）');
    }
    
    print('==================');
  }
}

/// 测试用的渲染器类
class TestRenderer extends GPUDanmakuBaseRenderer {
  TestRenderer({required super.config}) : super(
    opacity: 1.0,
  );

  @override
  void onDanmakuAdded(GPUDanmakuItem item) {}

  @override
  void onDanmakuRemoved(GPUDanmakuItem item) {}

  @override
  void onDanmakuCleared() {}

  @override
  void paintDanmaku(Canvas canvas, Size size) {}
} 