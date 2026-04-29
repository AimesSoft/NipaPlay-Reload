import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

import '../widgets/labs_setting_tile.dart';

class CupertinoSettingsLabsSection extends StatelessWidget {
  const CupertinoSettingsLabsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle.copyWith(
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
          child: Text('实验室', style: textStyle),
        ),
        const SizedBox(height: 8),
        CupertinoSettingsGroupCard(
          addDividers: true,
          backgroundColor: resolveSettingsSectionBackground(context),
          children: const [
            CupertinoLabsSettingTile(),
          ],
        ),
      ],
    );
  }
}
