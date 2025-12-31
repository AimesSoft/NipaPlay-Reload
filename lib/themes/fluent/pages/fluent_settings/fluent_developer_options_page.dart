import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/themes/fluent/pages/fluent_settings/fluent_debug_log_viewer_page.dart';
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
              onPressed: () => _openDebugLogViewer(context),
              child: const Text('查看终端输出'),
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: '开发模式远程访问端口',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      devOptions.devRemoteAccessWebUiPort > 0
                          ? '${devOptions.devRemoteAccessWebUiPort}'
                          : '未设置',
                    ),
                  ),
                  Button(
                    onPressed: () => _showDevRemoteAccessWebUiPortDialog(context, devOptions),
                    child: const Text('设置'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '设置后，远程访问将把 Web UI 请求反向代理到本机端口（用于联调 Web UI）。留空/0 关闭。',
              style: theme.typography.caption,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDevRemoteAccessWebUiPortDialog(
    BuildContext context,
    DeveloperOptionsProvider devOptions,
  ) async {
    final controller = TextEditingController(
      text: devOptions.devRemoteAccessWebUiPort > 0
          ? devOptions.devRemoteAccessWebUiPort.toString()
          : '',
    );

    final newPort = await showDialog<int>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('开发模式远程访问端口'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextBox(
                controller: controller,
                keyboardType: TextInputType.number,
                placeholder: '留空/0 关闭',
              ),
              const SizedBox(height: 8),
              Text(
                '远程访问将把除 /api 以外的请求代理到 http://127.0.0.1:<端口>。',
                style: FluentTheme.of(context).typography.caption,
              ),
            ],
          ),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim();
                final parsed = raw.isEmpty ? 0 : int.tryParse(raw);
                final isValid =
                    parsed != null && (parsed == 0 || (parsed > 0 && parsed < 65536));
                if (isValid) {
                  Navigator.pop(context, parsed);
                } else {
                  _showInfoBar(
                    context,
                    '请输入有效端口 (1-65535)，或留空/0 关闭。',
                    severity: InfoBarSeverity.warning,
                  );
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (newPort == null) return;

    await devOptions.setDevRemoteAccessWebUiPort(newPort);

    final server = ServiceProvider.webServer;
    if (server.isRunning) {
      final currentPort = server.port;
      await server.stopServer();
      final restarted = await server.startServer(port: currentPort);
      if (context.mounted) {
        _showInfoBar(
          context,
          restarted ? '已保存，远程访问服务已重启生效。' : '已保存，但远程访问服务重启失败。',
          severity: restarted ? InfoBarSeverity.success : InfoBarSeverity.error,
        );
      }
      return;
    }

    if (context.mounted) {
      _showInfoBar(context, '已保存，下次开启远程访问时生效。', severity: InfoBarSeverity.success);
    }
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

  void _openDebugLogViewer(BuildContext context) {
    Navigator.of(context).push(
      FluentPageRoute(
        builder: (_) => const FluentDebugLogViewerPage(),
        fullscreenDialog: true,
      ),
    );
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
