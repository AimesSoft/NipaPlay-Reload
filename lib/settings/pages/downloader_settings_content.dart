import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:provider/provider.dart';

class DownloaderSettingsContent extends StatelessWidget {
  const DownloaderSettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloaderSettingsProvider>(
      builder: (context, provider, _) {
        if (!provider.isLoaded) {
          return AdaptiveSettingsPage(
            title: _title(context),
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: AdaptiveSettingsScope.isPhoneLayout(context)
                      ? const cupertino.CupertinoActivityIndicator()
                      : const CircularProgressIndicator(),
                ),
              ),
            ],
          );
        }

        return AdaptiveSettingsPage(
          title: _title(context),
          children: [
            AdaptiveSettingsSection(
              dividerIndent: 56,
              children: [
                AdaptiveSettingsTile.toggle(
                  title: _text(context, '启用下载器', '啟用下載器', 'Enable Downloader'),
                  subtitle: _text(
                    context,
                    '关闭后隐藏主界面的下载器 Tab',
                    '關閉後隱藏主界面的下載器 Tab',
                    'Hide the downloader tab when disabled.',
                  ),
                  icon: Ionicons.cloud_download_outline,
                  phoneIcon: cupertino.CupertinoIcons.arrow_down_circle,
                  value: provider.enabled,
                  onChanged: provider.setEnabled,
                ),
                AdaptiveSettingsTile.toggle(
                  title: _text(
                    context,
                    '下载时创建同名文件夹',
                    '下載時創建同名文件夾',
                    'Create a Folder Per Task',
                  ),
                  subtitle: _text(
                    context,
                    '开启后新任务会放入同名文件夹，文件夹名会忽略后缀名',
                    '開啟後新任務會放入同名文件夾，文件夾名會忽略後綴名',
                    'Put new tasks into a same-name folder without the extension.',
                  ),
                  icon: Ionicons.folder_outline,
                  phoneIcon: cupertino.CupertinoIcons.folder,
                  value: provider.createFolderForTask,
                  onChanged: provider.setCreateFolderForTask,
                ),
                AdaptiveSettingsTile.toggle(
                  title: _text(
                    context,
                    '完成后自动加入媒体库',
                    '完成後自動加入媒體庫',
                    'Auto-add Completed Tasks',
                  ),
                  subtitle: _text(
                    context,
                    '任务下载完成后自动把输出文件夹加入库管理并扫描',
                    '任務下載完成後自動把輸出文件夾加入庫管理並掃描',
                    'Scan the output folder into the media library after completion.',
                  ),
                  icon: Ionicons.library_outline,
                  phoneIcon: cupertino.CupertinoIcons.collections,
                  value: provider.autoScanCompletedTasks,
                  onChanged: provider.setAutoScanCompletedTasks,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _title(BuildContext context) {
    return context.l10n.tabTorrentDownload;
  }

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final localeName = context.l10n.localeName;
    if (localeName.startsWith('zh_Hant')) {
      return traditional;
    }
    if (localeName.startsWith('en')) {
      return english;
    }
    return simplified;
  }
}
