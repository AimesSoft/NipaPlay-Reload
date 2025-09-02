import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'video_player_state.dart';
import 'danmaku_dialog_manager.dart'; // 导入弹幕对话框管理器

/// 热键管理服务，用于替代Flutter内部的键盘事件处理
class HotkeyService extends ChangeNotifier {
  static final HotkeyService _instance = HotkeyService._internal();
  static const String _shortcutsKey = 'keyboard_shortcuts';
  static const int _debounceTime = 300; // 防抖时间（毫秒）
  
  // 单例模式
  factory HotkeyService() {
    return _instance;
  }
  
  HotkeyService._internal();
  
  // 存储注册的热键
  final List<HotKey> _registeredHotkeys = [];
  
  // 快捷键配置
  final Map<String, String> _shortcuts = {};
  
  // 上下文，用于访问Provider
  BuildContext? _context;
  
  // 初始化热键服务
  Future<void> initialize(BuildContext context) async {
    _context = context;
    
    // 初始化hotkey_manager，但不注册任何热键
    await hotKeyManager.unregisterAll();
    
    // 加载快捷键配置
    await loadShortcuts();
    
    // 不在此处注册热键，等待明确调用
    ////debugPrint('[HotkeyService] 初始化完成，等待指令注册热键');
  }
  
  // 注册热键
  Future<void> registerHotkeys() async {
    // 先清理已注册的热键，再重新注册
    if (_registeredHotkeys.isNotEmpty) {
      //debugPrint('[HotkeyService] 清理现有热键后重新注册');
      await unregisterHotkeys();
    }
    await registerAllHotkeys();
  }
  
  // 注销热键
  Future<void> unregisterHotkeys() async {
    if (_registeredHotkeys.isEmpty) {
      //debugPrint('[HotkeyService] 没有已注册的热键需要注销');
      return;
    }
    //debugPrint('[HotkeyService] 开始注销 ${_registeredHotkeys.length} 个热键');
    await hotKeyManager.unregisterAll();
    // 清空已注册列表，以便下次可以重新注册
    _registeredHotkeys.clear();
    //debugPrint('[HotkeyService] 热键注销完成');
  }
  
  // 加载保存的快捷键配置
  Future<void> loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedShortcutsString = prefs.getString(_shortcutsKey);

