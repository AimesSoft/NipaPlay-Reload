import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_external_player_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

class CupertinoExternalPlayerSettingTile extends StatelessWidget {
  const CupertinoExternalPlayerSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final tileColor = resolveSettingsTileBackground(context);
    final bool externalSupported = globals.isDesktop;

    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final String subtitle = externalSupported
            ? (settingsProvider.useExternalPlayer
                ? context.l10n.externalPlayerEnabled
                : context.l10n.externalPlayerDisabled)
            : context.l10n.desktopOnlySupported;

        return CupertinoSettingsTile(
          leading: Icon(
            CupertinoIcons.square_arrow_up,
            color: resolveSettingsIconColor(context),
          ),
          title: Text(context.l10n.externalCall),
          subtitle: Text(subtitle),
          backgroundColor: tileColor,
          showChevron: true,
          onTap: () async {
            await Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (_) => const CupertinoExternalPlayerSettingsPage(),
              ),
            );
          },
        );
      },
    );
  }
}
