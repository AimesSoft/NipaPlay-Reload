import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

class ExternalPlayerSettingsPage extends StatelessWidget {
  const ExternalPlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool externalSupported = globals.isDesktop;

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Ionicons.open_outline,
                        color: colorScheme.onSurface, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '外部调用',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  externalSupported
                      ? '启用后，所有播放操作将通过外部播放器打开。'
                      : '仅桌面端支持外部播放器调用。',
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Divider(
                  color: colorScheme.onSurface.withOpacity(0.12),
                  height: 1,
                ),
                Consumer<SettingsProvider>(
                  builder: (context, settingsProvider, child) {
                    return SettingsItem.toggle(
                      title: '启用外部播放器',
                      subtitle: externalSupported
                          ? '开启后将使用外部播放器播放视频'
                          : '仅桌面端支持',
                      icon: Ionicons.play_outline,
                      enabled: externalSupported,
                      value: settingsProvider.useExternalPlayer,
                      onChanged: (bool value) async {
                        if (!externalSupported) return;
                        if (value) {
                          if (settingsProvider.externalPlayerPath
                              .trim()
                              .isEmpty) {
                            final picked = await FilePickerService()
                                .pickExternalPlayerExecutable();
                            if (picked == null || picked.trim().isEmpty) {
                              if (context.mounted) {
                                BlurSnackBar.show(context, '已取消选择外部播放器');
                              }
                              await settingsProvider.setUseExternalPlayer(false);
                              return;
                            }
                            await settingsProvider.setExternalPlayerPath(picked);
                          }
                          await settingsProvider.setUseExternalPlayer(true);
                          if (context.mounted) {
                            BlurSnackBar.show(context, '已启用外部播放器');
                          }
                        } else {
                          await settingsProvider.setUseExternalPlayer(false);
                          if (context.mounted) {
                            BlurSnackBar.show(context, '已关闭外部播放器');
                          }
                        }
                      },
                    );
                  },
                ),
                Divider(
                  color: colorScheme.onSurface.withOpacity(0.12),
                  height: 1,
                ),
                Consumer<SettingsProvider>(
                  builder: (context, settingsProvider, child) {
                    final path = settingsProvider.externalPlayerPath.trim();
                    final subtitle = !externalSupported
                        ? '仅桌面端支持'
                        : (path.isEmpty ? '未选择外部播放器' : path);
                    return SettingsItem.button(
                      title: '选择外部播放器',
                      subtitle: subtitle,
                      icon: Ionicons.folder_outline,
                      enabled: externalSupported,
                      onTap: () async {
                        if (!externalSupported) return;
                        final picked = await FilePickerService()
                            .pickExternalPlayerExecutable();
                        if (picked == null || picked.trim().isEmpty) {
                          if (context.mounted) {
                            BlurSnackBar.show(context, '已取消选择外部播放器');
                          }
                          return;
                        }
                        await settingsProvider.setExternalPlayerPath(picked);
                        if (context.mounted) {
                          BlurSnackBar.show(context, '已更新外部播放器');
                        }
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
