import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'fullscreen_handler.dart';
import './globals.dart' as globals;

class KeyboardShortcuts {
  static const String _shortcutsKey = 'keyboard_shortcuts';
  static const int _debounceTime = 300; // 增加防抖时间到300毫秒
  static final Map<String, int> _lastTriggerTime = {};
  static final Map<String, bool> _isProcessing = {}; // 添加处理状态标记
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
      'volume_up': '↑',
      'volume_down': '↓',
      'previous_episode': 'Shift+←',
      'next_episode': 'Shift+→',
    });
    _updateKeyBindings();
  }

  // 注册动作处理器
  static void registerActionHandler(String action, Function handler) {
    _actionHandlers[action] = handler;
  }

  // 处理键盘事件
  static KeyEventResult handleKeyEvent(RawKeyEvent event, BuildContext context) {
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }
    debugPrint('[KeyboardShortcuts] handleKeyEvent received: ${event.logicalKey}');
    
    // 检查当前是否有文本输入焦点
    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus != null) {
      final currentWidget = currentFocus.context?.widget;
      // 如果当前焦点是文本输入相关的组件，不拦截键盘事件
      if (currentWidget is TextField || 
          currentWidget is TextFormField || 
          currentWidget is EditableText) {
        return KeyEventResult.ignored;
      }
    }

    // 先处理全屏相关的按键
    final fullscreenResult = FullscreenHandler.handleFullscreenKey(event, context);
    if (fullscreenResult == KeyEventResult.handled) {
      return fullscreenResult;
    }

    // 其他按键的正常处理逻辑
    for (final entry in _keyBindings.entries) {
      final action = entry.key;
      final key = entry.value;

      if ((action == 'volume_up' || action == 'volume_down') && globals.isPhone) {
        continue;
      }

      // 检查是否匹配当前键盘事件
      bool keyMatches = false;
      
      // 检查组合键
      if (action == 'previous_episode' && _shortcuts[action] == 'Shift+←') {
        keyMatches = event.logicalKey == LogicalKeyboardKey.arrowLeft && 
                    (event.data.logicalKey == LogicalKeyboardKey.arrowLeft &&
                     (HardwareKeyboard.instance.isShiftPressed || 
                      RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
                      RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftRight)));
      } else if (action == 'next_episode' && _shortcuts[action] == 'Shift+→') {
        keyMatches = event.logicalKey == LogicalKeyboardKey.arrowRight && 
                    (event.data.logicalKey == LogicalKeyboardKey.arrowRight &&
                     (HardwareKeyboard.instance.isShiftPressed || 
                      RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
                      RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftRight)));
      } else {
        // 普通单键检查
        keyMatches = event.logicalKey == key;
      }

      if (keyMatches) {
        final handler = _actionHandlers[action];
        if (handler == null) {
          debugPrint('[KeyboardShortcuts] Handler for $action is NULL');
          continue; 
        }

        bool isVolumeAction = (action == 'volume_up' || action == 'volume_down');

        if (isVolumeAction) {
          // 对于音量调节，允许连续触发，不经过 _shouldTrigger 的严格防抖
          debugPrint('[KeyboardShortcuts] Executing continuous handler for $action (key: ${event.logicalKey})');
          handler();
          return KeyEventResult.handled;
        } else {
          // 其他动作使用现有的 _shouldTrigger 防抖
          // bool shouldTrigger = _shouldTrigger(action); // _shouldTrigger 默认 allowContinuous: false
          // 为了保持之前的 debugPrint 结构，我们直接用之前的 if 块
          debugPrint('[KeyboardShortcuts] Matched non-volume action: $action for key: ${event.logicalKey}');
          bool shouldTrigger = _shouldTrigger(action);
          debugPrint('[KeyboardShortcuts] _shouldTrigger($action) returned: $shouldTrigger');
          if (shouldTrigger) {
            // final handler = _actionHandlers[action]; // handler 已经获取过了
            debugPrint('[KeyboardShortcuts] Handler for $action is ${handler == null ? "NULL" : "VALID"}'); // handler 已确认非null
            // if (handler != null) { // handler 已确认非null
            debugPrint('[KeyboardShortcuts] Executing handler for $action');
            handler();
            return KeyEventResult.handled;
            // }
          }
        }
      }
    }
    debugPrint('[KeyboardShortcuts] No action handled for ${event.logicalKey}');
    return KeyEventResult.ignored;
  }

  static bool _shouldTrigger(String action) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastTime = _lastTriggerTime[action] ?? 0;
    
    // 检查是否正在处理中
    if (_isProcessing[action] == true) {
      return false;
    }
    
    if (now - lastTime < _debounceTime) {
      return false;
    }
    
    _lastTriggerTime[action] = now;
    _isProcessing[action] = true;
    
    // 设置一个定时器来重置处理状态
    Future.delayed(const Duration(milliseconds: _debounceTime), () {
      _isProcessing[action] = false;
    });
    
    return true;
  }

  static Future<void> loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedShortcutsString = prefs.getString(_shortcutsKey);

    // 先加载默认值，确保所有预定义的快捷键都存在于 _shortcuts 初始状态
    Map<String, String> currentShortcutsConfig = {};
    currentShortcutsConfig.addAll({
      'play_pause': '空格',
      'fullscreen': 'Enter',
      'rewind': '←',
      'forward': '→',
      'toggle_danmaku': 'D',
      'volume_up': '↑',
      'volume_down': '↓',
      'previous_episode': 'Shift+←',
      'next_episode': 'Shift+→',
    });

    if (savedShortcutsString != null) {
      try {
        final Map<String, dynamic> decodedSaved = json.decode(savedShortcutsString);
        // 用保存的值覆盖/添加至默认配置，确保用户自定义的得以保留，新增的默认配置也能加入
        decodedSaved.forEach((key, value) {
          if (value is String) {
            currentShortcutsConfig[key] = value; 
          }
        });
      } catch (e) {
        //debugPrint('Error decoding saved shortcuts: $e. Using defaults.');
        // 解码失败，currentShortcutsConfig 保持为仅包含代码中定义的默认值
      }
    }
    // 至此, currentShortcutsConfig 包含了合并后的配置
    
    _shortcuts.clear();
    _shortcuts.addAll(currentShortcutsConfig);
    _updateKeyBindings(); // 根据最新的 _shortcuts 更新 _keyBindings
    
    // 将当前（可能已更新/合并的）快捷键配置保存回去，以确保新增的默认快捷键能被持久化
    await saveShortcuts(); 
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
      case '↑':
        return LogicalKeyboardKey.arrowUp;
      case '↓':
        return LogicalKeyboardKey.arrowDown;
      case '+':
        return LogicalKeyboardKey.equal;
      case '-':
        return LogicalKeyboardKey.minus;
      case 'PageUp':
        return LogicalKeyboardKey.pageUp;
      case 'PageDown':
        return LogicalKeyboardKey.pageDown;
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
      case 'S':
        return LogicalKeyboardKey.keyS;
      case 'T':
        return LogicalKeyboardKey.keyT;
      case 'B':
        return LogicalKeyboardKey.keyB;
      case '4':
        return LogicalKeyboardKey.digit4;
      case '6':
        return LogicalKeyboardKey.digit6;
      default:
        debugPrint("[KeyboardShortcuts] Unknown key string for shortcut: '$keyString', defaulting to space.");
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

  static Future<bool> hasSavedShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_shortcutsKey);
  }
} 