import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_modal_popup.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:provider/provider.dart';

class CupertinoStorageSettingsPage extends StatefulWidget {
  const CupertinoStorageSettingsPage({super.key});

  @override
  State<CupertinoStorageSettingsPage> createState() =>
      _CupertinoStorageSettingsPageState();
}

class _CupertinoStorageSettingsPageState
    extends State<CupertinoStorageSettingsPage> {
  bool _clearOnLaunch = false;
  bool _isLoading = true;
  bool _isClearing = false;
  bool _isClearingImageCache = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final value = await SettingsStorage.loadBool(
      SettingsKeys.clearDanmakuCacheOnLaunch,
      defaultValue: false,
    );
    if (!mounted) return;
    setState(() {
      _clearOnLaunch = value;
      _isLoading = false;
    });
  }

  Future<void> _toggleClearOnLaunch(bool value) async {
    setState(() {
      _clearOnLaunch = value;
    });
    await SettingsStorage.saveBool(
      SettingsKeys.clearDanmakuCacheOnLaunch,
      value,
    );
    if (value) {
      await _clearDanmakuCache(showMessage: false);
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: context.l10n.enabledClearOnLaunchSnack,
          type: AdaptiveSnackBarType.info,
        );
      }
    }
  }

  Future<void> _clearDanmakuCache({bool showMessage = true}) async {
    if (_isClearing) return;
    setState(() {
      _isClearing = true;
    });
    try {
      await DanmakuCacheManager.clearAllCache();
      if (mounted && showMessage) {
        AdaptiveSnackBar.show(
          context,
          message: context.l10n.danmakuCacheCleared,
          type: AdaptiveSnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: context.l10n.clearFailed('$e'),
          type: AdaptiveSnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  Future<void> _clearImageCache({bool showMessage = true}) async {
    if (_isClearingImageCache) return;
    setState(() {
      _isClearingImageCache = true;
    });
    try {
      await ImageCacheManager.instance.clearCache();
      if (mounted && showMessage) {
        AdaptiveSnackBar.show(
          context,
          message: context.l10n.imageCacheCleared,
          type: AdaptiveSnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: context.l10n.clearFailed('$e'),
          type: AdaptiveSnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearingImageCache = false;
        });
      }
    }
  }

  Future<void> _confirmClearImageCache() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.l10n.confirmClearCacheTitle),
        content: Text(context.l10n.confirmClearImageCacheContent),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.confirm),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true) {
      await _clearImageCache(showMessage: true);
    }
  }

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
        title: context.l10n.storageSettings,
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: _isLoading
              ? const Center(child: CupertinoActivityIndicator())
              : ListView(
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
                            CupertinoIcons.refresh_circled,
                            color: resolveSettingsIconColor(context),
                          ),
                          title: Text(context.l10n.clearDanmakuCacheOnLaunchTitle),
                          subtitle: Text(context.l10n.clearDanmakuCacheOnLaunchSubtitle),
                          trailing: CupertinoSwitch(
                            value: _clearOnLaunch,
                            onChanged: _toggleClearOnLaunch,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    CupertinoSettingsGroupCard(
                      margin: EdgeInsets.zero,
                      addDividers: true,
                      dividerIndent: 56,
                      backgroundColor: sectionBackground,
                      children: [
                        Consumer<VideoPlayerState>(
                          builder: (context, videoState, child) {
                            final currentPath =
                                (videoState.screenshotSaveDirectory ?? '').trim();
                            return CupertinoSettingsTile(
                              leading: Icon(
                                CupertinoIcons.camera,
                                color: resolveSettingsIconColor(context),
                              ),
                              title: Text(context.l10n.screenshotSaveLocation),
                              subtitle: Text(
                                currentPath.isEmpty
                                    ? context.l10n.defaultDownloadDir
                                    : currentPath,
                              ),
                              showChevron: true,
                              onTap: () async {
                                final selected =
                                    await FilePickerService().pickDirectory(
                                  initialDirectory:
                                      currentPath.isEmpty ? null : currentPath,
                                );
                                if (selected == null ||
                                    selected.trim().isEmpty) {
                                  return;
                                }
                                await videoState
                                    .setScreenshotSaveDirectory(selected);
                                if (!mounted) return;
                                AdaptiveSnackBar.show(
                                  context,
                                  message: context.l10n.screenshotSaveLocationUpdated,
                                  type: AdaptiveSnackBarType.success,
                                );
                              },
                              backgroundColor:
                                  resolveSettingsTileBackground(context),
                            );
                          },
                        ),
                        if (defaultTargetPlatform == TargetPlatform.iOS)
                          Consumer<VideoPlayerState>(
                            builder: (context, videoState, child) {
                              return CupertinoSettingsTile(
                                leading: Icon(
                                  CupertinoIcons.photo_on_rectangle,
                                  color: resolveSettingsIconColor(context),
                                ),
                                title: Text(context.l10n.screenshotDefaultSaveTarget),
                                subtitle: Text(videoState.screenshotSaveTarget.label),
                                showChevron: true,
                                onTap: () async {
                                  final result =
                                      await showCupertinoModalPopupWithBottomBar<ScreenshotSaveTarget>(
                                    context: context,
                                    builder: (ctx) => CupertinoActionSheet(
                                      title: Text(context.l10n.screenshotDefaultSaveTarget),
                                      message: Text(context.l10n.screenshotDefaultSaveTargetMessage),
                                      actions: [
                                        CupertinoActionSheetAction(
                                          onPressed: () => Navigator.of(ctx)
                                              .pop(ScreenshotSaveTarget.ask),
                                          child: Text(
                                            ScreenshotSaveTarget.ask.label,
                                          ),
                                        ),
                                        CupertinoActionSheetAction(
                                          onPressed: () => Navigator.of(ctx)
                                              .pop(ScreenshotSaveTarget.photos),
                                          child: Text(
                                            ScreenshotSaveTarget.photos.label,
                                          ),
                                        ),
                                        CupertinoActionSheetAction(
                                          onPressed: () => Navigator.of(ctx)
                                              .pop(ScreenshotSaveTarget.file),
                                          child: Text(
                                            ScreenshotSaveTarget.file.label,
                                          ),
                                        ),
                                      ],
                                      cancelButton: CupertinoActionSheetAction(
                                        isDefaultAction: true,
                                        onPressed: () => Navigator.of(ctx).pop(),
                                        child: Text(context.l10n.cancel),
                                      ),
                                    ),
                                  );

                                  if (result != null) {
                                    await videoState.setScreenshotSaveTarget(result);
                                  }
                                },
                                backgroundColor:
                                    resolveSettingsTileBackground(context),
                              );
                            },
                          ),
                        CupertinoSettingsTile(
                          leading: Icon(
                            CupertinoIcons.trash,
                            color: CupertinoColors.destructiveRed.resolveFrom(
                              context,
                            ),
                          ),
                          title: Text(context.l10n.clearDanmakuCacheNow),
                          subtitle: Text(
                            _isClearing
                                ? context.l10n.clearingInProgress
                                : context.l10n.clearDanmakuCacheManualHint,
                          ),
                          onTap: _isClearing
                              ? null
                              : () => _clearDanmakuCache(showMessage: true),
                          trailing: _isClearing
                              ? const CupertinoActivityIndicator()
                              : Icon(
                                  CupertinoIcons.chevron_forward,
                                  color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.systemGrey2,
                                    context,
                                  ),
                                ),
                        ),
                        CupertinoSettingsTile(
                          leading: Icon(
                            CupertinoIcons.trash,
                            color: CupertinoColors.destructiveRed.resolveFrom(
                              context,
                            ),
                          ),
                          title: Text(context.l10n.clearImageCache),
                          subtitle: Text(
                            _isClearingImageCache
                                ? context.l10n.clearingInProgress
                                : context.l10n.clearImageCacheHint,
                          ),
                          onTap: _isClearingImageCache
                              ? null
                              : _confirmClearImageCache,
                          trailing: _isClearingImageCache
                              ? const CupertinoActivityIndicator()
                              : Icon(
                                  CupertinoIcons.chevron_forward,
                                  color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.systemGrey2,
                                    context,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        context.l10n.danmakuCacheDescription,
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .copyWith(
                              fontSize: 13,
                              color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemGrey,
                                context,
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        context.l10n.imageCacheDescription,
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .copyWith(
                              fontSize: 13,
                              color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemGrey,
                                context,
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
