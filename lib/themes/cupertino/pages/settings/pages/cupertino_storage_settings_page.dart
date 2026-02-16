import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
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
          message: '已启用启动时清理弹幕缓存',
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
          message: '弹幕缓存已清理',
          type: AdaptiveSnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: '清理失败: $e',
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
          message: '图片缓存已清除',
          type: AdaptiveSnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: '清理失败: $e',
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
        title: const Text('确认清除缓存'),
        content: const Text('确定要清除封面与缩略图等图片缓存吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
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
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('存储设置'),
      ),
      child: SafeArea(
        child: _isLoading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  CupertinoSettingsGroupCard(
                    addDividers: true,
                    backgroundColor: resolveSettingsSectionBackground(context),
                    children: [
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.refresh_circled,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: const Text('每次启动时清理弹幕缓存'),
                        subtitle: const Text('自动删除 cache/danmaku/ 目录下的弹幕缓存'),
                        trailing: CupertinoSwitch(
                          value: _clearOnLaunch,
                          onChanged: _toggleClearOnLaunch,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  CupertinoSettingsGroupCard(
                    addDividers: true,
                    backgroundColor: resolveSettingsSectionBackground(context),
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
                            title: const Text('截图保存位置'),
                            subtitle: Text(
                              currentPath.isEmpty ? '默认：下载目录' : currentPath,
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
                                message: '截图保存位置已更新',
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
                              title: const Text('截图默认保存位置'),
                              subtitle: Text(videoState.screenshotSaveTarget.label),
                              showChevron: true,
                              onTap: () async {
                                final result =
                                    await showCupertinoModalPopup<ScreenshotSaveTarget>(
                                  context: context,
                                  builder: (ctx) => CupertinoActionSheet(
                                    title: const Text('截图默认保存位置'),
                                    message: const Text('选择截图后的默认保存方式'),
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
                                      child: const Text('取消'),
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
                        title: const Text('立即清理弹幕缓存'),
                        subtitle: Text(
                          _isClearing
                              ? '正在清理...'
                              : '当弹幕异常或占用空间过大时可手动清理',
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
                        title: const Text('清除图片缓存'),
                        subtitle: Text(
                          _isClearingImageCache
                              ? '正在清理...'
                              : '清除封面与缩略图等图片缓存',
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
                  Text(
                    '弹幕缓存将存储在应用缓存目录 cache/danmaku/ 中，启用自动清理可减轻空间占用。',
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
                  const SizedBox(height: 6),
                  Text(
                    '图片缓存包含封面与播放缩略图，存储在应用缓存目录中，可按需清理。',
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
                ],
              ),
      ),
    );
  }
}
