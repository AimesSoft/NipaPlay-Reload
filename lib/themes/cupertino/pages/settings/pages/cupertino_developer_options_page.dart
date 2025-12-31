import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_debug_log_viewer_sheet.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:provider/provider.dart';

class CupertinoDeveloperOptionsPage extends StatelessWidget {
  const CupertinoDeveloperOptionsPage({super.key});

  Future<void> _openTerminalOutput(BuildContext context) async {
    await CupertinoBottomSheet.show(
      context: context,
      title: '终端输出',
      floatingTitle: true,
      child: const CupertinoDebugLogViewerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeveloperOptionsProvider>(
      builder: (context, devOptions, child) {
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 64;
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle.copyWith(
          fontSize: 13,
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGrey,
            context,
          ),
          letterSpacing: 0.2,
        );

    return AdaptiveScaffold(
          appBar: const AdaptiveAppBar(
            title: '开发者选项',
            useNativeToolbar: true,
          ),
          body: ColoredBox(
            color: backgroundColor,
            child: SafeArea(
              top: false,
              bottom: false,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
                children: [
                  CupertinoSettingsGroupCard(
                    margin: EdgeInsets.zero,
                    backgroundColor: resolveSettingsSectionBackground(context),
                    addDividers: true,
                    children: [
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.command,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: const Text('终端输出'),
                        subtitle: const Text('查看日志、复制内容或生成二维码分享'),
                        backgroundColor: resolveSettingsTileBackground(context),
                        showChevron: true,
                        onTap: () => _openTerminalOutput(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  CupertinoSettingsGroupCard(
                    margin: EdgeInsets.zero,
                    backgroundColor: resolveSettingsSectionBackground(context),
                    addDividers: true,
                    children: [
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.globe,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: const Text('开发模式远程访问端口'),
                        subtitle: Text(
                          devOptions.devRemoteAccessWebUiPort > 0
                              ? '127.0.0.1:${devOptions.devRemoteAccessWebUiPort}'
                              : '未设置（使用内置 Web UI）',
                        ),
                        backgroundColor: resolveSettingsTileBackground(context),
                        showChevron: true,
                        onTap: () =>
                            _showDevRemoteAccessWebUiPortDialog(context, devOptions),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '用于联调 Web UI：设置后远程访问会将除 /api 以外的请求反向代理到本机该端口（留空/0 关闭）。',
                      style: textStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

    final newPort = await showCupertinoDialog<int>(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('开发模式远程访问端口'),
          content: Column(
            children: [
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                placeholder: '留空/0 关闭',
              ),
              const SizedBox(height: 8),
              const Text('远程访问将把 Web UI 请求代理到 http://127.0.0.1:<端口>。'),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final raw = controller.text.trim();
                final parsed = raw.isEmpty ? 0 : int.tryParse(raw);
                final isValid =
                    parsed != null && (parsed == 0 || (parsed > 0 && parsed < 65536));
                if (isValid) {
                  Navigator.of(dialogContext).pop(parsed);
                } else {
                  AdaptiveSnackBar.show(
                    context,
                    message: '请输入有效端口 (1-65535)，或留空/0 关闭。',
                    type: AdaptiveSnackBarType.error,
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
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: restarted ? '已保存，远程访问服务已重启生效' : '已保存，但远程访问服务重启失败',
        type: restarted ? AdaptiveSnackBarType.success : AdaptiveSnackBarType.error,
      );
      return;
    }

    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: '已保存，下次开启远程访问时生效',
      type: AdaptiveSnackBarType.success,
    );
  }
}
