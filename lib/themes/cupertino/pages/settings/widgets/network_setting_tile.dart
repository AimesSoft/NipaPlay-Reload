import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';

import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_network_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoNetworkSettingTile extends StatelessWidget {
  const CupertinoNetworkSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final Color iconColor = resolveSettingsIconColor(context);
    final Color tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(CupertinoIcons.globe, color: iconColor),
      title: Text(context.l10n.networkSettings),
      subtitle: Text(context.l10n.networkSettingsSubtitle),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoNetworkSettingsPage(),
          ),
        );
      },
    );
  }
}
