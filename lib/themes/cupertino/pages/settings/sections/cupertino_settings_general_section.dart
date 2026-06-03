import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/plugins/plugin_service.dart';

import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:provider/provider.dart';

import '../widgets/appearance_setting_tile.dart';
import '../widgets/language_setting_tile.dart';
import '../widgets/player_setting_tile.dart';
import '../widgets/danmaku_setting_tile.dart';
import '../widgets/external_player_setting_tile.dart';
import '../widgets/network_setting_tile.dart';
import '../widgets/media_server_setting_tile.dart';
import '../widgets/remote_controller_setting_tile.dart';
import '../widgets/developer_setting_tile.dart';
import '../widgets/storage_setting_tile.dart';
import '../widgets/update_check_setting_tile.dart';
import '../widgets/plugin_setting_tile.dart';
import '../widgets/downloader_setting_tile.dart';

class CupertinoSettingsGeneralSection extends StatelessWidget {
  const CupertinoSettingsGeneralSection({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<PluginService>();
    final showDownloaderSettings = globals.isDownloaderSupportedPlatform;
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
          child: Text(context.l10n.settingsBasicSection, style: textStyle),
        ),
        const SizedBox(height: 8),
        CupertinoSettingsGroupCard(
          addDividers: true,
          backgroundColor: resolveSettingsSectionBackground(context),
          children: [
            const CupertinoAppearanceSettingTile(),
            const CupertinoLanguageSettingTile(),
            const CupertinoUpdateCheckSettingTile(),
            const CupertinoPlayerSettingTile(),
            const CupertinoDanmakuSettingTile(),
            const CupertinoExternalPlayerSettingTile(),
            const CupertinoNetworkSettingTile(),
            const CupertinoRemoteControllerSettingTile(),
            const CupertinoStorageSettingTile(),
            if (showDownloaderSettings) const CupertinoDownloaderSettingTile(),
            const CupertinoMediaServerSettingTile(),
            const CupertinoPluginSettingTile(),
            const CupertinoDeveloperSettingTile(),
          ],
        ),
      ],
    );
  }
}
