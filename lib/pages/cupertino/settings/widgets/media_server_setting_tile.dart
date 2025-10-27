import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

import '../cupertino_media_server_settings_page.dart';

class CupertinoMediaServerSettingTile extends StatelessWidget {
  const CupertinoMediaServerSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final Color iconColor = resolveSettingsIconColor(context);
    final Color primaryTextColor = resolveSettingsPrimaryTextColor(context);
    final Color secondaryTextColor = resolveSettingsSecondaryTextColor(context);
    final Color backgroundColor = resolveSettingsTileBackground(context);

    return Consumer2<JellyfinProvider, EmbyProvider>(
      builder: (context, jellyfinProvider, embyProvider, _) {
        final subtitle = _buildSubtitle(
          jellyfinProvider,
          embyProvider,
        );

        return AdaptiveListTile(
          leading: Icon(CupertinoIcons.cloud, color: iconColor),
          title: Text('网络媒体库', style: TextStyle(color: primaryTextColor)),
          subtitle: Text(subtitle, style: TextStyle(color: secondaryTextColor)),
          backgroundColor: backgroundColor,
          trailing: Icon(
            PlatformInfo.isIOS
                ? CupertinoIcons.chevron_forward
                : CupertinoIcons.forward,
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemGrey2,
              context,
            ),
          ),
          onTap: () {
            Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (_) => const CupertinoMediaServerSettingsPage(),
              ),
            );
          },
        );
      },
    );
  }

  String _buildSubtitle(
    JellyfinProvider jellyfinProvider,
    EmbyProvider embyProvider,
  ) {
    final bool jellyfinConnected = jellyfinProvider.isConnected;
    final bool embyConnected = embyProvider.isConnected;

    if (!jellyfinConnected && !embyConnected) {
      return '尚未连接任何服务器';
    }

    final List<String> segments = [];

    if (jellyfinConnected) {
      segments.add(
        'Jellyfin · ${_resolveSummary(jellyfinProvider.availableLibraries, jellyfinProvider.selectedLibraryIds)}',
      );
    }

    if (embyConnected) {
      segments.add(
        'Emby · ${_resolveSummary(embyProvider.availableLibraries, embyProvider.selectedLibraryIds)}',
      );
    }

    return segments.join('  |  ');
  }

  String _resolveSummary<T>(
    List<T> libraries,
    Iterable<String> selectedIds,
  ) {
    if (selectedIds.isEmpty) {
      return '未选择媒体库';
    }

    final Map<String, String> nameMap = {
      for (final library in libraries)
        if (library is JellyfinLibrary)
          library.id: library.name
        else if (library is EmbyLibrary)
          library.id: library.name
    };

    final List<String> names = [];
    for (final id in selectedIds) {
      final name = nameMap[id];
      if (name != null && name.isNotEmpty) {
        names.add(name);
      }
    }

    if (names.isEmpty) {
      return '未匹配到媒体库';
    }

    if (names.length == 1) {
      return names.first;
    }

    return '${names.first} 等 ${names.length} 个';
  }
}
