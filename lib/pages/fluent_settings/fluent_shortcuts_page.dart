import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/utils/hotkey_service.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_info_bar.dart';

class FluentShortcutsPage extends StatefulWidget {
  const FluentShortcutsPage({super.key});

  @override
  State<FluentShortcutsPage> createState() => _FluentShortcutsPageState();
}

class _FluentShortcutsPageState extends State<FluentShortcutsPage> {
  // 热键服务实例
  final HotkeyService _hotkeyService = HotkeyService();
  
  // 当前快捷键配置
  Map<String, String>? _shortcuts;
  
  // 记录当前正在录制的动作
  String? _recordingAction;
  
  // 动作标签映射
  final Map<String, String> _actionLabels = {
    'play_pause': '播放/暂停',
    'fullscreen': '全屏',
    'rewind': '快退',
    'forward': '快进',
    'toggle_danmaku': '显示/隐藏弹幕',
    'volume_up': '增大音量',
    'volume_down': '减小音量',
    'previous_episode': '上一集',
    'next_episode': '下一集',
    'send_danmaku': '发送弹幕',
  };
  
  // 动作描述
  final Map<String, String> _actionDescriptions = {
    'play_pause': '切换视频的播放和暂停状态',
    'fullscreen': '进入或退出全屏模式',
    'rewind': '快退10秒',
    'forward': '快进10秒',
    'toggle_danmaku': '显示或隐藏弹幕',
    'volume_up': '增加音量',
    'volume_down': '减少音量',
    'previous_episode': '播放上一集',
    'next_episode': '播放下一集',
    'send_danmaku': '打开弹幕发送对话框',
  };
  
