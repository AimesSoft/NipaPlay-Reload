import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material; // 用于跳转现有日志页面
import 'package:nipaplay/pages/settings/debug_log_viewer_page.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/utils/linux_storage_migration.dart';
import 'package:nipaplay/utils/platform_utils.dart' as platform;
import 'package:provider/provider.dart';

class FluentDeveloperOptionsPage extends StatelessWidget {
  const FluentDeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DeveloperOptionsProvider>(
      builder: (context, devOptions, child) {
        return ScaffoldPage(
          header: const PageHeader(title: Text('开发者选项')),
          content: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ListView(
              children: [
                _buildSecuritySection(context, devOptions),
                const SizedBox(height: 16),
                _buildDiagnosticsSection(context, devOptions),
                if (!kIsWeb && platform.Platform.isLinux) ...[
                  const SizedBox(height: 16),
                  _buildLinuxToolsSection(context),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSecuritySection(BuildContext context, DeveloperOptionsProvider devOptions) {
    final theme = FluentTheme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(FluentIcons.shield),
                const SizedBox(width: 8),
                Text(
                  '安全选项',
                  style: theme.typography.subtitle?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: '允许自签名证书 (全局)',
              child: ToggleSwitch(
                checked: devOptions.allowInvalidCertsGlobal,
                onChanged: (value) async {
                  await devOptions.setAllowInvalidCertsGlobal(value);
                  if (context.mounted) {
                    _showInfoBar(
                      context,
                      '自签名证书全局开关已${value ? '开启 (不安全)' : '关闭 (安全)'}',
                      severity: value ? InfoBarSeverity.warning : InfoBarSeverity.success,
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '仅桌面 / Android / iOS 生效，Web 无效。请仅在可信网络或调试时开启。',
              style: theme.typography.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsSection(BuildContext context, DeveloperOptionsProvider devOptions) {
    final theme = FluentTheme.of(context);
    final logService = DebugLogService();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(FluentIcons.developer_tools),
                const SizedBox(width: 8),
                Text(
                  '调试与诊断',
                  style: theme.typography.subtitle?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: '显示系统资源监控',
              child: ToggleSwitch(
                checked: devOptions.showSystemResources,
                onChanged: devOptions.setShowSystemResources,
              ),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: '调试日志收集',
              child: ToggleSwitch(
                checked: devOptions.enableDebugLogCollection,
                onChanged: (value) async {
                  await devOptions.setEnableDebugLogCollection(value);
                  if (value) {
                    logService.startCollecting();
                  } else {
                    logService.stopCollecting();
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: () {
                Navigator.of(context).push(
                  material.MaterialPageRoute(builder: (_) => const DebugLogViewerPage()),
                );
              },
              child: const Text('查看终端输出'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinuxToolsSection(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(FluentIcons.desktop_flow),
                const SizedBox(width: 8),
                Text(
                  'Linux 专用工具',
                  style: theme.typography.subtitle?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: () => _checkLinuxMigrationStatus(context),
              child: const Text('检查存储迁移状态'),
            ),
            const SizedBox(height: 8),
            Button(
              onPressed: () => _manualTriggerMigration(context),
              child: const Text('手动触发存储迁移'),
            ),
            const SizedBox(height: 8),
            Button(
              onPressed: () => _emergencyRestore(context),
              style: ButtonStyle(
                foregroundColor: ButtonState.all(const Color(0xFFD13438)),
              ),
              child: const Text('紧急恢复个人文件'),
            ),
            const SizedBox(height: 8),
            Button(
              onPressed: () => _showDirectoryInfo(context),
              child: const Text('查看当前存储目录'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkLinuxMigrationStatus(BuildContext context) async {
    final needsMigration = await LinuxStorageMigration.needsMigration();
    if (context.mounted) {
      _showInfoBar(
        context,
        needsMigration ? '检测到旧版数据目录，建议执行迁移。' : '未检测到需要迁移的数据。',
        severity: needsMigration ? InfoBarSeverity.warning : InfoBarSeverity.success,
      );
    }
  }

  Future<void> _manualTriggerMigration(BuildContext context) async {
    final result = await LinuxStorageMigration.performMigration();
    if (context.mounted) {
      _showInfoBar(
        context,
        result.message,
        severity: result.success ? InfoBarSeverity.success : InfoBarSeverity.error,
      );
    }
  }

  Future<void> _emergencyRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('紧急恢复个人文件'),
          content: const Text('此操作将尝试恢复误迁移的个人文件至用户目录。是否继续？'),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('执行恢复'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final result = await LinuxStorageMigration.emergencyRestorePersonalFiles();
      if (context.mounted) {
        _showInfoBar(
          context,
          result.message,
          severity: result.success ? InfoBarSeverity.success : InfoBarSeverity.error,
        );
      }
    }
  }

  Future<void> _showDirectoryInfo(BuildContext context) async {
    try {
      final dataDir = await LinuxStorageMigration.getXDGDataDirectory();
      final cacheDir = await LinuxStorageMigration.getXDGCacheDirectory();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return ContentDialog(
            title: const Text('存储目录信息'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoLabel(
                  label: '数据目录',
                  child: SelectableText(dataDir),
                ),
                const SizedBox(height: 12),
                InfoLabel(
                  label: '缓存目录',
                  child: SelectableText(cacheDir),
                ),
              ],
            ),
            actions: [
              Button(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (context.mounted) {
        _showInfoBar(context, '查询目录失败: $e', severity: InfoBarSeverity.error);
      }
    }
  }

  void _showInfoBar(
    BuildContext context,
    String message, {
    InfoBarSeverity severity = InfoBarSeverity.info,
  }) {
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: Text(_infoBarTitle(severity)),
        severity: severity,
        content: Text(message),
        action: IconButton(
          icon: const Icon(FluentIcons.clear),
          onPressed: close,
        ),
      ),
    );
  }

  String _infoBarTitle(InfoBarSeverity severity) {
    switch (severity) {
      case InfoBarSeverity.success:
        return '成功';
      case InfoBarSeverity.warning:
        return '警告';
      case InfoBarSeverity.error:
        return '错误';
      case InfoBarSeverity.info:
      default:
        return '提示';
    }
  }
}
