import 'package:flutter/material.dart';
import 'dart:io';
import '../utils/keyboard_shortcuts.dart';
import '../widgets/blur_dropdown.dart';
import '../widgets/blur_dialog.dart';

class ShortcutsSettingsPage extends StatefulWidget {
  const ShortcutsSettingsPage({super.key});

  @override
  State<ShortcutsSettingsPage> createState() => _ShortcutsSettingsPageState();
}

class _ShortcutsSettingsPageState extends State<ShortcutsSettingsPage> {
  final Map<String, String> _actionLabels = {
    'play_pause': '播放/暂停',
    'fullscreen': '全屏',
    'rewind': '快退',
    'forward': '快进',
    'toggle_danmaku': '显示/隐藏弹幕',
    'volume_up': '增大音量',
    'volume_down': '减小音量',
  };

  final Map<String, List<String>> _availableShortcuts = {
    'play_pause': ['空格', 'P', 'K'],
    'fullscreen': ['Enter', 'F', 'S'],
    'rewind': ['←', 'J', '4'],
    'forward': ['→', 'L', '6'],
    'toggle_danmaku': ['D', 'T', 'B'],
    'volume_up': ['↑', '+', 'PageUp'],
    'volume_down': ['↓', '-', 'PageDown'],
  };

  final Map<String, GlobalKey> _dropdownKeys = {
    'play_pause': GlobalKey(),
    'fullscreen': GlobalKey(),
    'rewind': GlobalKey(),
    'forward': GlobalKey(),
    'toggle_danmaku': GlobalKey(),
    'volume_up': GlobalKey(),
    'volume_down': GlobalKey(),
  };

  Future<void> _showRestartDialog() async {
    final result = await BlurDialog.show(
      context: context,
      title: '需要重启',
      content: '快捷键设置已更改，需要重启应用才能生效。',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(true);
            exit(0);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView.builder(
        itemCount: _actionLabels.length,
        itemBuilder: (context, index) {
          final action = _actionLabels.keys.elementAt(index);
          final label = _actionLabels[action]!;
          final currentShortcut = KeyboardShortcuts.getShortcutText(action);
          final shortcuts = _availableShortcuts[action]!;

          return ListTile(
            title: Text(label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('当前快捷键: $currentShortcut',
                style: const TextStyle(color: Colors.white70)),
            trailing: BlurDropdown<String>(
              dropdownKey: _dropdownKeys[action]!,
              items: shortcuts.map((String shortcut) {
                return DropdownMenuItemData(
                  title: shortcut,
                  value: shortcut,
                  isSelected: currentShortcut == shortcut,
                );
              }).toList(),
              onItemSelected: (shortcut) async {
                await KeyboardShortcuts.setShortcut(action, shortcut);
                setState(() {});
                _showRestartDialog();
                            },
            ),
          );
        },
      ),
    );
  }
} 