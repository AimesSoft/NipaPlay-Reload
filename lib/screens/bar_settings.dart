// ignore_for_file: unnecessary_null_comparison

import 'package:flutter/material.dart';
import 'package:nipaplay/services/settings_service.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/theme_provider.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/rounded_container.dart';
import 'package:nipaplay/widgets/sidebar_toggle.dart';
import 'package:provider/provider.dart';

class BarSettings extends StatefulWidget {
  final SettingsService settingsService;

  const BarSettings({super.key, required this.settingsService});

  @override
  State<BarSettings> createState() => _BarSettingsState();
}

class _BarSettingsState extends State<BarSettings> {
  @override
  void initState() {
    super.initState();
    _loadSettings(); // 加载保存的设置
  }

  // 从存储中加载设置
  Future<void> _loadSettings() async {
    // 加载 sidebarBlurEffect 并检查是否为空或 null
    bool? loadedSidebarBlurEffect =
        await SettingsStorage.loadBool('sidebarBlurEffect');
    if (loadedSidebarBlurEffect != null) {
      sidebarBlurEffect = loadedSidebarBlurEffect;
    }

    if (mounted) {
      // 添加 mounted 检查
      setState(() {}); // 确保 UI 更新
    }
  }

  // 保存设置
  Future<void> _saveSettings() async {
    await SettingsStorage.saveBool('sidebarBlurEffect', sidebarBlurEffect);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "边栏设置",
          style: getTitleTextStyle(context),
        ),
        RoundedContainer(
          child: SidebarToggle(
            title: '光晕动画',
            value: !sidebarBlurEffect,
            onChanged: (bool value) {
              setState(() {
                sidebarBlurEffect = !value;
                _saveSettings(); // 你的保存设置逻辑
                themeProvider.updateDraw(); // 更新主题
              });
            },
          ),
        ),
      ],
    );
  }
}
