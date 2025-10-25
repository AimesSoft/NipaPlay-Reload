import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

import '../pages/cupertino_ui_theme_settings_page.dart';

class CupertinoThemeSettingTile extends StatelessWidget {
  const CupertinoThemeSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UIThemeProvider>(
      builder: (context, provider, child) {
        final UIThemeType currentTheme = provider.currentTheme;
        final UIThemeType displayTheme = (PlatformInfo.isIOS &&
                currentTheme == UIThemeType.fluentUI)
            ? (globals.isPhone ? UIThemeType.cupertino : UIThemeType.nipaplay)
            : currentTheme;
        final String subtitle =
            '当前：${provider.getThemeName(displayTheme)}';

        return AdaptiveListTile(
          leading: const Icon(CupertinoIcons.sparkles),
          title: const Text('主题（实验性）'),
          subtitle: Text(subtitle),
          trailing: Icon(
            PlatformInfo.isIOS
                ? CupertinoIcons.chevron_forward
                : CupertinoIcons.forward,
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemGrey2,
              context,
            ),
          ),
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
