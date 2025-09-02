import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/hotkey_service.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_item.dart';
import 'package:nipaplay/utils/message_helper.dart';
import 'dart:ui';

class ShortcutsSettingsPage extends StatefulWidget {
  const ShortcutsSettingsPage({super.key});

  @override
  State<ShortcutsSettingsPage> createState() => _ShortcutsSettingsPageState();
}

class _ShortcutsSettingsPageState extends State<ShortcutsSettingsPage> {
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
    'play_pause': Ionicons.play_outline,
    'fullscreen': Ionicons.expand_outline,
    'rewind': Ionicons.play_back_outline,
    'forward': Ionicons.play_forward_outline,
    'toggle_danmaku': Ionicons.chatbubbles_outline,
    'volume_up': Ionicons.volume_high_outline,
    'volume_down': Ionicons.volume_low_outline,
    'previous_episode': Ionicons.play_skip_back_outline,
    'next_episode': Ionicons.play_skip_forward_outline,
    'send_danmaku': Ionicons.send_outline,
  };

  // 修饰键文本映射
  final Map<HotKeyModifier, String> _modifierTexts = {
    HotKeyModifier.shift: 'Shift',
    HotKeyModifier.control: 'Ctrl',
    HotKeyModifier.alt: 'Alt',
    HotKeyModifier.meta: 'Meta',
  };

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  // 加载当前快捷键配置
  Future<void> _loadShortcuts() async {
    _shortcuts = Map.from(_hotkeyService.allShortcuts);
    setState(() {});
  }

  // 获取动作对应的图标
  IconData _getActionIcon(String action) {
    return _actionIcons[action] ?? Ionicons.key_outline;
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
    debugPrint('[ShortcutsSettingsPage] 更新快捷键: $action -> $shortcut');
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

    // 功能键 (F1-F24)
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
    if (key == PhysicalKeyboardKey.semicolon) return ';';
    if (key == PhysicalKeyboardKey.equal) return '=';
    if (key == PhysicalKeyboardKey.comma) return ',';
    if (key == PhysicalKeyboardKey.minus) return '-';
    if (key == PhysicalKeyboardKey.period) return '.';
    if (key == PhysicalKeyboardKey.slash) return '/';
    if (key == PhysicalKeyboardKey.backquote) return '`';
    if (key == PhysicalKeyboardKey.bracketLeft) return '[';
    if (key == PhysicalKeyboardKey.backslash) return '\\';
    if (key == PhysicalKeyboardKey.bracketRight) return ']';
    if (key == PhysicalKeyboardKey.quote) return '\'';

    // 小键盘数字键
    if (key == PhysicalKeyboardKey.numpad0) return 'Num 0';
    if (key == PhysicalKeyboardKey.numpad1) return 'Num 1';
    if (key == PhysicalKeyboardKey.numpad2) return 'Num 2';
    if (key == PhysicalKeyboardKey.numpad3) return 'Num 3';
    if (key == PhysicalKeyboardKey.numpad4) return 'Num 4';
    if (key == PhysicalKeyboardKey.numpad5) return 'Num 5';
    if (key == PhysicalKeyboardKey.numpad6) return 'Num 6';
    if (key == PhysicalKeyboardKey.numpad7) return 'Num 7';
    if (key == PhysicalKeyboardKey.numpad8) return 'Num 8';
    if (key == PhysicalKeyboardKey.numpad9) return 'Num 9';

    // 小键盘其他键
    if (key == PhysicalKeyboardKey.numpadDivide) return 'Num /';
    if (key == PhysicalKeyboardKey.numpadMultiply) return 'Num *';
    if (key == PhysicalKeyboardKey.numpadSubtract) return 'Num -';
    if (key == PhysicalKeyboardKey.numpadAdd) return 'Num +';
    if (key == PhysicalKeyboardKey.numpadEnter) return 'Num Enter';
    if (key == PhysicalKeyboardKey.numpadDecimal) return 'Num .';

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

    debugPrint(
        '[ShortcutsSettingsPage] 接收到键盘事件: ${event.physicalKey}, debugName: ${event.physicalKey.debugName}');

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
    debugPrint('[ShortcutsSettingsPage] 键位文本表示: $keyText');

    // 如果是无法识别的键，显示提示并返回
    if (keyText.contains('PhysicalKeyboard') || keyText.contains('#')) {
      MessageHelper.showMessage(
        context,
        '无法识别的键位: ${event.physicalKey}',
        isError: true,
        duration: const Duration(seconds: 2),
      );
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
      shortcut = '${modifiers.join('+')}+$keyText';
    } else {
      shortcut = keyText;
    }

    debugPrint('[ShortcutsSettingsPage] 生成的快捷键: $shortcut');

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
      BlurDialog.show(
        context: context,
        title: '快捷键冲突',
        content: '快捷键"$shortcut"已被"$conflictAction"使用，是否替换？',
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _stopRecording();
            },
            child: const Text('取消',
                locale: Locale("zh", "CN"),
                style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _updateShortcut(_recordingAction!, shortcut);
              _stopRecording();
            },
            child: const Text('替换',
                locale: Locale("zh", "CN"),
                style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    } else {
      // 无冲突，直接更新
      _updateShortcut(_recordingAction!, shortcut);
      _stopRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKey: _handleKeyPress,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _shortcuts == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  // 恢复默认按钮作为单独的一栏
                  SettingsItem.button(
                    title: "恢复默认快捷键",
                    subtitle: "将所有快捷键恢复为默认设置",
                    icon: Ionicons.refresh_outline,
                    trailingIcon: Ionicons.refresh_outline,
                    onTap: _resetToDefaults,
                  ),
                  const Divider(color: Colors.white12, height: 1),

                  // 快捷键列表
                  ..._actionLabels.keys.map((action) {
                    final label = _actionLabels[action]!;
                    final description = _actionDescriptions[action] ?? '';
                    final shortcut = _shortcuts![action] ?? '';
                    final isRecording = _recordingAction == action;

                    return Column(
                      children: [
                        SettingsItem.hotkey(
                          title: label,
                          subtitle: description,
                          icon: _getActionIcon(action),
                          hotkeyText: shortcut,
                          isRecording: isRecording,
                          onTap: () => _startRecording(action),
                        ),
                        const Divider(color: Colors.white12, height: 1),
                      ],
                    );
                  }),
                ],
              ),
      ),
    );
  }

  // 构建录制中的按钮
  Widget _buildRecordingButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '按下键位...',
            locale: Locale("zh", "CN"),
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  // 构建快捷键按钮，使用与BlurButton一致的样式
  Widget _buildShortcutButton(String shortcut, VoidCallback onPressed) {
    bool isHovered = false;

    return StatefulBuilder(builder: (context, setState) {
      return MouseRegion(
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isHovered
                    ? Colors.white.withOpacity(0.4)
                    : Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isHovered
                      ? Colors.white.withOpacity(0.7)
                      : Colors.white.withOpacity(0.25),
                  width: isHovered ? 1.0 : 0.5,
                ),
                boxShadow: isHovered
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.25),
                          blurRadius: 10,
                          spreadRadius: 1,
                        )
                      ]
                    : [],
              ),
              child: InkWell(
                onTap: onPressed,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    color: isHovered
                        ? Colors.white
                        : Colors.white.withOpacity(0.8),
                    fontSize: 14,
                    fontWeight: isHovered ? FontWeight.w500 : FontWeight.normal,
                  ),
                  child: Text(shortcut.isEmpty ? '点击设置' : shortcut),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
