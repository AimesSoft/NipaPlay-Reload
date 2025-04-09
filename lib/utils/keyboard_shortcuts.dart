import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';

class KeyboardShortcuts {
  static const String _shortcutsKey = 'keyboard_shortcuts';
  static const int _debounceTime = 200; // 防抖时间，单位毫秒
  static final Map<String, int> _lastTriggerTime = {}; // 记录每个按键的最后触发时间
  static final Map<String, LogicalKeyboardKey> _keyBindings = {};
  static final Map<String, String> _shortcuts = {};
  static final Map<String, Function> _actionHandlers = {};

  // 初始化默认快捷键
  static void initialize() {
    _shortcuts.addAll({
      'play_pause': '空格',
      'fullscreen': 'Enter',
      'rewind': '←',
      'forward': '→',
      'toggle_danmaku': 'D',
    });
    _updateKeyBindings();
  }

  // 注册动作处理器
  static void registerActionHandler(String action, Function handler) {
    _actionHandlers[action] = handler;
  }

  // 处理键盘事件
  static KeyEventResult handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }

    // 检查每个动作的快捷键
    for (final entry in _keyBindings.entries) {
      final action = entry.key;
      final key = entry.value;

      if (event.logicalKey == key && _shouldTrigger(action)) {
        final handler = _actionHandlers[action];
        if (handler != null) {
          handler();
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  static bool _shouldTrigger(String action) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastTime = _lastTriggerTime[action] ?? 0;
    
    if (now - lastTime < _debounceTime) {
      return false;
    }
    
    _lastTriggerTime[action] = now;
    return true;
  }

  static Future<void> loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedShortcuts = prefs.getString(_shortcutsKey);
    if (savedShortcuts != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(savedShortcuts);
        _shortcuts.clear();
        _shortcuts.addAll(Map<String, String>.from(decoded));
        _updateKeyBindings();
      } catch (e) {
        print('Error loading shortcuts: $e');
        // 如果加载失败，使用默认快捷键
        initialize();
      }
    } else {
      // 如果没有保存的快捷键，使用默认值
      initialize();
    }
  }

  static Future<void> saveShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shortcutsKey, json.encode(_shortcuts));
  }

  static void _updateKeyBindings() {
    _keyBindings.clear();
    for (final entry in _shortcuts.entries) {
      _keyBindings[entry.key] = _getKeyFromString(entry.value);
    }
  }

  static LogicalKeyboardKey _getKeyFromString(String keyString) {
    switch (keyString) {
      case '空格':
        return LogicalKeyboardKey.space;
      case 'Enter':
        return LogicalKeyboardKey.enter;
      case '←':
        return LogicalKeyboardKey.arrowLeft;
      case '→':
        return LogicalKeyboardKey.arrowRight;
      case 'P':
        return LogicalKeyboardKey.keyP;
      case 'K':
        return LogicalKeyboardKey.keyK;
      case 'F':
        return LogicalKeyboardKey.keyF;
      case 'D':
        return LogicalKeyboardKey.keyD;
      case 'J':
        return LogicalKeyboardKey.keyJ;
      case 'L':
        return LogicalKeyboardKey.keyL;
      case '4':
        return LogicalKeyboardKey.digit4;
      case '6':
        return LogicalKeyboardKey.digit6;
      default:
        return LogicalKeyboardKey.space;
    }
  }

  static String getShortcutText(String action) {
    return _shortcuts[action] ?? '';
  }

  static Future<void> setShortcut(String action, String shortcut) async {
    _shortcuts[action] = shortcut;
    _keyBindings[action] = _getKeyFromString(shortcut);
    await saveShortcuts();
  }

  static Map<String, String> get allShortcuts => Map.unmodifiable(_shortcuts);

  static String formatActionWithShortcut(String action, String shortcut) {
    return '$action ($shortcut)';
  }
} 