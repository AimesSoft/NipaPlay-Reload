import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:provider/provider.dart';

import 'package:nipaplay/utils/theme_notifier.dart';
import '../widgets/appearance_preview_card.dart';

class CupertinoAppearanceSettingsPage extends StatefulWidget {
  const CupertinoAppearanceSettingsPage({super.key});

  @override
  State<CupertinoAppearanceSettingsPage> createState() =>
      _CupertinoAppearanceSettingsPageState();
}

class _CupertinoAppearanceSettingsPageState
    extends State<CupertinoAppearanceSettingsPage> {
  late ThemeMode _currentMode;

  @override
  void initState() {
    super.initState();
    final notifier = Provider.of<ThemeNotifier>(context, listen: false);
    _currentMode = notifier.themeMode;
  }

  void _updateThemeMode(ThemeMode mode) {
    if (_currentMode == mode) return;
    setState(() {
      _currentMode = mode;
    });
    Provider.of<ThemeNotifier>(context, listen: false).themeMode = mode;
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 48;

    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(
        title: '外观',
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, topPadding, 20, 32),
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            children: [
              AdaptiveFormSection.insetGrouped(
                children: [
                  _buildThemeOptionTile(
                    mode: ThemeMode.light,
                    title: '浅色模式',
                    subtitle: '保持明亮的界面与对比度。',
                  ),
                  _buildThemeOptionTile(
                    mode: ThemeMode.dark,
                    title: '深色模式',
                    subtitle: '降低亮度，保护视力并节省电量。',
                  ),
                  _buildThemeOptionTile(
                    mode: ThemeMode.system,
                    title: '跟随系统',
                    subtitle: '自动根据系统设置切换外观。',
                  ),
                ],
              ),
              const SizedBox(height: 28),
              CupertinoAppearancePreviewCard(mode: _currentMode),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOptionTile({
    required ThemeMode mode,
    required String title,
    required String subtitle,
  }) {
    return AdaptiveListTile(
      leading: Icon(
        mode == ThemeMode.dark
            ? CupertinoIcons.moon_fill
            : (mode == ThemeMode.light
                ? CupertinoIcons.sun_max_fill
                : CupertinoIcons.circle_lefthalf_fill),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: AdaptiveRadio<ThemeMode>(
        value: mode,
        groupValue: _currentMode,
        onChanged: (ThemeMode? value) {
          if (value != null) {
            _updateThemeMode(value);
          }
        },
      ),
      onTap: () => _updateThemeMode(mode),
    );
  }
}
