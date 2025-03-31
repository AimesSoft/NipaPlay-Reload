// ThemeModePage.dart
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/utils/settings_storage.dart';

class ThemeModePage extends StatefulWidget {
  final ThemeNotifier themeNotifier;

  const ThemeModePage({super.key, required this.themeNotifier});

  @override
  // ignore: library_private_types_in_public_api
  _ThemeModePageState createState() => _ThemeModePageState();
}

class _ThemeModePageState extends State<ThemeModePage> {
  final GlobalKey _dropdownKey = GlobalKey();
  final GlobalKey _blurDropdownKey = GlobalKey();
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            ListTile(
              title: Text("主题模式", style: getTitleTextStyle(context)),
              trailing: BlurDropdown<ThemeMode>(
                dropdownKey: _dropdownKey,
                items: [
                  DropdownMenuItemData(
                    title: "日间模式",
                    value: ThemeMode.light,
                    isSelected:
                        widget.themeNotifier.themeMode == ThemeMode.light,
                  ),
                  DropdownMenuItemData(
                    title: "夜间模式",
                    value: ThemeMode.dark,
                    isSelected:
                        widget.themeNotifier.themeMode == ThemeMode.dark,
                  ),
                  DropdownMenuItemData(
                    title: "跟随系统",
                    value: ThemeMode.system,
                    isSelected:
                        widget.themeNotifier.themeMode == ThemeMode.system,
                  ),
                ],
                onItemSelected: (mode) {
                  setState(() {
                    widget.themeNotifier.themeMode = mode;
                    _saveThemeMode(mode);
                  });
                },
              ),
            ),
            ListTile(
              title: Text("毛玻璃效果", style: getTitleTextStyle(context)),
              trailing: BlurDropdown<int>(
                dropdownKey: _blurDropdownKey,
                items: [
                  DropdownMenuItemData(
                    title: "无",
                    value: 0,
                    isSelected: widget.themeNotifier.blurPower == 0,
                  ),
                  DropdownMenuItemData(
                    title: "轻微",
                    value: 5,
                    isSelected: widget.themeNotifier.blurPower == 5,
                  ),
                  DropdownMenuItemData(
                    title: "中等",
                    value: 15,
                    isSelected: widget.themeNotifier.blurPower == 15,
                  ),
                  DropdownMenuItemData(
                    title: "高",
                    value: 25,
                    isSelected: widget.themeNotifier.blurPower == 25,
                  ),
                  DropdownMenuItemData(
                    title: "超级",
                    value: 50,
                    isSelected: widget.themeNotifier.blurPower == 50,
                  ),
                  DropdownMenuItemData(
                    title: "梦幻",
                    value: 100,
                    isSelected: widget.themeNotifier.blurPower == 100,
                  ),
                ],
                onItemSelected: (blur) {
                  setState(() {
                    widget.themeNotifier.blurPower =
                        blur.toDouble(); // 将 blur 转换为 double
                    _saveBlurPower(blur.toDouble());
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    String modeString;
    switch (mode) {
      case ThemeMode.light:
        modeString = 'light';
        break;
      case ThemeMode.dark:
        modeString = 'dark';
        break;
      default:
        modeString = 'system';
    }
    await SettingsStorage.saveString('themeMode', modeString);
  }

  Future<void> _saveBlurPower(double blur) async {
    // 修改参数类型为 double
    await SettingsStorage.saveDouble('blurPower', blur); // 使用 saveDouble
    setState(() {
      blurPower = blur; // 更新全局 blurPower 变量
    });
  }
}
