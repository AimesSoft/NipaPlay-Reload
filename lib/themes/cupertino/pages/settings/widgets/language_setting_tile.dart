import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_language_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:provider/provider.dart';

class CupertinoLanguageSettingTile extends StatelessWidget {
  const CupertinoLanguageSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppLanguageProvider>();
    final tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(
        CupertinoIcons.globe,
        color: resolveSettingsIconColor(context),
      ),
      title: Text(context.l10n.language),
      subtitle: Text(
        context.l10n.currentLanguage(_modeLabel(context, provider.mode)),
      ),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoLanguageSettingsPage(),
          ),
        );
      },
    );
  }

  String _modeLabel(BuildContext context, AppLanguageMode mode) {
    switch (mode) {
      case AppLanguageMode.simplifiedChinese:
        return context.l10n.languageSimplifiedChinese;
      case AppLanguageMode.traditionalChinese:
        return context.l10n.languageTraditionalChinese;
      case AppLanguageMode.auto:
        return context.l10n.languageAuto;
    }
  }
}
