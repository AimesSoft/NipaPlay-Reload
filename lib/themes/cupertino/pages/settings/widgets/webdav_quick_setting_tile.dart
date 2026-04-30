import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';

import '../pages/webdav_quick_settings_page.dart' show CupertinoWebDAVQuickSettingsPage;

class CupertinoWebDAVQuickSettingTile extends StatelessWidget {
  const CupertinoWebDAVQuickSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final Color iconColor = resolveSettingsIconColor(context);
    final Color backgroundColor = resolveSettingsTileBackground(context);

    return Consumer<WebDAVQuickAccessProvider>(
      builder: (context, provider, _) {
        final subtitle = _buildSubtitle(context, provider);

        return CupertinoSettingsTile(
          leading: Icon(CupertinoIcons.cloud, color: iconColor),
          title: const Text('WebDAV快捷'),
          subtitle: Text(subtitle),
          backgroundColor: backgroundColor,
          showChevron: true,
          onTap: () {
            Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (_) => const CupertinoWebDAVQuickSettingsPage(),
              ),
            );
          },
        );
      },
    );
  }

  String _buildSubtitle(BuildContext context, WebDAVQuickAccessProvider provider) {
    if (!provider.showWebDAVTab) {
      return '未启用';
    }

    final connections = WebDAVService.instance.connections;
    if (connections.isEmpty) {
      return '无服务器配置';
    }

    if (provider.defaultServerName != null && provider.defaultServerName!.isNotEmpty) {
      return provider.defaultServerName!;
    }

    return '已启用';
  }
}
