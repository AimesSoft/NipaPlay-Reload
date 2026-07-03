import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/file_log_service.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_build_info_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_debug_log_viewer_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dependency_versions_sheet.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/debug_log_viewer_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/dependency_versions_window.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/nipaplay_ui_preview_window.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/build_info.dart';
import 'package:nipaplay/utils/linux_storage_migration.dart';
import 'package:nipaplay/utils/platform_utils.dart' as platform;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class DeveloperOptionsSettingsContent extends StatelessWidget {
  const DeveloperOptionsSettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isCupertino = AdaptiveSettingsScope.isCupertino(context);
    const showCertificateToggle = !kIsWeb;
    final showLinuxTools = !kIsWeb && platform.Platform.isLinux;

    return Consumer<DeveloperOptionsProvider>(
      builder: (context, devOptions, child) {
        return AdaptiveSettingsPage(
          title: l10n.developerOptions,
          children: [
            AdaptiveSettingsSection(
              children: [
                if (showCertificateToggle)
                  AdaptiveSettingsTile<bool>.toggle(
                    title: _text(
                      context,
                      '允许自签名证书（全局）',
                      '允許自簽名憑證（全域）',
                      'Allow Self-Signed Certificates',
                    ),
                    subtitle: _text(
                      context,
                      '仅在内网或调试时开启，Web 平台不生效。',
                      '僅在內網或除錯時開啟，Web 平台不生效。',
                      'Enable only for local networks or debugging. Web is not affected.',
                    ),
                    icon: Ionicons.alert_circle_outline,
                    cupertinoIcon:
                        cupertino.CupertinoIcons.exclamationmark_shield,
                    value: devOptions.allowInvalidCertsGlobal,
                    onChanged: (value) async {
                      await devOptions.setAllowInvalidCertsGlobal(value);
                      if (!context.mounted) return;
                      AdaptiveSnackBar.show(
                        context,
                        message: value
                            ? _text(
                                context,
                                '自签名证书全局开关：已开启（不安全）',
                                '自簽名憑證全域開關：已開啟（不安全）',
                                'Self-signed certificates are now allowed.',
                              )
                            : _text(
                                context,
                                '自签名证书全局开关：已关闭（默认安全）',
                                '自簽名憑證全域開關：已關閉（預設安全）',
                                'Self-signed certificates are no longer allowed.',
                              ),
                        type: value
                            ? AdaptiveSnackBarType.warning
                            : AdaptiveSnackBarType.success,
                      );
                    },
                  ),
                AdaptiveSettingsTile<bool>.toggle(
                  title: _text(
                    context,
                    '显示系统资源监控',
                    '顯示系統資源監控',
                    'Show System Resource Monitor',
                  ),
                  subtitle: _text(
                    context,
                    '在界面右上角显示 CPU、内存和帧率信息',
                    '在介面右上角顯示 CPU、記憶體與影格率資訊',
                    'Show CPU, memory, and FPS in the upper-right corner.',
                  ),
                  icon: Ionicons.analytics_outline,
                  cupertinoIcon: cupertino.CupertinoIcons.speedometer,
                  value: devOptions.showSystemResources,
                  onChanged: devOptions.setShowSystemResources,
                ),
                AdaptiveSettingsTile<bool>.toggle(
                  title: _text(
                    context,
                    '调试日志收集',
                    '除錯日誌收集',
                    'Debug Log Collection',
                  ),
                  subtitle: _text(
                    context,
                    '收集应用的所有打印输出，用于调试和问题诊断',
                    '收集應用程式的所有列印輸出，用於除錯與問題診斷',
                    'Collect app print output for debugging and diagnostics.',
                  ),
                  icon: Ionicons.document_text_outline,
                  cupertinoIcon: cupertino.CupertinoIcons.doc_text,
                  value: devOptions.enableDebugLogCollection,
                  onChanged: (value) async {
                    await devOptions.setEnableDebugLogCollection(value);
                    final logService = DebugLogService();
                    if (value) {
                      logService.startCollecting();
                    } else {
                      logService.stopCollecting();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            AdaptiveSettingsSection(
              children: [
                AdaptiveSettingsTile<bool>.toggle(
                  title: l10n.fileLogWriteTitle,
                  subtitle: l10n.fileLogWriteSubtitle,
                  icon: Ionicons.folder_outline,
                  cupertinoIcon: cupertino.CupertinoIcons.folder,
                  value: devOptions.enableFileLog,
                  onChanged: (value) => _setFileLog(context, devOptions, value),
                ),
                AdaptiveSettingsTile<void>.card(
                  title: l10n.openLogDirectoryTitle,
                  subtitle: l10n.openLogDirectorySubtitle,
                  icon: Ionicons.folder_open_outline,
                  cupertinoIcon: cupertino.CupertinoIcons.folder_open,
                  onTap: () => _openLogDirectory(context),
                ),
                AdaptiveSettingsTile<void>.card(
                  title: l10n.terminalOutput,
                  subtitle: l10n.terminalOutputSubtitle,
                  icon: Ionicons.terminal_outline,
                  cupertinoIcon: cupertino.CupertinoIcons.command,
                  onTap: () => _openDebugLogViewer(context),
                ),
                AdaptiveSettingsTile<void>.card(
                  title: l10n.dependencyVersions,
                  subtitle: l10n.dependencyVersionsSubtitle,
                  icon: Ionicons.list_outline,
                  cupertinoIcon: cupertino.CupertinoIcons.list_bullet,
                  onTap: () => _openDependencyVersions(context),
                ),
                if (!isCupertino)
                  AdaptiveSettingsTile<void>.card(
                    title: _text(
                      context,
                      'Nipaplay 设计 UI 预览',
                      'Nipaplay 設計 UI 預覽',
                      'Nipaplay UI Preview',
                    ),
                    subtitle: _text(
                      context,
                      '在窗口中集中查看 Nipaplay UI 组件示例',
                      '在視窗中集中查看 Nipaplay UI 元件範例',
                      'Preview Nipaplay UI components in a window.',
                    ),
                    icon: Ionicons.color_palette_outline,
                    cupertinoIcon: cupertino.CupertinoIcons.paintbrush,
                    onTap: () => _openNipaplayUiPreview(context),
                  ),
                AdaptiveSettingsTile<void>.card(
                  title: l10n.buildInfo,
                  subtitle: l10n.buildInfoSubtitle,
                  icon: Ionicons.information_circle_outline,
                  cupertinoIcon: cupertino.CupertinoIcons.info_circle,
                  onTap: () => _showBuildInfo(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                final enabled = videoState.spoilerPreventionEnabled;
                return AdaptiveSettingsSection(
                  children: [
                    AdaptiveSettingsTile<bool>.toggle(
                      title: l10n.spoilerAiDebugPrintTitle,
                      subtitle: enabled
                          ? l10n.spoilerAiDebugPrintEnabledHint
                          : l10n.spoilerAiDebugPrintNeedSpoilerMode,
                      icon: Ionicons.information_circle_outline,
                      cupertinoIcon: cupertino.CupertinoIcons.info_circle,
                      enabled: enabled,
                      value: videoState.spoilerAiDebugPrintResponse,
                      onChanged: (value) async {
                        await videoState.setSpoilerAiDebugPrintResponse(value);
                        if (!context.mounted) return;
                        AdaptiveSnackBar.show(
                          context,
                          message: value
                              ? l10n.spoilerAiDebugPrintEnabled
                              : l10n.spoilerAiDebugPrintDisabled,
                          type: AdaptiveSnackBarType.success,
                        );
                      },
                    ),
                  ],
                );
              },
            ),
            if (showLinuxTools) ...[
              const SizedBox(height: 16),
              AdaptiveSettingsSection(
                children: [
                  AdaptiveSettingsTile<void>.card(
                    title: _text(
                      context,
                      '检查 Linux 存储迁移状态',
                      '檢查 Linux 儲存遷移狀態',
                      'Check Linux Storage Migration',
                    ),
                    subtitle: _text(
                      context,
                      '查看 Linux 平台数据目录迁移状态',
                      '查看 Linux 平台資料目錄遷移狀態',
                      'View Linux data directory migration status.',
                    ),
                    icon: Ionicons.information_circle_outline,
                    cupertinoIcon: cupertino.CupertinoIcons.info_circle,
                    onTap: () => _checkLinuxMigrationStatus(context),
                  ),
                  AdaptiveSettingsTile<void>.card(
                    title: _text(
                      context,
                      '手动触发存储迁移',
                      '手動觸發儲存遷移',
                      'Run Storage Migration',
                    ),
                    subtitle: _text(
                      context,
                      '强制重新执行数据目录迁移（仅用于测试）',
                      '強制重新執行資料目錄遷移（僅用於測試）',
                      'Force data directory migration for testing.',
                    ),
                    icon: Ionicons.refresh_outline,
                    cupertinoIcon: cupertino.CupertinoIcons.refresh,
                    onTap: () => _manualTriggerMigration(context),
                  ),
                  AdaptiveSettingsTile<void>.card(
                    title: _text(
                      context,
                      '紧急恢复个人文件',
                      '緊急恢復個人檔案',
                      'Emergency Personal File Restore',
                    ),
                    subtitle: _text(
                      context,
                      '将误迁移的个人文件恢复到 Documents 目录',
                      '將誤遷移的個人檔案恢復到 Documents 目錄',
                      'Restore personal files moved to the app data directory.',
                    ),
                    icon: Ionicons.medical_outline,
                    cupertinoIcon:
                        cupertino.CupertinoIcons.exclamationmark_triangle,
                    isDestructive: true,
                    onTap: () => _emergencyRestorePersonalFiles(context),
                  ),
                  AdaptiveSettingsTile<void>.card(
                    title: _text(
                      context,
                      '显示存储目录信息',
                      '顯示儲存目錄資訊',
                      'Show Storage Directory Info',
                    ),
                    subtitle: _text(
                      context,
                      '查看当前使用的数据和缓存目录路径',
                      '查看目前使用的資料與快取目錄路徑',
                      'View current data and cache directory paths.',
                    ),
                    icon: Ionicons.folder_outline,
                    cupertinoIcon: cupertino.CupertinoIcons.folder,
                    onTap: () => _showStorageDirectoryInfo(context),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _setFileLog(
    BuildContext context,
    DeveloperOptionsProvider devOptions,
    bool value,
  ) async {
    final enabledMessage = context.l10n.fileLogWriteEnabled;
    final disabledMessage = context.l10n.fileLogWriteDisabled;
    await devOptions.setEnableFileLog(value);
    final fileLogService = FileLogService();
    if (value) {
      await fileLogService.start();
    } else {
      await fileLogService.stop();
    }
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: value ? enabledMessage : disabledMessage,
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _openLogDirectory(BuildContext context) async {
    final openedMessage = context.l10n.logDirectoryOpened;
    final failedMessage = context.l10n.openLogDirectoryFailed;
    final ok = await FileLogService().openLogDirectory();
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: ok ? openedMessage : failedMessage,
      type: ok ? AdaptiveSnackBarType.success : AdaptiveSnackBarType.error,
    );
  }

  Future<void> _openDebugLogViewer(BuildContext context) async {
    if (AdaptiveSettingsScope.isCupertino(context)) {
      await CupertinoBottomSheet.show(
        context: context,
        title: context.l10n.terminalOutput,
        floatingTitle: true,
        child: const CupertinoDebugLogViewerSheet(),
      );
      return;
    }

    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    NipaplayWindow.show<void>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      child: Builder(
        builder: (dialogContext) {
          final colorScheme = Theme.of(dialogContext).colorScheme;
          final screenSize = MediaQuery.of(dialogContext).size;
          final maxWidth = (screenSize.width * 0.95).clamp(320.0, 1200.0);

          return NipaplayWindowScaffold(
            maxWidth: maxWidth,
            maxHeightFactor: 0.85,
            onClose: () => Navigator.of(dialogContext).maybePop(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: Row(
                    children: [
                      Text(
                        context.l10n.terminalOutput,
                        locale: const Locale('zh', 'CN'),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                ),
                const Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    child: DebugLogViewerPage(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openDependencyVersions(BuildContext context) async {
    if (AdaptiveSettingsScope.isCupertino(context)) {
      await CupertinoBottomSheet.show(
        context: context,
        title: context.l10n.dependencyVersions,
        floatingTitle: true,
        child: const CupertinoDependencyVersionsSheet(),
      );
      return;
    }

    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    NipaplayWindow.show<void>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      child: const DependencyVersionsWindow(),
    );
  }

  void _openNipaplayUiPreview(BuildContext context) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    NipaplayWindow.show<void>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      child: const NipaplayUiPreviewWindow(),
    );
  }

  Future<void> _showBuildInfo(BuildContext context) async {
    if (AdaptiveSettingsScope.isCupertino(context)) {
      await CupertinoBottomSheet.show(
        context: context,
        title: context.l10n.buildInfo,
        floatingTitle: true,
        child: const CupertinoBuildInfoSheet(),
      );
      return;
    }

    final infoFuture = loadBuildInfoSections();
    BlurDialog.show<void>(
      context: context,
      title: context.l10n.buildInfo,
      contentWidget: FutureBuilder<List<BuildInfoSection>>(
        future: infoFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在收集构建信息...'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return Text('读取构建信息失败: ${snapshot.error}');
          }
          return _buildBuildInfoContent(context, snapshot.data ?? []);
        },
      ),
      actions: [
        HoverScaleTextButton(
          child: Text(
            context.l10n.close,
            locale: const Locale('zh-Hans', 'zh'),
            style: const TextStyle(color: Colors.lightBlueAccent),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildBuildInfoContent(
    BuildContext context,
    List<BuildInfoSection> sections,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      color: colorScheme.onSurface.withValues(alpha: 0.65),
      fontSize: 13,
    );
    final valueStyle = TextStyle(
      color: colorScheme.onSurface.withValues(alpha: 0.9),
      fontSize: 14,
    );
    final titleStyle = TextStyle(
      color: colorScheme.onSurface,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );
    final noteStyle = TextStyle(
      color: colorScheme.onSurface.withValues(alpha: 0.6),
      fontSize: 12,
      height: 1.4,
    );

    if (sections.isEmpty) {
      return const Text('暂无构建信息');
    }

    final children = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      children.add(
        Text(section.title, style: titleStyle, textAlign: TextAlign.left),
      );
      children.add(const SizedBox(height: 8));
      for (final entry in section.entries) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 86,
                  child: Text(
                    entry.label,
                    style: labelStyle,
                    textAlign: TextAlign.left,
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.value,
                    style: valueStyle,
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      if (i != sections.length - 1) {
        children.add(const SizedBox(height: 12));
      }
    }

    children.add(const SizedBox(height: 6));
    children.add(
      Text(
        '注：构建前需生成 assets/build_info.json，未生成将显示“未注入”。',
        style: noteStyle,
        textAlign: TextAlign.left,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Future<void> _checkLinuxMigrationStatus(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;

    try {
      final needsMigration = await LinuxStorageMigration.needsMigration();
      final dataDir = await LinuxStorageMigration.getXDGDataDirectory();
      final cacheDir = await LinuxStorageMigration.getXDGCacheDirectory();

      if (!context.mounted) return;

      BlurDialog.show<void>(
        context: context,
        title: 'Linux存储迁移状态',
        content: '''
当前状态: ${needsMigration ? '需要迁移' : '迁移已完成'}

XDG数据目录: $dataDir
XDG缓存目录: $cacheDir

遵循XDG Base Directory规范，提供更好的Linux用户体验。
        '''
            .trim(),
        actions: [
          HoverScaleTextButton(
            child: const Text(
              '知道了',
              locale: Locale('zh-Hans', 'zh'),
              style: TextStyle(color: Colors.lightBlueAccent),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    } catch (e) {
      if (!context.mounted) return;

      AdaptiveSnackBar.show(
        context,
        message: '检查迁移状态失败: $e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _manualTriggerMigration(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '确认迁移',
      content: '这将重新执行数据目录迁移过程。\n\n注意：这是一个测试功能，在正常情况下不应该使用。',
      actions: [
        HoverScaleTextButton(
          child: const Text(
            '取消',
            locale: Locale('zh-Hans', 'zh'),
            style: TextStyle(color: Colors.white70),
          ),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        HoverScaleTextButton(
          child: const Text(
            '确认',
            locale: Locale('zh-Hans', 'zh'),
            style: TextStyle(color: Colors.orange),
          ),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirm != true || !context.mounted) return;
    AdaptiveSnackBar.show(context, message: '开始执行迁移...');

    try {
      await LinuxStorageMigration.resetMigrationStatus();
      final result = await LinuxStorageMigration.performMigration();

      if (!context.mounted) return;

      if (result.success) {
        BlurDialog.show<void>(
          context: context,
          title: '迁移成功',
          content: '''
${result.message}

迁移详情:
- 总项目数: ${result.totalItems}
- 成功项目: ${result.migratedItems}
- 失败项目: ${result.failedItems}
          '''
              .trim(),
          actions: [
            HoverScaleTextButton(
              child: const Text(
                '知道了',
                locale: Locale('zh-Hans', 'zh'),
                style: TextStyle(color: Colors.lightBlueAccent),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      } else {
        BlurDialog.show<void>(
          context: context,
          title: '迁移失败',
          content: '''
${result.message}

错误信息:
${result.errors.join('\n')}
          '''
              .trim(),
          actions: [
            HoverScaleTextButton(
              child: const Text(
                '知道了',
                locale: Locale('zh-Hans', 'zh'),
                style: TextStyle(color: Colors.orange),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '迁移过程出错: $e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _showStorageDirectoryInfo(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;

    try {
      final dataDir = await LinuxStorageMigration.getXDGDataDirectory();
      final cacheDir = await LinuxStorageMigration.getXDGCacheDirectory();
      final xdgDataHome =
          platform.Platform.environment['XDG_DATA_HOME'] ?? '未设置';
      final xdgCacheHome =
          platform.Platform.environment['XDG_CACHE_HOME'] ?? '未设置';
      final homeDir = platform.Platform.environment['HOME'] ?? '未知';

      if (!context.mounted) return;

      BlurDialog.show<void>(
        context: context,
        title: 'Linux存储目录信息',
        content: '''
=== 当前使用的目录 ===
数据目录: $dataDir
缓存目录: $cacheDir

=== 环境变量 ===
HOME: $homeDir
XDG_DATA_HOME: $xdgDataHome
XDG_CACHE_HOME: $xdgCacheHome

=== 说明 ===
- 数据目录用于存储用户数据（数据库、设置等）
- 缓存目录用于存储临时文件和缓存
- 遵循XDG Base Directory规范
- 提供与其他Linux应用一致的用户体验
        '''
            .trim(),
        actions: [
          HoverScaleTextButton(
            child: const Text(
              '知道了',
              locale: Locale('zh-Hans', 'zh'),
              style: TextStyle(color: Colors.lightBlueAccent),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    } catch (e) {
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '获取目录信息失败: $e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _emergencyRestorePersonalFiles(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '紧急恢复个人文件',
      content: '''
这个功能将把误迁移到 ~/.local/share/NipaPlay 的个人文件恢复到 ~/Documents 目录。

注意事项：
- 只恢复非应用相关的文件
- 应用数据（如数据库、缓存等）会保留在新位置
- 这是一个紧急修复功能

是否继续？
      '''
          .trim(),
      actions: [
        HoverScaleTextButton(
          child: const Text(
            '取消',
            locale: Locale('zh-Hans', 'zh'),
            style: TextStyle(color: Colors.white70),
          ),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        HoverScaleTextButton(
          child: const Text(
            '确认恢复',
            locale: Locale('zh-Hans', 'zh'),
            style: TextStyle(color: Colors.red),
          ),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirm != true || !context.mounted) return;
    AdaptiveSnackBar.show(context, message: '开始恢复个人文件...');

    try {
      final result =
          await LinuxStorageMigration.emergencyRestorePersonalFiles();

      if (!context.mounted) return;

      if (result.success) {
        BlurDialog.show<void>(
          context: context,
          title: '恢复成功',
          content: '''
${result.message}

恢复详情:
- 总文件数: ${result.totalItems}
- 成功恢复: ${result.migratedItems}
- 失败项目: ${result.failedItems}

您的个人文件已恢复到 ~/Documents 目录。
          '''
              .trim(),
          actions: [
            HoverScaleTextButton(
              child: const Text(
                '知道了',
                locale: Locale('zh-Hans', 'zh'),
                style: TextStyle(color: Colors.lightBlueAccent),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      } else {
        BlurDialog.show<void>(
          context: context,
          title: '恢复失败',
          content: '''
${result.message}

错误信息:
${result.errors.join('\n')}
          '''
              .trim(),
          actions: [
            HoverScaleTextButton(
              child: const Text(
                '知道了',
                locale: Locale('zh-Hans', 'zh'),
                style: TextStyle(color: Colors.orange),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '恢复过程出错: $e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final locale = context.l10n.localeName;
    if (locale == 'en') {
      return english;
    }
    if (locale == 'zh_Hant') {
      return traditional;
    }
    return simplified;
  }
}
