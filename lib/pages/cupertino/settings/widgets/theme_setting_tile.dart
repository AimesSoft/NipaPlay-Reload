import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

import '../pages/cupertino_ui_theme_settings_page.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/widgets/cupertino/cupertino_settings_tile.dart';

class CupertinoThemeSettingTile extends StatelessWidget {
  const CupertinoThemeSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UIThemeProvider>(
      builder: (context, provider, child) {
        final UIThemeType currentTheme = provider.currentTheme;
        final bool isPhone = globals.isPhone;
        final UIThemeType displayTheme =
            (isPhone && currentTheme == UIThemeType.fluentUI)
                ? UIThemeType.cupertino
                : currentTheme;
        final String subtitle = '当前：${provider.getThemeName(displayTheme)}';

        final tileColor = resolveSettingsTileBackground(context);

        return CupertinoSettingsTile(
          leading: Icon(
            CupertinoIcons.sparkles,
            color: resolveSettingsIconColor(context),
          ),
          title: const Text('主题（实验性）'),
          subtitle: Text(subtitle),
          backgroundColor: tileColor,
          showChevron: true,
          onTap: () {
            Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (_) => const CupertinoUIThemeSettingsPage(),
              ),
            );
          },
        );
      },
    );
  }
}