  // 动作图标映射
  final Map<String, IconData> _actionIcons = {
    'play_pause': FluentIcons.play,
    'fullscreen': FluentIcons.full_screen,
    'rewind': FluentIcons.rewind,
    'forward': FluentIcons.fast_forward,
    'toggle_danmaku': FluentIcons.comment,
    'volume_up': FluentIcons.volume3,
    'volume_down': FluentIcons.volume2,
    'previous_episode': FluentIcons.previous,
    'next_episode': FluentIcons.next,
    'send_danmaku': FluentIcons.send,
  };

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }
  
  // 加载当前快捷键配置
  Future<void> _loadShortcuts() async {
    // 确保HotkeyService已经加载了快捷键配置
    await _hotkeyService.loadShortcuts();
    _shortcuts = Map.from(_hotkeyService.allShortcuts);
    setState(() {});
  }
  
  // 获取动作对应的图标
  IconData _getActionIcon(String action) {
    return _actionIcons[action] ?? FluentIcons.key_phrase_extraction;
  }
  
  // 开始录制快捷键
  void _startRecording(String action) {
    setState(() {
      _recordingAction = action;
    });
  }
  
  // 停止录制快捷键
  void _stopRecording() {
    setState(() {
      _recordingAction = null;
    });
  }
  
  // 更新快捷键
  Future<void> _updateShortcut(String action, String shortcut) async {
    await _hotkeyService.updateShortcut(action, shortcut);
    await _loadShortcuts();
  }
  
  // 重置为默认快捷键
  Future<void> _resetToDefaults() async {
    final defaultShortcuts = {
      'play_pause': '空格',
      'fullscreen': 'Enter',
      'rewind': '←',
      'forward': '→',
      'toggle_danmaku': 'D',
      'volume_up': '↑',
      'volume_down': '↓',
      'previous_episode': 'Shift+←',
      'next_episode': 'Shift+→',
    };
    
    for (final entry in defaultShortcuts.entries) {
      await _hotkeyService.updateShortcut(entry.key, entry.value);
    }
    
    await _loadShortcuts();
    
    if (mounted) {
      FluentInfoBar.show(
        context,
        '已重置为默认快捷键',
        severity: InfoBarSeverity.success,
      );
    }
  }
  
  // 将PhysicalKeyboardKey转换为文本
  String _keyToText(PhysicalKeyboardKey key) {
    // 特殊键的映射
    final specialKeys = {
      PhysicalKeyboardKey.space: '空格',
      PhysicalKeyboardKey.enter: 'Enter',
      PhysicalKeyboardKey.arrowLeft: '←',
      PhysicalKeyboardKey.arrowRight: '→',
      PhysicalKeyboardKey.arrowUp: '↑',
      PhysicalKeyboardKey.arrowDown: '↓',
      PhysicalKeyboardKey.escape: 'Esc',
      PhysicalKeyboardKey.pageUp: 'PageUp',
      PhysicalKeyboardKey.pageDown: 'PageDown',
      PhysicalKeyboardKey.home: 'Home',
      PhysicalKeyboardKey.end: 'End',
      PhysicalKeyboardKey.tab: 'Tab',
    };
    
    if (specialKeys.containsKey(key)) {
      return specialKeys[key]!;
    }
    
    // 字母键 (A-Z)
    if (key == PhysicalKeyboardKey.keyA) return 'A';
    if (key == PhysicalKeyboardKey.keyB) return 'B';
    if (key == PhysicalKeyboardKey.keyC) return 'C';
    if (key == PhysicalKeyboardKey.keyD) return 'D';
    if (key == PhysicalKeyboardKey.keyE) return 'E';
    if (key == PhysicalKeyboardKey.keyF) return 'F';
    if (key == PhysicalKeyboardKey.keyG) return 'G';
    if (key == PhysicalKeyboardKey.keyH) return 'H';
    if (key == PhysicalKeyboardKey.keyI) return 'I';
    if (key == PhysicalKeyboardKey.keyJ) return 'J';
    if (key == PhysicalKeyboardKey.keyK) return 'K';
    if (key == PhysicalKeyboardKey.keyL) return 'L';
    if (key == PhysicalKeyboardKey.keyM) return 'M';
    if (key == PhysicalKeyboardKey.keyN) return 'N';
    if (key == PhysicalKeyboardKey.keyO) return 'O';
    if (key == PhysicalKeyboardKey.keyP) return 'P';
    if (key == PhysicalKeyboardKey.keyQ) return 'Q';
    if (key == PhysicalKeyboardKey.keyR) return 'R';
    if (key == PhysicalKeyboardKey.keyS) return 'S';
    if (key == PhysicalKeyboardKey.keyT) return 'T';
    if (key == PhysicalKeyboardKey.keyU) return 'U';
    if (key == PhysicalKeyboardKey.keyV) return 'V';
    if (key == PhysicalKeyboardKey.keyW) return 'W';
    if (key == PhysicalKeyboardKey.keyX) return 'X';
    if (key == PhysicalKeyboardKey.keyY) return 'Y';
    if (key == PhysicalKeyboardKey.keyZ) return 'Z';
    
    // 数字键 (0-9)
    if (key == PhysicalKeyboardKey.digit0) return '0';
    if (key == PhysicalKeyboardKey.digit1) return '1';
    if (key == PhysicalKeyboardKey.digit2) return '2';
    if (key == PhysicalKeyboardKey.digit3) return '3';
    if (key == PhysicalKeyboardKey.digit4) return '4';
    if (key == PhysicalKeyboardKey.digit5) return '5';
    if (key == PhysicalKeyboardKey.digit6) return '6';
    if (key == PhysicalKeyboardKey.digit7) return '7';
    if (key == PhysicalKeyboardKey.digit8) return '8';
    if (key == PhysicalKeyboardKey.digit9) return '9';
    
    // 功能键 (F1-F12)
    if (key == PhysicalKeyboardKey.f1) return 'F1';
    if (key == PhysicalKeyboardKey.f2) return 'F2';
    if (key == PhysicalKeyboardKey.f3) return 'F3';
    if (key == PhysicalKeyboardKey.f4) return 'F4';
    if (key == PhysicalKeyboardKey.f5) return 'F5';
    if (key == PhysicalKeyboardKey.f6) return 'F6';
    if (key == PhysicalKeyboardKey.f7) return 'F7';
    if (key == PhysicalKeyboardKey.f8) return 'F8';
    if (key == PhysicalKeyboardKey.f9) return 'F9';
    if (key == PhysicalKeyboardKey.f10) return 'F10';
    if (key == PhysicalKeyboardKey.f11) return 'F11';
    if (key == PhysicalKeyboardKey.f12) return 'F12';
    
    // 其他常见键
    if (key == PhysicalKeyboardKey.backspace) return '退格';
    if (key == PhysicalKeyboardKey.delete) return 'Del';
    if (key == PhysicalKeyboardKey.capsLock) return 'Caps';
    if (key == PhysicalKeyboardKey.numLock) return 'NumLock';
    if (key == PhysicalKeyboardKey.scrollLock) return 'ScrollLock';
    if (key == PhysicalKeyboardKey.printScreen) return 'PrtSc';
    if (key == PhysicalKeyboardKey.insert) return 'Ins';
    
    // 获取键的调试名称
    final String debugName = key.debugName ?? '';
    
    // 如果以上都不匹配，尝试获取更友好的名称
    if (debugName.isNotEmpty) {
      // 尝试从debugName中提取字母或数字
      final letterRegExp = RegExp(r'^Key([A-Z])$');
      final letterMatch = letterRegExp.firstMatch(debugName);
      if (letterMatch != null && letterMatch.groupCount >= 1) {
        return letterMatch.group(1)!;
      }
      
      // 尝试从debugName中提取数字
      final digitRegExp = RegExp(r'^Digit([0-9])$');
      final digitMatch = digitRegExp.firstMatch(debugName);
      if (digitMatch != null && digitMatch.groupCount >= 1) {
        return digitMatch.group(1)!;
      }
      
      return debugName;
    }
    
    // 最后的备选方案，使用toString()并提取最后一部分
    final fullName = key.toString();
    final parts = fullName.split('.');
    if (parts.length > 1) {
      return parts.last;
    }
    
    return fullName;
  }
  
  // 处理键盘事件
  void _handleKeyPress(RawKeyEvent event) {
    if (_recordingAction == null || event is! RawKeyDownEvent) return;
    
    // 忽略修饰键单独按下的事件
    if (event.physicalKey == PhysicalKeyboardKey.shiftLeft ||
        event.physicalKey == PhysicalKeyboardKey.shiftRight ||
        event.physicalKey == PhysicalKeyboardKey.controlLeft ||
        event.physicalKey == PhysicalKeyboardKey.controlRight ||
        event.physicalKey == PhysicalKeyboardKey.altLeft ||
        event.physicalKey == PhysicalKeyboardKey.altRight ||
        event.physicalKey == PhysicalKeyboardKey.metaLeft ||
        event.physicalKey == PhysicalKeyboardKey.metaRight) {
      return;
    }
    
    // 获取键的文本表示
    final keyText = _keyToText(event.physicalKey);
    
    // 如果是无法识别的键，显示提示并返回
    if (keyText.contains('PhysicalKeyboard') || keyText.contains('#')) {
      if (mounted) {
        FluentInfoBar.show(
          context,
          '无法识别的键位',
          content: event.physicalKey.toString(),
          severity: InfoBarSeverity.warning,
        );
      }
      _stopRecording();
      return;
    }
    
    // 构建修饰键列表
    List<String> modifiers = [];
    if (event.isShiftPressed) modifiers.add('Shift');
    if (event.isControlPressed) modifiers.add('Ctrl');
    if (event.isAltPressed) modifiers.add('Alt');
    if (event.isMetaPressed) modifiers.add('Meta');
    
    // 构建快捷键文本
    String shortcut = '';
    if (modifiers.isNotEmpty) {
      shortcut = '\${modifiers.join('+')}+\$keyText';
    } else {
      shortcut = keyText;
    }
    
    // 检查是否与现有快捷键冲突
    bool hasConflict = false;
    String? conflictAction;
    
    for (final entry in _shortcuts!.entries) {
      if (entry.key != _recordingAction && entry.value == shortcut) {
        hasConflict = true;
        conflictAction = _actionLabels[entry.key] ?? entry.key;
        break;
      }
    }
    
    if (hasConflict) {
      // 显示冲突提示
      _showConflictDialog(shortcut, conflictAction!);
    } else {
      // 无冲突，直接更新
      _updateShortcut(_recordingAction!, shortcut);
      _stopRecording();
    }
  }
  
  // 显示冲突对话框
  void _showConflictDialog(String shortcut, String conflictAction) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('快捷键冲突'),
        content: Text('快捷键"\$shortcut"已被"\$conflictAction"使用，是否替换？'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () {
              Navigator.of(context).pop();
              _stopRecording();
            },
          ),
          FilledButton(
            child: const Text('替换'),
            onPressed: () {
              Navigator.of(context).pop();
              _updateShortcut(_recordingAction!, shortcut);
              _stopRecording();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKey: _handleKeyPress,
      child: ScaffoldPage(
        header: const PageHeader(
          title: Text('快捷键设置'),
        ),
        content: _shortcuts == null
            ? const Center(child: ProgressRing())
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: ListView(
                  children: [
                    // 重置按钮卡片
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '快捷键管理',
                              style: FluentTheme.of(context).typography.subtitle,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('恢复默认快捷键'),
                                      const SizedBox(height: 4),
                                      Text(
                                        '将所有快捷键恢复为默认设置',
                                        style: FluentTheme.of(context).typography.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                Button(
                                  onPressed: _resetToDefaults,
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(FluentIcons.refresh, size: 16),
                                      SizedBox(width: 4),
                                      Text('重置'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 快捷键列表卡片
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '快捷键配置',
                              style: FluentTheme.of(context).typography.subtitle,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '点击快捷键按钮以修改对应的快捷键',
                              style: FluentTheme.of(context).typography.caption,
                            ),
                            const SizedBox(height: 16),
                            
                            // 快捷键列表
                            ..._actionLabels.keys.map((action) {
                              final label = _actionLabels[action]!;
                              final description = _actionDescriptions[action] ?? '';
                              final shortcut = _shortcuts![action] ?? '';
                              final isRecording = _recordingAction == action;
                              final icon = _getActionIcon(action);
                              
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: Row(
                                  children: [
                                    // 图标
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: FluentTheme.of(context).accentColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(
                                        icon,
                                        size: 16,
                                        color: FluentTheme.of(context).accentColor,
                                      ),
                                    ),
                                    
                                    const SizedBox(width: 16),
                                    
                                    // 标题和描述
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            label,
                                            style: const TextStyle(fontWeight: FontWeight.w500),
                                          ),
                                          if (description.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              description,
                                              style: FluentTheme.of(context).typography.caption,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    
                                    const SizedBox(width: 16),
                                    
                                    // 快捷键按钮
                                    _buildShortcutButton(
                                      isRecording ? '按下键位...' : (shortcut.isEmpty ? '点击设置' : shortcut),
                                      isRecording,
                                      () => _startRecording(action),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
  
  // 构建快捷键按钮
  Widget _buildShortcutButton(String text, bool isRecording, VoidCallback onPressed) {
    return Button(
      onPressed: isRecording ? null : onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isRecording 
              ? FluentTheme.of(context).accentColor.withOpacity(0.1)
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRecording) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: FluentTheme.of(context).accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: TextStyle(
                color: isRecording 
                    ? FluentTheme.of(context).accentColor
                    : null,
                fontWeight: isRecording ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}