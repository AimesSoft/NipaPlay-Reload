import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_player_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoPlayerSettingTile extends StatefulWidget {
  const CupertinoPlayerSettingTile({super.key});

  @override
  State<CupertinoPlayerSettingTile> createState() =>
      _CupertinoPlayerSettingTileState();
}

class _CupertinoPlayerSettingTileState
    extends State<CupertinoPlayerSettingTile> {
  String _kernelLabel(BuildContext context, PlayerKernelType type) {
    switch (type) {
      case PlayerKernelType.mdk:
        return context.l10n.playerKernelCurrentMdk;
      case PlayerKernelType.videoPlayer:
        return context.l10n.playerKernelCurrentVideoPlayer;
      case PlayerKernelType.mediaKit:
        return context.l10n.playerKernelCurrentLibmpv;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kernelName = _kernelLabel(context, PlayerFactory.getKernelType());
    final tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(
        CupertinoIcons.play_circle,
        color: resolveSettingsIconColor(context),
      ),
      title: Text(context.l10n.player),
      subtitle: Text(kernelName),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () async {
        await Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoPlayerSettingsPage(),
          ),
        );
        if (!mounted) return;
        setState(() {});
      },
    );
  }
}
