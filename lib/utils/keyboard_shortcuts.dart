import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class KeyboardShortcuts {
  static const String _shortcutsKey = 'keyboard_shortcuts';
  static Map<String, String> _shortcuts = {
    'play_pause': '空格',
    'fullscreen': 'Enter',
    'rewind': '←',
    'forward': '→',
  };

  static Map<String, LogicalKeyboardKey> _keyBindings = {
    'play_pause': LogicalKeyboardKey.space,
    'fullscreen': LogicalKeyboardKey.enter,
    'rewind': LogicalKeyboardKey.arrowLeft,
    'forward': LogicalKeyboardKey.arrowRight,
  };

  static Future<void> loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedShortcuts = prefs.getString(_shortcutsKey);
    if (savedShortcuts != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(savedShortcuts);
        _shortcuts = Map<String, String>.from(decoded);
        _updateKeyBindings();
      } catch (e) {
        print('Error loading shortcuts: $e');
      }
    }
  }

  static Future<void> saveShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shortcutsKey, json.encode(_shortcuts));
  }

  static void _updateKeyBindings() {
    _keyBindings = {
      'play_pause': _getKeyFromString(_shortcuts['play_pause'] ?? '空格'),
      'fullscreen': _getKeyFromString(_shortcuts['fullscreen'] ?? 'Enter'),
      'rewind': _getKeyFromString(_shortcuts['rewind'] ?? '←'),
      'forward': _getKeyFromString(_shortcuts['forward'] ?? '→'),
    };
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

  static LogicalKeyboardKey getKeyBinding(String action) {
    _keyBindings[action] = _getKeyFromString(_shortcuts[action] ?? '');
    return _keyBindings[action] ?? LogicalKeyboardKey.space;
  }

  static String formatActionWithShortcut(String action, String shortcut) {
    return '$action ($shortcut)';
  }

  static Future<void> setShortcut(String action, String shortcut) async {
    print('\n=== 设置快捷键 ===');
    print('动作: $action');
    print('新快捷键: $shortcut');
    
    _shortcuts[action] = shortcut;
    
    _keyBindings[action] = _getKeyFromString(shortcut);
    print('更新后的按键绑定: ${_keyBindings[action]}');
    
    await saveShortcuts();
    print('=== 快捷键设置完成 ===\n');
  }

  static Map<String, String> get allShortcuts => Map.unmodifiable(_shortcuts);
} 