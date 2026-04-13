import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_appearance_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

class CupertinoAppearanceSettingTile extends StatelessWidget {
  const CupertinoAppearanceSettingTile({super.key});

  String _modeLabel(BuildContext context, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return context.l10n.lightMode;
      case ThemeMode.dark:
        return context.l10n.darkMode;
      case ThemeMode.system:
        return context.l10n.followSystem;
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
      title: Text(context.l10n.appearance),
      subtitle: Text(_modeLabel(context, themeMode)),
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
