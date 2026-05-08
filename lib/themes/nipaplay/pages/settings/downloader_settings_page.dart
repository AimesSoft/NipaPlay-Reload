import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:provider/provider.dart';

class DownloaderSettingsPage extends StatelessWidget {
  const DownloaderSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<DownloaderSettingsProvider>(
      builder: (context, provider, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SettingsCard(
              child: Column(
                children: [
                  SettingsItem.toggle(
                    title: '启用下载器',
                    subtitle: '关闭后隐藏主界面的下载器 Tab',
                    icon: Ionicons.cloud_download_outline,
                    value: provider.enabled,
                    onChanged: provider.setEnabled,
                  ),
                  Divider(
                    color: colorScheme.onSurface.withOpacity(0.12),
                    height: 1,
                  ),
                  SettingsItem.toggle(
                    title: '下载时创建同名文件夹',
                    subtitle: '开启后新任务会放入同名文件夹，文件夹名会忽略后缀名',
                    icon: Ionicons.folder_outline,
                    value: provider.createFolderForTask,
                    onChanged: provider.setCreateFolderForTask,
                  ),
                  Divider(
                    color: colorScheme.onSurface.withOpacity(0.12),
                    height: 1,
                  ),
                  SettingsItem.toggle(
                    title: '完成后自动加入媒体库',
                    subtitle: '任务下载完成后自动把输出文件夹加入库管理并扫描',
                    icon: Ionicons.library_outline,
                    value: provider.autoScanCompletedTasks,
                    onChanged: provider.setAutoScanCompletedTasks,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
