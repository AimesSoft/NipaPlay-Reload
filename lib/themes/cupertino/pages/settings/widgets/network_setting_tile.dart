import 'package:flutter/cupertino.dart';

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
      title: const Text('网络设置'),
      subtitle: const Text('弹弹play 服务器及自定义地址'),
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
