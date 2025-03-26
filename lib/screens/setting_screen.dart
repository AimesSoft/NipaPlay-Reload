import 'package:flutter/material.dart';
import 'package:nipaplay/screens/account_settings.dart';
import 'package:nipaplay/screens/background_settings.dart';
import 'package:nipaplay/screens/bar_settings.dart';
import 'package:nipaplay/screens/color_settings.dart';
import 'package:nipaplay/screens/theme_settings.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/theme_provider.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/page_ui.dart';
import 'package:nipaplay/services/settings_service.dart';
import 'package:nipaplay/utils/theme_helper.dart';
import 'package:provider/provider.dart';

class SettingScreen extends StatefulWidget {
  final SettingsService settingsService = SettingsService();

  SettingScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _SettingScreenState createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
  // 加载 sidebarBlurEffect，并检查是否为空或 null
  sidebarBlurEffect = await SettingsStorage.loadBool('sidebarBlurEffect');

  // 加载背景图片，并检查是否为空
  String? loadedBackImage = await SettingsStorage.loadString('backImage');
  if (loadedBackImage.isNotEmpty) {
    backImage = loadedBackImage;
  }

  // 加载背景图片编号
  backImageNumber = await SettingsStorage.loadInt('backImageNumber');

  // 加载基础颜色，并应用默认值
  baseLightColor = await SettingsStorage.loadString(
    "baseLightColor",
    defaultValue: computeLeftColorHex(Colors.grey),
  );

  // 加载 modeSwitch
  modeSwitch = await SettingsStorage.loadBool('modeSwitch');

  // 加载是否启用暗黑模式的值
  isDarkModeValue = await SettingsStorage.loadBool('isDarkModeValue');

  // 刷新 UI（确保 UI 更新只在 widget 被挂载时进行）
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

  // 根据 barPageNumber 显示对应的页面内容
  String _getPageContent() {
    switch (barPageNumber) {
      case 0:
        return playVideoTitle; // 显示播放视频页面
      case 1:
        return libraryTitle; // 显示媒体库页面
      case 2:
        return settingTitle; // 显示设置页面
      default:
        return settingTitle; // 默认显示播放视频页面
    }
  }

  // 获取 settingsWidgets 根据 barPageNumber 的值动态传入不同的内容
  List<Widget> _getSettingsWidgets() {
    switch (barPageNumber) {
      case 0: // 播放视频页面
        return [
          const SubOptionDivider(isLast: true),
          Center(
            child: Text(
              "这里什么都没有...",
              textAlign: TextAlign.center,
              style: getTitleTextStyle(context),
            ),
          ),
        ];
      case 1: // 媒体库页面
        return [
          const SubOptionDivider(isLast: true),
          Center(
            child: Text(
              "这里什么都没有...",
              textAlign: TextAlign.center,
              style: getTitleTextStyle(context),
            ),
          ),
        ];
      case 2: // 设置页面
        return [
          const SubOptionDivider(isLast: true),
          AccountSettings(settingsService: widget.settingsService),
          const SubOptionDivider(),
          BackgroundSettings(settingsService: widget.settingsService),
          const SubOptionDivider(),
          const ColorSettings(),
          const SubOptionDivider(),
          DarkSettings(settingsService: widget.settingsService),
          if (!isMobile) ...[
            const SubOptionDivider(),
            BarSettings(settingsService: widget.settingsService),
          ],
        ];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    getCurrentThemeMode(context, modeSwitch);
    return PageUI(
      settingTitle: _getPageContent(),
      settingsWidgets: _getSettingsWidgets(), // 动态传入控件列表
    );
  }
}
