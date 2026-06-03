import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppLanguageProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SettingsCard(
          child: Column(
            children: [
              _buildOption(
                context: context,
                provider: provider,
                mode: AppLanguageMode.auto,
                title: context.l10n.languageAuto,
              ),
              Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1,
              ),
              _buildOption(
                context: context,
                provider: provider,
                mode: AppLanguageMode.simplifiedChinese,
                title: context.l10n.languageSimplifiedChinese,
              ),
              Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1,
              ),
              _buildOption(
                context: context,
                provider: provider,
                mode: AppLanguageMode.traditionalChinese,
                title: context.l10n.languageTraditionalChinese,
              ),
              Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1,
              ),
              _buildOption(
                context: context,
                provider: provider,
                mode: AppLanguageMode.english,
                title: context.l10n.languageEnglish,
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            context.l10n.languageSettingsSubtitle,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required AppLanguageProvider provider,
    required AppLanguageMode mode,
    required String title,
  }) {
    final bool selected = provider.mode == mode;
    return ListTile(
      dense: false,
      leading: Icon(Ionicons.language_outline),
      title: Text(title),
      trailing: selected
          ? Icon(
              Icons.check_rounded,
              color: AppAccentColors.current,
            )
          : null,
      onTap: () => context.read<AppLanguageProvider>().setMode(mode),
    );
  }
}
