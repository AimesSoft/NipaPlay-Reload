import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_danmaku_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoDanmakuSettingTile extends StatelessWidget {
  const CupertinoDanmakuSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final Color iconColor = resolveSettingsIconColor(context);
    final Color tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(
        CupertinoIcons.bubble_left_bubble_right,
        color: iconColor,
      ),
      title: const Text('弹幕'),
      subtitle: const Text('渲染、防剧透与匹配'),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoDanmakuSettingsPage(),
          ),
        );
      },
    );
  }
}
