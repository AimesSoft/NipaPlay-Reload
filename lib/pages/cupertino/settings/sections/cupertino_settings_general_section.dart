import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

import '../widgets/appearance_setting_tile.dart';
import '../widgets/theme_setting_tile.dart';
import '../widgets/player_setting_tile.dart';

class CupertinoSettingsGeneralSection extends StatelessWidget {
  const CupertinoSettingsGeneralSection({super.key});

  @override
  Widget build(BuildContext context) {
    final textStyle = CupertinoTheme.of(context)
        .textTheme
        .textStyle
        .copyWith(
          fontSize: 13,
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGrey,
            context,
          ),
          letterSpacing: 0.2,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('基础设置', style: textStyle),
        ),
        const SizedBox(height: 8),
        AdaptiveFormSection.insetGrouped(
          backgroundColor: CupertinoDynamicColor.resolve(
            const CupertinoDynamicColor.withBrightness(
              color: CupertinoColors.white,
              darkColor: CupertinoColors.darkBackgroundGray,
            ),
            context,
          ),
          children: [
            CupertinoAppearanceSettingTile(),
            CupertinoThemeSettingTile(),
            CupertinoPlayerSettingTile(),
          ],
        ),
      ],
    );
  }
}
