import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'hotkey_service.dart';
import 'dart:async';

/// 快捷键提示管理器，用于统一管理和更新所有快捷键提示
class ShortcutTooltipManager extends ChangeNotifier {
  static final ShortcutTooltipManager _instance = ShortcutTooltipManager._internal();
  
  // 单例模式
  factory ShortcutTooltipManager() {
    return _instance;
  }
  
  ShortcutTooltipManager._internal() {
    _initialize();
  }
  
  // 快捷键映射
  final Map<String, String> _shortcutTooltips = {};
  
  // 热键服务
  final HotkeyService _hotkeyService = HotkeyService();
  
  // 是否已初始化
  bool _isInitialized = false;
  
  // 初始化
  Future<void> _initialize() async {
    if (_isInitialized) return;
    
    // 从HotkeyService加载快捷键
    _updateShortcuts();
    
    // 监听快捷键变化
    _hotkeyService.addListener(_updateShortcuts);
    
    _isInitialized = true;
  }
  
  // 更新快捷键
  void _updateShortcuts() {
    final shortcuts = _hotkeyService.allShortcuts;
    
    _shortcutTooltips.clear();
    
    shortcuts.forEach((action, shortcut) {
      final actionLabel = _getActionLabel(action);
      if (actionLabel != null) {
        _shortcutTooltips[action] = shortcut.isEmpty ? actionLabel : '$actionLabel ($shortcut)';
      }
    });
    
    // 通知所有监听者
    notifyListeners();
  }
  
  // 获取动作标签
  String? _getActionLabel(String action) {
    final Map<String, String> actionLabels = {
      'play_pause': '播放/暂停',
      'fullscreen': '全屏',
      'rewind': '快退',
      'forward': '快进',
      'toggle_danmaku': '显示/隐藏弹幕',
      'volume_up': '增大音量',
      'volume_down': '减小音量',
      'previous_episode': '上一话',
      'next_episode': '下一话',
      'send_danmaku': '发送弹幕',
      'skip': '跳过',
    };
    
    return actionLabels[action];
  }
  
  // 获取动作的提示文本
  String getTooltip(String action) {
    return _shortcutTooltips[action] ?? _getActionLabel(action) ?? action;
  }
  
  // 获取动作的快捷键文本
  String getShortcutText(String action) {
    final shortcut = _hotkeyService.getShortcutText(action);
    return shortcut;
  }
  
  // 格式化动作和快捷键
  String formatActionWithShortcut(String action, String? customLabel) {
    final label = customLabel ?? _getActionLabel(action) ?? action;
    final shortcut = getShortcutText(action);
    
    final result = shortcut.isEmpty ? label : '$label ($shortcut)';
    return result;
  }
  
  @override
  void dispose() {
    _hotkeyService.removeListener(_updateShortcuts);
    super.dispose();
  }
} 