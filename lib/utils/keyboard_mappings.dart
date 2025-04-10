import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KeyboardMappings {
  static Map<LogicalKeySet, Intent> get allMappings {
    final Map<LogicalKeySet, Intent> mappings = {};
    
    // 添加所有可能的按键组合
    void addKey(LogicalKeyboardKey key) {
      // 单独按键
      mappings[LogicalKeySet(key)] = VoidCallbackIntent(() {});
      
      // 带修饰键的组合
      final modifiers = [
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.altRight,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.metaRight,
      ];
      
      for (var modifier in modifiers) {
        mappings[LogicalKeySet(modifier, key)] = VoidCallbackIntent(() {});
      }
    }
    
    // 添加所有字母键
    final letterKeys = [
      LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyB, LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyE, LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyG, LogicalKeyboardKey.keyH, LogicalKeyboardKey.keyI,
      LogicalKeyboardKey.keyJ, LogicalKeyboardKey.keyK, LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyM, LogicalKeyboardKey.keyN, LogicalKeyboardKey.keyO,
      LogicalKeyboardKey.keyP, LogicalKeyboardKey.keyQ, LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyT, LogicalKeyboardKey.keyU,
      LogicalKeyboardKey.keyV, LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyX,
      LogicalKeyboardKey.keyY, LogicalKeyboardKey.keyZ,
    ];
    
    for (var key in letterKeys) {
      addKey(key);
    }
    
    // 添加所有数字键
    final numberKeys = [
      LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    
    for (var key in numberKeys) {
      addKey(key);
    }
    
    // 添加所有功能键
    final functionKeys = [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.delete,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.capsLock,
      LogicalKeyboardKey.scrollLock,
      LogicalKeyboardKey.numLock,
      LogicalKeyboardKey.insert,
      LogicalKeyboardKey.print,
      LogicalKeyboardKey.pause,
    ];
    
    for (var key in functionKeys) {
      addKey(key);
    }
    
    // 添加方向键
    final arrowKeys = [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ];
    
    for (var key in arrowKeys) {
      addKey(key);
    }
    
    // 添加F键
    final fKeys = [
      LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, LogicalKeyboardKey.f3,
      LogicalKeyboardKey.f4, LogicalKeyboardKey.f5, LogicalKeyboardKey.f6,
      LogicalKeyboardKey.f7, LogicalKeyboardKey.f8, LogicalKeyboardKey.f9,
      LogicalKeyboardKey.f10, LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
    ];
    
    for (var key in fKeys) {
      addKey(key);
    }
    
    return mappings;
  }
} 