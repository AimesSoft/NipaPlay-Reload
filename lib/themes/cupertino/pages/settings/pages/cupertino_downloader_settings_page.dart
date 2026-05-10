import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/downloader_settings_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:provider/provider.dart';

class CupertinoDownloaderSettingsPage extends StatelessWidget {
  const CupertinoDownloaderSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final sectionBackground = resolveSettingsSectionBackground(context);
    final double topPadding = MediaQuery.of(context).padding.top + 64;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: context.l10n.localeName.startsWith('zh_Hant') ? '下載器' : '下载器',
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Consumer<DownloaderSettingsProvider>(
            builder: (context, provider, _) {
              if (!provider.isLoaded) {
                return const Center(child: CupertinoActivityIndicator());
              }

              return ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
                children: [
                  CupertinoSettingsGroupCard(
                    margin: EdgeInsets.zero,
                    addDividers: true,
                    dividerIndent: 56,
                    backgroundColor: sectionBackground,
                    children: [
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.arrow_down_circle,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: Text(
                          context.l10n.localeName.startsWith('zh_Hant')
                              ? '啟用下載器'
                              : '启用下载器',
                        ),
                        subtitle: Text(
                          context.l10n.localeName.startsWith('zh_Hant')
                              ? '關閉後隱藏主界面的下載器 Tab'
                              : '关闭后隐藏主界面的下载器 Tab',
                        ),
                        trailing: CupertinoSwitch(
                          value: provider.enabled,
                          onChanged: provider.setEnabled,
                        ),
                      ),
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.folder,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: Text(
                          context.l10n.localeName.startsWith('zh_Hant')
                              ? '下載時創建同名文件夾'
                              : '下载时创建同名文件夹',
                        ),
                        subtitle: Text(
                          context.l10n.localeName.startsWith('zh_Hant')
                              ? '開啟後新任務會放入同名文件夾，文件夾名會忽略後綴名'
                              : '开启后新任务会放入同名文件夹，文件夹名会忽略后缀名',
                        ),
                        trailing: CupertinoSwitch(
                          value: provider.createFolderForTask,
                          onChanged: provider.setCreateFolderForTask,
                        ),
                      ),
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.collections,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: Text(
                          context.l10n.localeName.startsWith('zh_Hant')
                              ? '完成後自動加入媒體庫'
                              : '完成后自动加入媒体库',
                        ),
                        subtitle: Text(
                          context.l10n.localeName.startsWith('zh_Hant')
                              ? '任務下載完成後自動把輸出文件夾加入庫管理並掃描'
                              : '任务下载完成后自动把输出文件夹加入库管理并扫描',
                        ),
                        trailing: CupertinoSwitch(
                          value: provider.autoScanCompletedTasks,
                          onChanged: provider.setAutoScanCompletedTasks,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
