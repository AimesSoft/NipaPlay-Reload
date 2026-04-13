import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';

import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_build_info_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_dependency_versions_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_debug_log_viewer_sheet.dart';
import 'package:nipaplay/services/file_log_service.dart';
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
      title: context.l10n.terminalOutput,
      floatingTitle: true,
      child: const CupertinoDebugLogViewerSheet(),
    );
  }

  Future<void> _openDependencyVersions(BuildContext context) async {
    await CupertinoBottomSheet.show(
      context: context,
      title: context.l10n.dependencyVersions,
      floatingTitle: true,
      child: const CupertinoDependencyVersionsSheet(),
    );
  }

  Future<void> _openBuildInfo(BuildContext context) async {
    await CupertinoBottomSheet.show(
      context: context,
      title: context.l10n.buildInfo,
      floatingTitle: true,
      child: const CupertinoBuildInfoSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeveloperOptionsProvider>(
      builder: (context, devOptions, child) {
        final l10n = context.l10n;
        final Color backgroundColor = CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground,
          context,
        );
        final double topPadding = MediaQuery.of(context).padding.top + 64;
        return AdaptiveScaffold(
          appBar: AdaptiveAppBar(
            title: l10n.developerOptions,
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
                        title: Text(l10n.terminalOutput),
                        subtitle: Text(l10n.terminalOutputSubtitle),
                        backgroundColor: resolveSettingsTileBackground(context),
                        showChevron: true,
                        onTap: () => _openTerminalOutput(context),
                      ),
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.list_bullet,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: Text(l10n.dependencyVersions),
                        subtitle: Text(l10n.dependencyVersionsSubtitle),
                        backgroundColor: resolveSettingsTileBackground(context),
                        showChevron: true,
                        onTap: () => _openDependencyVersions(context),
                      ),
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.info_circle,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: Text(l10n.buildInfo),
                        subtitle: Text(l10n.buildInfoSubtitle),
                        backgroundColor: resolveSettingsTileBackground(context),
                        showChevron: true,
                        onTap: () => _openBuildInfo(context),
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
                          CupertinoIcons.folder,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: Text(l10n.fileLogWriteTitle),
                        subtitle: Text(l10n.fileLogWriteSubtitle),
                        trailing: AdaptiveSwitch(
                          value: devOptions.enableFileLog,
                          onChanged: (value) async {
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
                              message: value
                                  ? l10n.fileLogWriteEnabled
                                  : l10n.fileLogWriteDisabled,
                              type: AdaptiveSnackBarType.success,
                            );
                          },
                        ),
                        onTap: () async {
                          final newValue = !devOptions.enableFileLog;
                          await devOptions.setEnableFileLog(newValue);
                          final fileLogService = FileLogService();
                          if (newValue) {
                            await fileLogService.start();
                          } else {
                            await fileLogService.stop();
                          }
                          if (!context.mounted) return;
                          AdaptiveSnackBar.show(
                            context,
                            message: newValue
                                ? l10n.fileLogWriteEnabled
                                : l10n.fileLogWriteDisabled,
                            type: AdaptiveSnackBarType.success,
                          );
                        },
                        backgroundColor: resolveSettingsTileBackground(context),
                      ),
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.folder_open,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: Text(l10n.openLogDirectoryTitle),
                        subtitle: Text(l10n.openLogDirectorySubtitle),
                        backgroundColor: resolveSettingsTileBackground(context),
                        showChevron: true,
                        onTap: () async {
                          final ok = await FileLogService().openLogDirectory();
                          if (!context.mounted) return;
                          AdaptiveSnackBar.show(
                            context,
                            message: ok
                                ? l10n.logDirectoryOpened
                                : l10n.openLogDirectoryFailed,
                            type: ok
                                ? AdaptiveSnackBarType.success
                                : AdaptiveSnackBarType.error,
                          );
                        },
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
                            title: Text(l10n.spoilerAiDebugPrintTitle),
                            subtitle: Text(
                              enabled
                                  ? l10n.spoilerAiDebugPrintEnabledHint
                                  : l10n.spoilerAiDebugPrintNeedSpoilerMode,
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
                                            ? l10n.spoilerAiDebugPrintEnabled
                                            : l10n.spoilerAiDebugPrintDisabled,
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
                                          ? l10n.spoilerAiDebugPrintEnabled
                                          : l10n.spoilerAiDebugPrintDisabled,
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
