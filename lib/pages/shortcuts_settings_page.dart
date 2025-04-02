import 'package:flutter/material.dart';
import '../utils/keyboard_shortcuts.dart';
import '../utils/theme_utils.dart';
import '../widgets/blur_dropdown.dart';

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
  };

  final Map<String, List<String>> _availableShortcuts = {
    'play_pause': ['空格', 'P', 'K'],
    'fullscreen': ['Enter', 'F', 'D'],
    'rewind': ['←', 'J', '4'],
    'forward': ['→', 'L', '6'],
  };

  final Map<String, GlobalKey> _dropdownKeys = {
    'play_pause': GlobalKey(),
    'fullscreen': GlobalKey(),
    'rewind': GlobalKey(),
    'forward': GlobalKey(),
  };

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
                if (shortcut != null) {
                  await KeyboardShortcuts.setShortcut(action, shortcut);
                  setState(() {});
                }
              },
            ),
          );
        },
      ),
    );
  }
} 