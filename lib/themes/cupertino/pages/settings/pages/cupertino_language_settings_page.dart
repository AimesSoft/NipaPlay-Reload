import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:provider/provider.dart';

class CupertinoLanguageSettingsPage extends StatelessWidget {
  const CupertinoLanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppLanguageProvider>();
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 64;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: context.l10n.languageSettingsTitle,
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
            children: [
              CupertinoSettingsGroupCard(
                margin: EdgeInsets.zero,
                backgroundColor: resolveSettingsSectionBackground(context),
                addDividers: true,
                dividerIndent: 56,
                children: [
                  _buildOptionTile(
                    context: context,
                    provider: provider,
                    mode: AppLanguageMode.auto,
                    title: context.l10n.languageAuto,
                  ),
                  _buildOptionTile(
                    context: context,
                    provider: provider,
                    mode: AppLanguageMode.simplifiedChinese,
                    title: context.l10n.languageSimplifiedChinese,
                  ),
                  _buildOptionTile(
                    context: context,
                    provider: provider,
                    mode: AppLanguageMode.traditionalChinese,
                    title: context.l10n.languageTraditionalChinese,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  context.l10n.languageSettingsSubtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: resolveSettingsSecondaryTextColor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required BuildContext context,
    required AppLanguageProvider provider,
    required AppLanguageMode mode,
    required String title,
  }) {
    final bool selected = provider.mode == mode;
    return CupertinoSettingsTile(
      leading: Icon(
        CupertinoIcons.globe,
        color: resolveSettingsIconColor(context),
      ),
      title: Text(title),
      trailing: selected
          ? Icon(
              CupertinoIcons.check_mark,
              color: resolveSettingsIconColor(context),
              size: 18,
            )
          : null,
      backgroundColor: resolveSettingsTileBackground(context),
      onTap: () => context.read<AppLanguageProvider>().setMode(mode),
    );
  }
}
