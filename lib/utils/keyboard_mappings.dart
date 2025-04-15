import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KeyboardMappings {
  static Map<LogicalKeySet, Intent> get allMappings {
    final Map<LogicalKeySet, Intent> mappings = {};
    
    // 只注册特定功能键和控制键，避免注册普通字符键
    // 不再添加所有可能的按键组合，只添加应用实际需要的快捷键
    
    // 媒体控制相关快捷键
    mappings[LogicalKeySet(LogicalKeyboardKey.space)] = VoidCallbackIntent(() {});
    mappings[LogicalKeySet(LogicalKeyboardKey.enter)] = VoidCallbackIntent(() {});
    mappings[LogicalKeySet(LogicalKeyboardKey.arrowLeft)] = VoidCallbackIntent(() {});
    mappings[LogicalKeySet(LogicalKeyboardKey.arrowRight)] = VoidCallbackIntent(() {});
    
    // 添加特定字母键的快捷键
    final mediaControlLetters = [
      LogicalKeyboardKey.keyD, // 显示/隐藏弹幕
      LogicalKeyboardKey.keyP, // 播放/暂停
      LogicalKeyboardKey.keyF, // 全屏
    ];
    
    for (var key in mediaControlLetters) {
      mappings[LogicalKeySet(key)] = VoidCallbackIntent(() {});
    }
    
    return mappings;
  }
} 