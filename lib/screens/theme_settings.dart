// ignore_for_file: unnecessary_null_comparison

import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_helper.dart';
import 'package:nipaplay/utils/theme_provider.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/rounded_container.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/services/settings_service.dart';
import 'package:nipaplay/widgets/rounded_button.dart';
import 'package:nipaplay/utils/settings_storage.dart';

class DarkSettings extends StatefulWidget {
  final SettingsService settingsService;

  const DarkSettings({super.key, required this.settingsService});

  @override
  // ignore: library_private_types_in_public_api
  _DarkSettingsState createState() => _DarkSettingsState();
}

class _DarkSettingsState extends State<DarkSettings> {
  @override
  void initState() {
    super.initState();
    _loadSettings(); // 加载保存的设置
  }

  // 从存储中加载设置
  Future<void> _loadSettings() async {
    // 加载 modeSwitch 并检查是否为空或 null
    bool? loadedModeSwitch = await SettingsStorage.loadBool('modeSwitch');
    if (loadedModeSwitch != null) {
      modeSwitch = loadedModeSwitch;
    }

    // 加载 isDarkModeValue 并检查是否为空或 null
    bool? loadedIsDarkModeValue =
        await SettingsStorage.loadBool('isDarkModeValue');
    if (loadedIsDarkModeValue != null) {
      isDarkModeValue = loadedIsDarkModeValue;
    }

    // 刷新 UI
    if (mounted) {
      setState(() {});
    }

    // 根据加载的设置应用主题
    _applySettings();
  }

  // 应用加载的设置
  void _applySettings() {
    final themeProvider = context.read<ThemeProvider>();
    if (!modeSwitch) {
      bool isDarkModeAuto = isDarkMode(context);
      themeProvider.toggleDarkMode(isDarkModeAuto ? 'night' : 'day', context);
    } else {
      themeProvider.toggleDarkMode(isDarkModeValue ? 'night' : 'day', context);
    }
  }

  // 保存设置
  Future<void> _saveSettings() async {
    await SettingsStorage.saveBool('modeSwitch', modeSwitch);
    await SettingsStorage.saveBool('isDarkModeValue', isDarkModeValue);
  }

  @override
  Widget build(BuildContext context) {
    isDarkModeValue = getCurrentThemeMode(context, modeSwitch);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "明暗设置",
          style: getTitleTextStyle(context),
        ),
        RoundedContainer(
          // 使用 RoundedContainer 包裹按钮行
          child: Row(
            children: [
              // 日间模式按钮
              RoundedButton(
                text: "日间模式",
                isSelected: modeSwitch == true && isDarkModeValue == false,
                onPressed: () {
                  setState(() {
                    context
                        .read<ThemeProvider>()
                        .toggleDarkMode('day', context);
                    modeSwitch = true;
                    isDarkModeValue = false;
                    _saveSettings();
                  });
                },
              ),
              const SizedBox(width: 10),

              // 夜间模式按钮
              RoundedButton(
                text: "夜间模式",
                isSelected: modeSwitch == true && isDarkModeValue == true,
                onPressed: () {
                  setState(() {
                    context
                        .read<ThemeProvider>()
                        .toggleDarkMode('night', context);
                    modeSwitch = true;
                    isDarkModeValue = true;
                    _saveSettings();
                  });
                },
              ),
              const SizedBox(width: 10),

              // 跟随系统按钮
              RoundedButton(
                text: "跟随系统",
                isSelected: modeSwitch == false,
                onPressed: () {
                  setState(() {
                    modeSwitch = false;
                    bool isDarkModeAuto = isDarkMode(context);
                    context.read<ThemeProvider>().toggleDarkMode(
                        isDarkModeAuto ? 'night' : 'day', context);
                    _saveSettings();
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
