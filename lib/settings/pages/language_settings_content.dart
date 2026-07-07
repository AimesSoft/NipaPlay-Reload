import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:provider/provider.dart';

class LanguageSettingsContent extends StatelessWidget {
  const LanguageSettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppLanguageProvider>();

    return AdaptiveSettingsPage(
      title: context.l10n.languageSettingsTitle,
      children: [
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<AppLanguageMode>.dropdown(
              title: context.l10n.languageSettingsTitle,
              subtitle: context.l10n.languageSettingsSubtitle,
              icon: Ionicons.language_outline,
              phoneIcon: cupertino.CupertinoIcons.globe,
              items: [
                _item(
                  context,
                  provider,
                  AppLanguageMode.auto,
                  context.l10n.languageAuto,
                ),
                _item(
                  context,
                  provider,
                  AppLanguageMode.simplifiedChinese,
                  context.l10n.languageSimplifiedChinese,
                ),
                _item(
                  context,
                  provider,
                  AppLanguageMode.traditionalChinese,
                  context.l10n.languageTraditionalChinese,
                ),
                _item(
                  context,
                  provider,
                  AppLanguageMode.english,
                  context.l10n.languageEnglish,
                ),
              ],
              onChanged: context.read<AppLanguageProvider>().setMode,
            ),
          ],
        ),
      ],
    );
  }

  DropdownMenuItemData<AppLanguageMode> _item(
    BuildContext context,
    AppLanguageProvider provider,
    AppLanguageMode mode,
    String title,
  ) {
    return DropdownMenuItemData(
      title: title,
      value: mode,
      isSelected: provider.mode == mode,
    );
  }
}
