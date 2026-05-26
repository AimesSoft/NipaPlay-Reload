import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/platform_utils.dart' as platform;
import 'package:flutter/material.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/dependency_versions_window.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/debug_log_viewer_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/nipaplay_ui_preview_window.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/file_log_service.dart';
import 'package:nipaplay/utils/linux_storage_migration.dart';
import 'package:nipaplay/utils/build_info.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';
// 证书相关的主机快捷信任按钮应用户要求移除，仅保留全局开关

/// 开发者选项设置页面
class DeveloperOptionsPage extends StatelessWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<DeveloperOptionsProvider>(
      builder: (context, devOptions, child) {
        return ListView(
          children: [
            // 危险：全局允许无效/自签名证书（仅 IO 平台生效）
            SettingsItem.toggle(
              title: '允许自签名证书（全局）',
              subtitle: '仅桌面/Android/iOS生效，Web无效，仅在内网或调试时开启。',
              icon: Ionicons.alert_circle_outline,
              value: devOptions.allowInvalidCertsGlobal,
              onChanged: (bool value) async {
                await devOptions.setAllowInvalidCertsGlobal(value);
                // 立即反馈
                final status = value ? '已开启（不安全）' : '已关闭（默认安全）';
                BlurSnackBar.show(context, '自签名证书全局开关：$status');
              },
            ),

            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            // 显示系统资源监控开关（所有平台可用）
            SettingsItem.toggle(
              title: '显示系统资源监控',
              subtitle: '在界面右上角显示CPU、内存和帧率信息',
              icon: Ionicons.analytics_outline,
              value: devOptions.showSystemResources,
              onChanged: (bool value) {
                devOptions.setShowSystemResources(value);
              },
            ),

            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

            // 调试日志收集开关
            SettingsItem.toggle(
              title: '调试日志收集',
              subtitle: '收集应用的所有打印输出，用于调试和问题诊断',
              icon: Ionicons.document_text_outline,
              value: devOptions.enableDebugLogCollection,
              onChanged: (bool value) async {
                await devOptions.setEnableDebugLogCollection(value);

                // 根据设置控制日志服务
                final logService = DebugLogService();
                if (value) {
                  logService.startCollecting();
                } else {
                  logService.stopCollecting();
                }
              },
            ),

            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

            // 日志写入文件开关
            SettingsItem.toggle(
              title: '日志写入文件',
              subtitle: '每 1 秒写入磁盘，保留最近 5 份日志文件',
              icon: Ionicons.folder_outline,
              value: devOptions.enableFileLog,
              onChanged: (bool value) async {
                await devOptions.setEnableFileLog(value);

                final fileLogService = FileLogService();
                if (value) {
                  await fileLogService.start();
                  BlurSnackBar.show(context, '已开启日志写入文件');
                } else {
                  await fileLogService.stop();
                  BlurSnackBar.show(context, '已关闭日志写入文件');
                }
              },
            ),

            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

            SettingsItem.button(
              title: '打开日志路径',
              subtitle: '在文件管理器中打开日志目录',
              icon: Ionicons.folder_open_outline,
              trailingIcon: Ionicons.chevron_forward_outline,
              onTap: () async {
                final ok = await FileLogService().openLogDirectory();
                if (!context.mounted) return;
                BlurSnackBar.show(
                  context,
                  ok ? '已打开日志目录' : '打开日志目录失败',
                );
              },
            ),

            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                final enabled = videoState.spoilerPreventionEnabled;
                return SettingsItem.toggle(
                  title: '调试：打印 AI 返回内容',
                  subtitle:
                      enabled ? '开启后会在日志里打印 AI 返回的原始文本与命中弹幕' : '需先启用防剧透模式',
                  icon: Ionicons.information_circle_outline,
                  enabled: enabled,
                  value: videoState.spoilerAiDebugPrintResponse,
                  onChanged: (bool value) async {
                    await videoState.setSpoilerAiDebugPrintResponse(value);
                    BlurSnackBar.show(
                      context,
                      value ? '已开启 AI 调试打印' : '已关闭 AI 调试打印',
                    );
                  },
                );
              },
            ),

            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

            // 终端输出查看器
            SettingsItem.button(
              title: '终端输出',
              subtitle: '查看应用的所有打印输出，支持搜索、过滤和复制',
              icon: Ionicons.terminal_outline,
              trailingIcon: Ionicons.chevron_forward_outline,
              onTap: () {
                _openDebugLogViewer(context);
              },
            ),

            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

            SettingsItem.button(
              title: '依赖库版本',
              subtitle: '查看依赖库版本与 GitHub 跳转',
              icon: Ionicons.list_outline,
              trailingIcon: Ionicons.chevron_forward_outline,
              onTap: () {
                _openDependencyVersions(context);
              },
            ),

            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

            SettingsItem.button(
              title: 'Nipaplay 设计 UI 预览',
              subtitle: '在窗口中集中查看 Nipaplay UI 组件示例',
              icon: Ionicons.color_palette_outline,
              trailingIcon: Ionicons.chevron_forward_outline,
              onTap: () {
                _openNipaplayUiPreview(context);
              },
            ),

            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

            SettingsItem.button(
              title: '构建信息',
              subtitle: '查看构建时间、处理器、内存与系统架构',
              icon: Ionicons.information_circle_outline,
              trailingIcon: Ionicons.chevron_forward_outline,
              onTap: () {
                _showBuildInfo(context);
              },
            ),

            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

            // Linux存储迁移选项（仅Linux平台显示，Web环境下不显示）
            if (!kIsWeb && platform.Platform.isLinux) ...[
              // 检查迁移状态
              ListTile(
                title: Text(
                  '检查Linux存储迁移状态',
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '查看Linux平台数据目录迁移状态',
                  locale: Locale("zh-Hans", "zh"),
                  style:
                      TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                ),
                trailing: Icon(Ionicons.information_circle_outline,
                    color: colorScheme.onSurface),
                onTap: () => _checkLinuxMigrationStatus(context),
              ),

              Divider(
                  color: colorScheme.onSurface.withOpacity(0.12), height: 1),

              // 手动触发迁移
              ListTile(
                title: Text(
                  '手动触发存储迁移',
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '强制重新执行数据目录迁移（仅用于测试）',
                  locale: Locale("zh-Hans", "zh"),
                  style:
                      TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                ),
                trailing:
                    const Icon(Ionicons.refresh_outline, color: Colors.orange),
                onTap: () => _manualTriggerMigration(context),
              ),

              Divider(
                  color: colorScheme.onSurface.withOpacity(0.12), height: 1),

              // 紧急恢复个人文件
              ListTile(
                title: const Text(
                  '🚨 紧急恢复个人文件',
                  locale: Locale("zh-Hans", "zh"),
                  style:
                      TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '将误迁移的个人文件恢复到Documents目录',
                  locale: Locale("zh-Hans", "zh"),
                  style:
                      TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                ),
                trailing:
                    const Icon(Ionicons.medical_outline, color: Colors.red),
                onTap: () => _emergencyRestorePersonalFiles(context),
              ),

              Divider(
                  color: colorScheme.onSurface.withOpacity(0.12), height: 1),

              // 显示存储目录信息
              ListTile(
                title: Text(
                  '显示存储目录信息',
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '查看当前使用的数据和缓存目录路径',
                  locale: Locale("zh-Hans", "zh"),
                  style:
                      TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                ),
                trailing:
                    Icon(Ionicons.folder_outline, color: colorScheme.onSurface),
                onTap: () => _showStorageDirectoryInfo(context),
              ),

              Divider(
                  color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            ],

            // 这里可以添加更多开发者选项
          ],
        );
      },
    );
  }

  void _openDebugLogViewer(BuildContext context) {
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
        builder: (BuildContext dialogContext) {
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
                        '终端输出',
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
                  color: colorScheme.onSurface.withOpacity(0.12),
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

  void _openDependencyVersions(BuildContext context) {
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

  void _showBuildInfo(BuildContext context) {
    final infoFuture = loadBuildInfoSections();
    BlurDialog.show<void>(
      context: context,
      title: '构建信息',
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
      actions: <Widget>[
        HoverScaleTextButton(
          child: const Text(
            "知道了",
            locale: Locale("zh-Hans", "zh"),
            style: TextStyle(color: Colors.lightBlueAccent),
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
      color: colorScheme.onSurface.withOpacity(0.65),
      fontSize: 13,
    );
    final valueStyle = TextStyle(
      color: colorScheme.onSurface.withOpacity(0.9),
      fontSize: 14,
    );
    final titleStyle = TextStyle(
      color: colorScheme.onSurface,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );
    final noteStyle = TextStyle(
      color: colorScheme.onSurface.withOpacity(0.6),
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

  // 检查Linux存储迁移状态
  Future<void> _checkLinuxMigrationStatus(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;

    try {
      final needsMigration = await LinuxStorageMigration.needsMigration();
      final dataDir = await LinuxStorageMigration.getXDGDataDirectory();
      final cacheDir = await LinuxStorageMigration.getXDGCacheDirectory();

      if (!context.mounted) return;

      BlurDialog.show<void>(
        context: context,
        title: "Linux存储迁移状态",
        content: """
当前状态: ${needsMigration ? '需要迁移' : '迁移已完成'}

XDG数据目录: $dataDir
XDG缓存目录: $cacheDir

遵循XDG Base Directory规范，提供更好的Linux用户体验。
        """
            .trim(),
        actions: <Widget>[
          HoverScaleTextButton(
            child: const Text("知道了",
                locale: Locale("zh-Hans", "zh"),
                style: TextStyle(color: Colors.lightBlueAccent)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    } catch (e) {
      if (!context.mounted) return;

      BlurSnackBar.show(context, '检查迁移状态失败: $e');
    }
  }

  // 手动触发存储迁移
  Future<void> _manualTriggerMigration(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: "确认迁移",
      content: "这将重新执行数据目录迁移过程。\n\n注意：这是一个测试功能，在正常情况下不应该使用。",
      actions: <Widget>[
        HoverScaleTextButton(
          child: const Text("取消",
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.white70)),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        HoverScaleTextButton(
          child: const Text("确认",
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.orange)),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirm == true && context.mounted) {
      BlurSnackBar.show(context, '开始执行迁移...');

      try {
        // 重置迁移状态
        await LinuxStorageMigration.resetMigrationStatus();

        // 执行迁移
        final result = await LinuxStorageMigration.performMigration();

        if (!context.mounted) return;

        if (result.success) {
          BlurDialog.show<void>(
            context: context,
            title: "迁移成功",
            content: """
${result.message}

迁移详情:
- 总项目数: ${result.totalItems}
- 成功项目: ${result.migratedItems}
- 失败项目: ${result.failedItems}
            """
                .trim(),
            actions: <Widget>[
              HoverScaleTextButton(
                child: const Text("知道了",
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(color: Colors.lightBlueAccent)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        } else {
          BlurDialog.show<void>(
            context: context,
            title: "迁移失败",
            content: """
${result.message}

错误信息:
${result.errors.join('\n')}
            """
                .trim(),
            actions: <Widget>[
              HoverScaleTextButton(
                child: const Text("知道了",
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(color: Colors.orange)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        BlurSnackBar.show(context, '迁移过程出错: $e');
      }
    }
  }

  // 显示存储目录信息
  Future<void> _showStorageDirectoryInfo(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;

    try {
      final dataDir = await LinuxStorageMigration.getXDGDataDirectory();
      final cacheDir = await LinuxStorageMigration.getXDGCacheDirectory();

      // 获取环境变量信息
      final xdgDataHome =
          platform.Platform.environment['XDG_DATA_HOME'] ?? '未设置';
      final xdgCacheHome =
          platform.Platform.environment['XDG_CACHE_HOME'] ?? '未设置';
      final homeDir = platform.Platform.environment['HOME'] ?? '未知';

      if (!context.mounted) return;

      BlurDialog.show<void>(
        context: context,
        title: "Linux存储目录信息",
        content: """
=== 当前使用的目录 ===
数据目录: $dataDir
缓存目录: $cacheDir

=== 环境变量 ===
HOME: $homeDir
XDG_DATA_HOME: $xdgDataHome
XDG_CACHE_HOME: $xdgCacheHome

=== 说明 ===
• 数据目录用于存储用户数据（数据库、设置等）
• 缓存目录用于存储临时文件和缓存
• 遵循XDG Base Directory规范
• 提供与其他Linux应用一致的用户体验
        """
            .trim(),
        actions: <Widget>[
          HoverScaleTextButton(
            child: const Text("知道了",
                locale: Locale("zh-Hans", "zh"),
                style: TextStyle(color: Colors.lightBlueAccent)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    } catch (e) {
      if (!context.mounted) return;
      BlurSnackBar.show(context, '获取目录信息失败: $e');
    }
  }

  // 紧急恢复个人文件
  Future<void> _emergencyRestorePersonalFiles(BuildContext context) async {
    if (kIsWeb || !platform.Platform.isLinux) return;

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: "🚨 紧急恢复个人文件",
      content: """
这个功能将把误迁移到 ~/.local/share/NipaPlay 的个人文件恢复到 ~/Documents 目录。

⚠️ 注意事项：
• 只恢复非应用相关的文件
• 应用数据（如数据库、缓存等）会保留在新位置
• 这是一个紧急修复功能

是否继续？
      """
          .trim(),
      actions: <Widget>[
        HoverScaleTextButton(
          child: const Text("取消",
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.white70)),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        HoverScaleTextButton(
          child: const Text("确认恢复",
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.red)),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirm == true && context.mounted) {
      BlurSnackBar.show(context, '开始恢复个人文件...');

      try {
        final result =
            await LinuxStorageMigration.emergencyRestorePersonalFiles();

        if (!context.mounted) return;

        if (result.success) {
          BlurDialog.show<void>(
            context: context,
            title: "恢复成功",
            content: """
${result.message}

恢复详情:
- 总文件数: ${result.totalItems}
- 成功恢复: ${result.migratedItems}
- 失败项目: ${result.failedItems}

您的个人文件已恢复到 ~/Documents 目录。
            """
                .trim(),
            actions: <Widget>[
              HoverScaleTextButton(
                child: const Text("知道了",
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(color: Colors.lightBlueAccent)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        } else {
          BlurDialog.show<void>(
            context: context,
            title: "恢复失败",
            content: """
${result.message}

错误信息:
${result.errors.join('\n')}
            """
                .trim(),
            actions: <Widget>[
              HoverScaleTextButton(
                child: const Text("知道了",
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(color: Colors.orange)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        BlurSnackBar.show(context, '恢复过程出错: $e');
      }
    }
  }
}
