import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_storage_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoStorageSettingTile extends StatelessWidget {
  const CupertinoStorageSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final Color iconColor = resolveSettingsIconColor(context);
    final Color tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(CupertinoIcons.archivebox, color: iconColor),
      title: const Text('存储'),
      subtitle: const Text('管理弹幕缓存与清理策略'),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoStorageSettingsPage(),
          ),
        );
      },
    );
  }
}
