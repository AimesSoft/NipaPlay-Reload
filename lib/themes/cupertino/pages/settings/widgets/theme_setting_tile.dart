import 'package:flutter/cupertino.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_ui_theme_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:provider/provider.dart';

class CupertinoThemeSettingTile extends StatelessWidget {
  const CupertinoThemeSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UIThemeProvider>(
      builder: (context, provider, child) {
        final subtitle = '当前：${provider.currentThemeDescriptor.displayName}';

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
