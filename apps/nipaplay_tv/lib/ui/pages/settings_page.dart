import 'package:flutter/material.dart';
import 'package:nipaplay_core/constants/settings_keys.dart';
import 'package:nipaplay_core/utils/settings_storage.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import '../focusable_card.dart';

/// 设置页：开关项经 core 的 SettingsStorage 持久化（SharedPreferences）。
/// 展示"TV 版 UI + core 存储契约"的接线；阶段四扩充为完整 TV 设置瓦片。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _toggles = <String, bool>{};

  static const _items = [
    ('tv.settings.hardwareDecode', '硬件解码（阶段四接 NipaPlayer）'),
    ('tv.settings.danmaku', '弹幕（阶段四接引擎渲染）'),
    ('tv.settings.autoPlayNext', '自动连播'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final map = <String, bool>{};
    for (final item in _items) {
      map[item.$1] = await SettingsStorage.loadBool(item.$1, defaultValue: true);
    }
    if (mounted) setState(() => _toggles.addAll(map));
  }

  Future<void> _toggle(String key, bool value) async {
    await SettingsStorage.saveBool(key, value);
    if (mounted) setState(() => _toggles[key] = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tabSettings,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(l10n.settingsBasicSection,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Colors.white38)),
          const SizedBox(height: 16),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FocusableCard(
                onActivate: () =>
                    _toggle(item.$1, !(_toggles[item.$1] ?? true)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(item.$2,
                          style: Theme.of(context).textTheme.bodyLarge),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: _toggles[item.$1] ?? true,
                      onChanged: (v) => _toggle(item.$1, v),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('存储键空间示例: ${SettingsKeys.appLanguageMode}（core/constants/settings_keys.dart）',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white24)),
        ],
      ),
    );
  }
}
