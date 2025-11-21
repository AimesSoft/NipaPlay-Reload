import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_appearance_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

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

    final tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(
        CupertinoIcons.paintbrush,
        color: resolveSettingsIconColor(context),
      ),
      title: const Text('外观'),
      subtitle: Text(_modeLabel(themeMode)),
      backgroundColor: tileColor,
      showChevron: true,
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
