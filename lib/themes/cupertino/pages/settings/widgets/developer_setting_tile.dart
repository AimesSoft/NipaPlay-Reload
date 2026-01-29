import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_developer_options_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoDeveloperSettingTile extends StatelessWidget {
  const CupertinoDeveloperSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final Color iconColor = resolveSettingsIconColor(context);
    final Color tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(CupertinoIcons.command, color: iconColor),
      title: const Text('开发者选项'),
      subtitle: const Text('终端输出、依赖版本、构建信息'),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoDeveloperOptionsPage(),
          ),
        );
      },
    );
  }
}
