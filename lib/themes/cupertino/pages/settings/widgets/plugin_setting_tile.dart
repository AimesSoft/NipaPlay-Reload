import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_plugin_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoPluginSettingTile extends StatelessWidget {
  const CupertinoPluginSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final iconColor = resolveSettingsIconColor(context);
    final tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(CupertinoIcons.cube_box, color: iconColor),
      title: const Text('插件'),
      subtitle: const Text('管理 JS 插件并配置启用状态'),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoPluginSettingsPage(),
          ),
        );
      },
    );
  }
}
