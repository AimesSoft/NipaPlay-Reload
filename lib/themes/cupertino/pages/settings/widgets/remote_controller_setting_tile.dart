import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_remote_controller_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoRemoteControllerSettingTile extends StatelessWidget {
  const CupertinoRemoteControllerSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final iconColor = resolveSettingsIconColor(context);
    final tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(CupertinoIcons.dot_radiowaves_left_right, color: iconColor),
      title: const Text('远程访问'),
      subtitle: const Text('本机被控端、共享媒体库与局域网遥控器'),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoRemoteControllerSettingsPage(),
          ),
        );
      },
    );
  }
}
