import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/l10n/l10n.dart';

import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';

class CupertinoExternalPlayerSettingsPage extends StatelessWidget {
  const CupertinoExternalPlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 64;
    final bool externalSupported = globals.isDesktop;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: context.l10n.externalCall,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  externalSupported
                      ? context.l10n.externalPlayerIntroDesktop
                      : context.l10n.externalPlayerIntroUnsupported,
                  style: TextStyle(
                    fontSize: 13,
                    color: resolveSettingsSecondaryTextColor(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildExternalSettingsCard(context, externalSupported),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExternalSettingsCard(
      BuildContext context, bool externalSupported) {
    final Color sectionColor = resolveSettingsSectionBackground(context);
    final Color tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsGroupCard(
      margin: EdgeInsets.zero,
      backgroundColor: sectionColor,
      addDividers: true,
      dividerIndent: 16,
      children: [
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            Future<void> toggleExternal(bool value) async {
              if (!externalSupported) {
                return;
              }
              final l10n = context.l10n;
              if (value) {
                if (settingsProvider.externalPlayerPath.trim().isEmpty) {
                  final picked =
                      await FilePickerService().pickExternalPlayerExecutable();
                  if (picked == null || picked.trim().isEmpty) {
                    if (!context.mounted) return;
                    AdaptiveSnackBar.show(
                      context,
                      message: l10n.externalPlayerSelectionCanceled,
                      type: AdaptiveSnackBarType.info,
                    );
                    await settingsProvider.setUseExternalPlayer(false);
                    return;
                  }
                  await settingsProvider.setExternalPlayerPath(picked);
                }
                await settingsProvider.setUseExternalPlayer(true);
                if (!context.mounted) return;
                AdaptiveSnackBar.show(
                  context,
                  message: l10n.externalPlayerEnabled,
                  type: AdaptiveSnackBarType.success,
                );
              } else {
                await settingsProvider.setUseExternalPlayer(false);
                if (!context.mounted) return;
                AdaptiveSnackBar.show(
                  context,
                  message: l10n.externalPlayerDisabled,
                  type: AdaptiveSnackBarType.success,
                );
              }
            }

            return CupertinoSettingsTile(
              leading: Icon(
                CupertinoIcons.square_arrow_up,
                color: resolveSettingsIconColor(context),
              ),
              title: Text(context.l10n.externalPlayerEnableTitle),
              subtitle: Text(externalSupported
                  ? context.l10n.externalPlayerEnableSubtitle
                  : context.l10n.desktopOnlySupported),
              trailing: AdaptiveSwitch(
                value: settingsProvider.useExternalPlayer,
                onChanged: externalSupported ? toggleExternal : null,
              ),
              onTap: externalSupported
                  ? () => toggleExternal(!settingsProvider.useExternalPlayer)
                  : null,
              backgroundColor: tileColor,
            );
          },
        ),
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            final path = settingsProvider.externalPlayerPath.trim();
            final subtitle = !externalSupported
                ? context.l10n.desktopOnlySupported
                : (path.isEmpty
                    ? context.l10n.externalPlayerNotSelected
                    : path);
            return CupertinoSettingsTile(
              leading: Icon(
                CupertinoIcons.folder,
                color: resolveSettingsIconColor(context),
              ),
              title: Text(context.l10n.externalPlayerSelectTitle),
              subtitle: Text(subtitle),
              showChevron: true,
              onTap: externalSupported
                  ? () async {
                      final l10n = context.l10n;
                      final picked = await FilePickerService()
                          .pickExternalPlayerExecutable();
                      if (picked == null || picked.trim().isEmpty) {
                        if (!context.mounted) return;
                        AdaptiveSnackBar.show(
                          context,
                          message: l10n.externalPlayerSelectionCanceled,
                          type: AdaptiveSnackBarType.info,
                        );
                        return;
                      }
                      await settingsProvider.setExternalPlayerPath(picked);
                      if (!context.mounted) return;
                      AdaptiveSnackBar.show(
                        context,
                        message: l10n.externalPlayerUpdated,
                        type: AdaptiveSnackBarType.success,
                      );
                    }
                  : null,
              backgroundColor: tileColor,
            );
          },
        ),
      ],
    );
  }
}
