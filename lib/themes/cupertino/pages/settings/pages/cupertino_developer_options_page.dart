import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_build_info_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dependency_versions_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_debug_log_viewer_sheet.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/video_player_state.dart';
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

  Future<void> _openDependencyVersions(BuildContext context) async {
    await CupertinoBottomSheet.show(
      context: context,
      title: '依赖库版本',
      floatingTitle: true,
      child: const CupertinoDependencyVersionsSheet(),
    );
  }

  Future<void> _openBuildInfo(BuildContext context) async {
    await CupertinoBottomSheet.show(
      context: context,
      title: '构建信息',
      floatingTitle: true,
      child: const CupertinoBuildInfoSheet(),
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
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.list_bullet,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: const Text('依赖库版本'),
                        subtitle: const Text('查看依赖库与版本号（含 GitHub 跳转）'),
                        backgroundColor: resolveSettingsTileBackground(context),
                        showChevron: true,
                        onTap: () => _openDependencyVersions(context),
                      ),
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.info_circle,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: const Text('构建信息'),
                        subtitle: const Text('查看构建时间、处理器、内存与系统架构'),
                        backgroundColor: resolveSettingsTileBackground(context),
                        showChevron: true,
                        onTap: () => _openBuildInfo(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Consumer<VideoPlayerState>(
                    builder: (context, videoState, child) {
                      final enabled = videoState.spoilerPreventionEnabled;
                      return CupertinoSettingsGroupCard(
                        margin: EdgeInsets.zero,
                        backgroundColor:
                            resolveSettingsSectionBackground(context),
                        addDividers: true,
                        children: [
                          CupertinoSettingsTile(
                            leading: Icon(
                              CupertinoIcons.info_circle,
                              color: resolveSettingsIconColor(context),
                            ),
                            title: const Text('调试：打印 AI 返回内容'),
                            subtitle: Text(
                              enabled
                                  ? '开启后会在日志里打印 AI 返回的原始文本与命中弹幕。'
                                  : '需先启用防剧透模式',
                            ),
                            trailing: AdaptiveSwitch(
                              value: videoState.spoilerAiDebugPrintResponse,
                              onChanged: enabled
                                  ? (value) async {
                                      await videoState
                                          .setSpoilerAiDebugPrintResponse(
                                        value,
                                      );
                                      if (!context.mounted) return;
                                      AdaptiveSnackBar.show(
                                        context,
                                        message: value
                                            ? '已开启 AI 调试打印'
                                            : '已关闭 AI 调试打印',
                                        type: AdaptiveSnackBarType.success,
                                      );
                                    }
                                  : null,
                            ),
                            onTap: enabled
                                ? () async {
                                    final newValue =
                                        !videoState.spoilerAiDebugPrintResponse;
                                    await videoState
                                        .setSpoilerAiDebugPrintResponse(
                                      newValue,
                                    );
                                    if (!context.mounted) return;
                                    AdaptiveSnackBar.show(
                                      context,
                                      message: newValue
                                          ? '已开启 AI 调试打印'
                                          : '已关闭 AI 调试打印',
                                      type: AdaptiveSnackBarType.success,
                                    );
                                  }
                                : null,
                            backgroundColor:
                                resolveSettingsTileBackground(context),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