    // 先加载默认值
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
      'send_danmaku': 'C', // 添加发送弹幕快捷键
    });

    if (savedShortcutsString != null) {
      try {
        final Map<String, dynamic> decodedSaved = json.decode(savedShortcutsString);
        // 用保存的值覆盖默认配置
        decodedSaved.forEach((key, value) {
          if (value is String) {
            currentShortcutsConfig[key] = value; 
          }
        });
      } catch (e) {
        ////debugPrint('[HotkeyService] 解析保存的快捷键配置失败: $e，使用默认配置');
      }
    }
    
    _shortcuts.clear();
    _shortcuts.addAll(currentShortcutsConfig);
    
    // 将当前配置保存回去
    await saveShortcuts();
    
    // 通知监听者
    notifyListeners();
    
    ////debugPrint('[HotkeyService] 加载快捷键配置完成: ${_shortcuts.toString()}');
  }
  
  // 保存快捷键配置
  Future<void> saveShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shortcutsKey, json.encode(_shortcuts));
  }
  
  // 注册所有热键
  Future<void> registerAllHotkeys() async {
    //debugPrint('[HotkeyService] 开始注册所有热键');
    // 先清除所有已注册的热键
    await hotKeyManager.unregisterAll();
    _registeredHotkeys.clear();
    
    // 注册播放/暂停热键
    await _registerHotkey('play_pause', '播放/暂停', _handlePlayPause);
    
    // 注册全屏热键
    await _registerHotkey('fullscreen', '全屏', _handleFullscreen);
    
    // 注册快退热键
    await _registerHotkey('rewind', '快退', _handleRewind);
    
    // 注册快进热键
    await _registerHotkey('forward', '快进', _handleForward);
    
    // 注册弹幕开关热键
    await _registerHotkey('toggle_danmaku', '弹幕开关', _handleToggleDanmaku);
    
    // 注册音量增加热键
    await _registerHotkey('volume_up', '音量+', _handleVolumeUp);
    
    // 注册音量减少热键
    await _registerHotkey('volume_down', '音量-', _handleVolumeDown);
    
    // 注册上一集热键
    await _registerHotkey('previous_episode', '上一集', _handlePreviousEpisode);
    
    // 注册下一集热键
    await _registerHotkey('next_episode', '下一集', _handleNextEpisode);
    
    // 注册发送弹幕热键
    await _registerHotkey('send_danmaku', '发送弹幕', _handleSendDanmaku);
    
    // 注册ESC键退出全屏
    await _registerEscapeKey();
    
    //debugPrint('[HotkeyService] 所有热键注册完成，已注册 ${_registeredHotkeys.length} 个热键');
  }
  
  // 注册单个热键
  Future<void> _registerHotkey(String action, String description, Function handler) async {
    final keyString = _shortcuts[action];
    if (keyString == null) {
      ////debugPrint('[HotkeyService] 未找到 $action 的快捷键配置');
      return;
    }
    
    try {
      final keyInfo = _parseKeyString(keyString);
      if (keyInfo == null) {
        ////debugPrint('[HotkeyService] 无法解析快捷键: $keyString');
        return;
      }
      
      final hotKey = HotKey(
        key: keyInfo.keyCode,
        modifiers: keyInfo.modifiers,
        scope: HotKeyScope.inapp,
      );
      
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (HotKey hotKey) {
          ////debugPrint('[HotkeyService] 热键触发: $description ($keyString)');
          handler();
        },
      );
      
      _registeredHotkeys.add(hotKey);
      ////debugPrint('[HotkeyService] 已注册热键: $description ($keyString)');
    } catch (e) {
      ////debugPrint('[HotkeyService] 注册热键失败 $description ($keyString): $e');
    }
  }
  
  // 特别处理ESC键
  Future<void> _registerEscapeKey() async {
    try {
      final hotKey = HotKey(
        key: PhysicalKeyboardKey.escape,
        scope: HotKeyScope.inapp,
      );
      
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (HotKey hotKey) {
          ////debugPrint('[HotkeyService] ESC键被按下 - 退出全屏');
          _handleEscape();
        },
      );
      
      _registeredHotkeys.add(hotKey);
      ////debugPrint('[HotkeyService] 已注册ESC热键');
    } catch (e) {
      ////debugPrint('[HotkeyService] 注册ESC热键失败: $e');
    }
  }
  
  // 解析键位字符串
  _KeyInfo? _parseKeyString(String keyString) {
    ////debugPrint('[HotkeyService] 解析键位字符串: $keyString');
    PhysicalKeyboardKey? keyCode;
    List<HotKeyModifier> modifiers = [];
    
    // 处理组合键
    if (keyString.contains('+')) {
      final parts = keyString.split('+');
      final keyPart = parts.last.trim(); // 最后一部分是主键
      
      // 处理所有修饰键（除了最后一部分）
      for (int i = 0; i < parts.length - 1; i++) {
        final modifierPart = parts[i].trim();
        
        switch (modifierPart.toLowerCase()) {
          case 'shift':
            modifiers.add(HotKeyModifier.shift);
            break;
          case 'ctrl':
            modifiers.add(HotKeyModifier.control);
            break;
          case 'alt':
            modifiers.add(HotKeyModifier.alt);
            break;
          case 'meta':
            modifiers.add(HotKeyModifier.meta);
            break;
        }
      }
      
      // 解析主键
      keyCode = _getKeyCodeFromString(keyPart);
      ////debugPrint('[HotkeyService] 解析组合键: 修饰键=${modifiers.length}个, 主键=$keyPart, 解析结果=${keyCode != null ? "成功" : "失败"}');
    } else {
      // 单键
      keyCode = _getKeyCodeFromString(keyString);
      ////debugPrint('[HotkeyService] 解析单键: $keyString, 解析结果=${keyCode != null ? "成功" : "失败"}');
    }
    
    if (keyCode == null) {
      ////debugPrint('[HotkeyService] 键位解析失败: $keyString');
      return null;
    }
    
    return _KeyInfo(keyCode, modifiers);
  }
  
  // 将字符串转换为PhysicalKeyboardKey
  PhysicalKeyboardKey? _getKeyCodeFromString(String keyString) {
    ////debugPrint('[HotkeyService] _getKeyCodeFromString: 尝试解析键位字符串: "$keyString"');
    
    // 特殊键的映射
    switch (keyString) {
      case '空格':
        return PhysicalKeyboardKey.space;
      case 'Enter':
        return PhysicalKeyboardKey.enter;
      case '←':
        return PhysicalKeyboardKey.arrowLeft;
      case '→':
        return PhysicalKeyboardKey.arrowRight;
      case '↑':
        return PhysicalKeyboardKey.arrowUp;
      case '↓':
        return PhysicalKeyboardKey.arrowDown;
      case 'Esc':
        return PhysicalKeyboardKey.escape;
      case '+':
        return PhysicalKeyboardKey.equal;
      case '-':
        return PhysicalKeyboardKey.minus;
      case 'PageUp':
        return PhysicalKeyboardKey.pageUp;
      case 'PageDown':
        return PhysicalKeyboardKey.pageDown;
      case 'Home':
        return PhysicalKeyboardKey.home;
      case 'End':
        return PhysicalKeyboardKey.end;
      case 'Tab':
        return PhysicalKeyboardKey.tab;
      case '退格':
        return PhysicalKeyboardKey.backspace;
      case 'Del':
        return PhysicalKeyboardKey.delete;
      case 'Caps':
        return PhysicalKeyboardKey.capsLock;
      case 'NumLock':
        return PhysicalKeyboardKey.numLock;
      case 'ScrollLock':
        return PhysicalKeyboardKey.scrollLock;
      case 'PrtSc':
        return PhysicalKeyboardKey.printScreen;
      case 'Ins':
        return PhysicalKeyboardKey.insert;
      case ';':
        return PhysicalKeyboardKey.semicolon;
      case '=':
        return PhysicalKeyboardKey.equal;
      case ',':
        return PhysicalKeyboardKey.comma;
      case '.':
        return PhysicalKeyboardKey.period;
      case '/':
        return PhysicalKeyboardKey.slash;
      case '`':
        return PhysicalKeyboardKey.backquote;
      case '[':
        return PhysicalKeyboardKey.bracketLeft;
      case '\\':
        return PhysicalKeyboardKey.backslash;
      case ']':
        return PhysicalKeyboardKey.bracketRight;
      case '\'':
        return PhysicalKeyboardKey.quote;
        
      // 单个字母键 (A-Z)
      case 'A': return PhysicalKeyboardKey.keyA;
      case 'B': return PhysicalKeyboardKey.keyB;
      case 'C': return PhysicalKeyboardKey.keyC;
      case 'D': return PhysicalKeyboardKey.keyD;
      case 'E': return PhysicalKeyboardKey.keyE;
      case 'F': return PhysicalKeyboardKey.keyF;
      case 'G': return PhysicalKeyboardKey.keyG;
      case 'H': return PhysicalKeyboardKey.keyH;
      case 'I': return PhysicalKeyboardKey.keyI;
      case 'J': return PhysicalKeyboardKey.keyJ;
      case 'K': return PhysicalKeyboardKey.keyK;
      case 'L': return PhysicalKeyboardKey.keyL;
      case 'M': return PhysicalKeyboardKey.keyM;
      case 'N': return PhysicalKeyboardKey.keyN;
      case 'O': return PhysicalKeyboardKey.keyO;
      case 'P': return PhysicalKeyboardKey.keyP;
      case 'Q': return PhysicalKeyboardKey.keyQ;
      case 'R': return PhysicalKeyboardKey.keyR;
      case 'S': return PhysicalKeyboardKey.keyS;
      case 'T': return PhysicalKeyboardKey.keyT;
      case 'U': return PhysicalKeyboardKey.keyU;
      case 'V': return PhysicalKeyboardKey.keyV;
      case 'W': return PhysicalKeyboardKey.keyW;
      case 'X': return PhysicalKeyboardKey.keyX;
      case 'Y': return PhysicalKeyboardKey.keyY;
      case 'Z': return PhysicalKeyboardKey.keyZ;
      
      // 数字键 (0-9)
      case '0': return PhysicalKeyboardKey.digit0;
      case '1': return PhysicalKeyboardKey.digit1;
      case '2': return PhysicalKeyboardKey.digit2;
      case '3': return PhysicalKeyboardKey.digit3;
      case '4': return PhysicalKeyboardKey.digit4;
      case '5': return PhysicalKeyboardKey.digit5;
      case '6': return PhysicalKeyboardKey.digit6;
      case '7': return PhysicalKeyboardKey.digit7;
      case '8': return PhysicalKeyboardKey.digit8;
      case '9': return PhysicalKeyboardKey.digit9;
    }
    
    // 功能键 (F1-F24)
    final functionKeyRegExp = RegExp(r'^F([0-9]{1,2})$');
    final functionKeyMatch = functionKeyRegExp.firstMatch(keyString);
    if (functionKeyMatch != null && functionKeyMatch.groupCount >= 1) {
      final number = int.tryParse(functionKeyMatch.group(1)!);
      if (number != null && number >= 1 && number <= 24) {
        switch (number) {
          case 1: return PhysicalKeyboardKey.f1;
          case 2: return PhysicalKeyboardKey.f2;
          case 3: return PhysicalKeyboardKey.f3;
          case 4: return PhysicalKeyboardKey.f4;
          case 5: return PhysicalKeyboardKey.f5;
          case 6: return PhysicalKeyboardKey.f6;
          case 7: return PhysicalKeyboardKey.f7;
          case 8: return PhysicalKeyboardKey.f8;
          case 9: return PhysicalKeyboardKey.f9;
          case 10: return PhysicalKeyboardKey.f10;
          case 11: return PhysicalKeyboardKey.f11;
          case 12: return PhysicalKeyboardKey.f12;
          case 13: return PhysicalKeyboardKey.f13;
          case 14: return PhysicalKeyboardKey.f14;
          case 15: return PhysicalKeyboardKey.f15;
          case 16: return PhysicalKeyboardKey.f16;
          case 17: return PhysicalKeyboardKey.f17;
          case 18: return PhysicalKeyboardKey.f18;
          case 19: return PhysicalKeyboardKey.f19;
          case 20: return PhysicalKeyboardKey.f20;
          case 21: return PhysicalKeyboardKey.f21;
          case 22: return PhysicalKeyboardKey.f22;
          case 23: return PhysicalKeyboardKey.f23;
          case 24: return PhysicalKeyboardKey.f24;
        }
      }
    }
    
    // 小键盘数字键
    final numpadRegExp = RegExp(r'^Num\s+([0-9])$');
    final numpadMatch = numpadRegExp.firstMatch(keyString);
    if (numpadMatch != null && numpadMatch.groupCount >= 1) {
      final number = int.tryParse(numpadMatch.group(1)!);
      if (number != null && number >= 0 && number <= 9) {
        switch (number) {
          case 0: return PhysicalKeyboardKey.numpad0;
          case 1: return PhysicalKeyboardKey.numpad1;
          case 2: return PhysicalKeyboardKey.numpad2;
          case 3: return PhysicalKeyboardKey.numpad3;
          case 4: return PhysicalKeyboardKey.numpad4;
          case 5: return PhysicalKeyboardKey.numpad5;
          case 6: return PhysicalKeyboardKey.numpad6;
          case 7: return PhysicalKeyboardKey.numpad7;
          case 8: return PhysicalKeyboardKey.numpad8;
          case 9: return PhysicalKeyboardKey.numpad9;
        }
      }
    }
    
    // 小键盘其他键
    switch (keyString) {
      case 'Num /': return PhysicalKeyboardKey.numpadDivide;
      case 'Num *': return PhysicalKeyboardKey.numpadMultiply;
      case 'Num -': return PhysicalKeyboardKey.numpadSubtract;
      case 'Num +': return PhysicalKeyboardKey.numpadAdd;
      case 'Num Enter': return PhysicalKeyboardKey.numpadEnter;
      case 'Num .': return PhysicalKeyboardKey.numpadDecimal;
    }
    
    debugPrint("[HotkeyService] 未知的键位字符串: '$keyString'");
    return null;
  }
  
  // 获取VideoPlayerState实例
  VideoPlayerState? _getVideoPlayerState() {
    if (_context == null) {
      ////debugPrint('[HotkeyService] 上下文为空，无法获取VideoPlayerState');
      return null;
    }
    
    try {
      return Provider.of<VideoPlayerState>(_context!, listen: false);
    } catch (e) {
      ////debugPrint('[HotkeyService] 获取VideoPlayerState失败: $e');
      return null;
    }
  }
  
  // 热键处理函数
  void _handlePlayPause() {
    final videoState = _getVideoPlayerState();
    if (videoState != null) {
      videoState.togglePlayPause();
    }
  }
  
  void _handleFullscreen() {
    final videoState = _getVideoPlayerState();
    if (videoState != null) {
      videoState.toggleFullscreen();
    }
  }
  
  void _handleRewind() {
    final videoState = _getVideoPlayerState();
    if (videoState != null) {
      final currentPosition = videoState.position;
      final newPosition = currentPosition - Duration(seconds: videoState.seekStepSeconds);
      videoState.seekTo(newPosition);
    }
  }
  
  void _handleForward() {
    final videoState = _getVideoPlayerState();
    if (videoState != null) {
      final currentPosition = videoState.position;
      final newPosition = currentPosition + Duration(seconds: videoState.seekStepSeconds);
      videoState.seekTo(newPosition);
    }
  }
  
  void _handleToggleDanmaku() {
    final videoState = _getVideoPlayerState();
    if (videoState != null) {
      videoState.toggleDanmakuVisible();
    }
  }
  
  void _handleVolumeUp() {
    final videoState = _getVideoPlayerState();
    if (videoState != null) {
      videoState.increaseVolume();
    }
  }
  
  void _handleVolumeDown() {
    final videoState = _getVideoPlayerState();
    if (videoState != null) {
      videoState.decreaseVolume();
    }
  }
  
  void _handlePreviousEpisode() {
    final videoState = _getVideoPlayerState();
    if (videoState != null) {
      videoState.playPreviousEpisode();
    }
  }
  
  void _handleNextEpisode() {
    final videoState = _getVideoPlayerState();
    if (videoState != null) {
      videoState.playNextEpisode();
    }
  }
  
  void _handleSendDanmaku() {
    ////debugPrint('[HotkeyService] 处理发送弹幕快捷键');
    
    // 先检查是否已经有弹幕对话框在显示
    final dialogManager = DanmakuDialogManager();
    
    // 如果已经在显示弹幕对话框，则关闭它，否则显示新对话框
    if (!dialogManager.handleSendDanmakuHotkey()) {
      // 对话框未显示，显示新对话框
      final videoState = _getVideoPlayerState();
      if (videoState != null) {
        videoState.showSendDanmakuDialog();
      }
    }
  }
  
  void _handleEscape() {
    final videoState = _getVideoPlayerState();
    if (videoState != null && videoState.isFullscreen) {
      videoState.toggleFullscreen();
    }
  }
  
  // 更新快捷键
  Future<void> updateShortcut(String action, String shortcut) async {
    ////debugPrint('[HotkeyService] 更新快捷键: $action -> $shortcut');
    _shortcuts[action] = shortcut;
    await saveShortcuts();
    await registerAllHotkeys(); // 重新注册所有热键
    notifyListeners(); // 通知监听者
  }
  
  // 获取所有快捷键配置
  Map<String, String> get allShortcuts => Map.unmodifiable(_shortcuts);
  
  // 获取指定动作的快捷键文本
  String getShortcutText(String action) {
    return _shortcuts[action] ?? '';
  }
  
  // 格式化动作和快捷键
  String formatActionWithShortcut(String action, String shortcut) {
    return '$action ($shortcut)';
  }
  
  // 清理资源
  @override
  Future<void> dispose() async {
    await hotKeyManager.unregisterAll();
    _registeredHotkeys.clear();
  }
}

// 用于存储键位信息的辅助类
class _KeyInfo {
  final PhysicalKeyboardKey keyCode;
  final List<HotKeyModifier> modifiers;
  
  _KeyInfo(this.keyCode, this.modifiers);
} 