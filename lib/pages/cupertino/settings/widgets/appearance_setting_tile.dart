import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons, ThemeMode;
import 'package:provider/provider.dart';

import 'package:nipaplay/utils/theme_notifier.dart';
import '../pages/cupertino_appearance_settings_page.dart';

class CupertinoAppearanceSettingTile extends StatelessWidget {
  const CupertinoAppearanceSettingTile({super.key});

  String _modeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色模式';
      case ThemeMode.dark:
        return '深色模式';
      case ThemeMode.system:
      default:
        return '跟随系统';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeNotifier>().themeMode;

    return AdaptiveListTile(
      leading: const Icon(CupertinoIcons.paintbrush),
      title: const Text('外观'),
      subtitle: Text(_modeLabel(themeMode)),
      trailing: Icon(
        PlatformInfo.isIOS ? CupertinoIcons.chevron_forward : Icons.chevron_right,
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGrey2,
          context,
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoAppearanceSettingsPage(),
          ),
        );
      },
    );
  }
}
