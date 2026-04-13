import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:provider/provider.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
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

  Future<void> _updateClearOnLaunch(bool value) async {
    setState(() {
      _clearOnLaunch = value;
    });
    await SettingsStorage.saveBool(
      SettingsKeys.clearDanmakuCacheOnLaunch,
      value,
    );
    if (value) {
      await _clearDanmakuCache(showSnack: false);
      if (mounted) {
        BlurSnackBar.show(context, context.l10n.enabledClearOnLaunchSnack);
      }
    }
  }

  Future<void> _clearDanmakuCache({bool showSnack = true}) async {
    if (_isClearing) return;
    setState(() {
      _isClearing = true;
    });
    try {
      await DanmakuCacheManager.clearAllCache();
      if (mounted && showSnack) {
        BlurSnackBar.show(context, context.l10n.danmakuCacheCleared);
      }
    } catch (e) {
      if (mounted && showSnack) {
        BlurSnackBar.show(context, context.l10n.clearDanmakuCacheFailed('$e'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  Future<void> _clearImageCache() async {
    if (_isClearingImageCache) return;
    setState(() {
      _isClearingImageCache = true;
    });
    try {
      await ImageCacheManager.instance.clearCache();
      if (mounted) {
        BlurSnackBar.show(context, context.l10n.imageCacheCleared);
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, context.l10n.clearImageCacheFailed('$e'));
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
    final colorScheme = Theme.of(context).colorScheme;
    final bool? confirm = await BlurDialog.show<bool>(
      context: context,
      title: context.l10n.confirmClearCacheTitle,
      content: context.l10n.confirmClearImageCacheContent,
      actions: [
        HoverScaleTextButton(
          child: Text(
            context.l10n.cancel,
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
          ),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        HoverScaleTextButton(
          child: Text(
            context.l10n.confirm,
            style: TextStyle(color: colorScheme.onSurface),
          ),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (!mounted) return;
    if (confirm == true) {
      await _clearImageCache();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      children: [
        SettingsItem.toggle(
          title: l10n.clearDanmakuCacheOnLaunchTitle,
          subtitle: l10n.clearDanmakuCacheOnLaunchSubtitleNipaplay,
          icon: Ionicons.refresh_outline,
          value: _clearOnLaunch,
          onChanged: _updateClearOnLaunch,
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        SettingsItem.button(
          title: l10n.clearDanmakuCacheNow,
          subtitle:
              _isClearing ? l10n.clearingInProgress : l10n.clearDanmakuCacheManualHintNipaplay,
          icon: Ionicons.trash_bin_outline,
          isDestructive: true,
          enabled: !_isClearing,
          onTap: () => _clearDanmakuCache(showSnack: true),
          trailingIcon: Ionicons.chevron_forward_outline,
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            l10n.danmakuCacheDescriptionNipaplay,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
          ),
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final currentPath = (videoState.screenshotSaveDirectory ?? '').trim();
            return SettingsItem.button(
              title: l10n.screenshotSaveLocation,
              subtitle: currentPath.isEmpty ? l10n.defaultDownloadDir : currentPath,
              icon: Icons.camera_alt_outlined,
              onTap: () async {
                final selected = await FilePickerService().pickDirectory(
                  initialDirectory: currentPath.isEmpty ? null : currentPath,
                );
                if (selected == null || selected.trim().isEmpty) return;
                await videoState.setScreenshotSaveDirectory(selected);
                if (!context.mounted) return;
                BlurSnackBar.show(context, l10n.screenshotSaveLocationUpdated);
              },
            );
          },
        ),
        if (defaultTargetPlatform == TargetPlatform.iOS) ...[
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
          Consumer<VideoPlayerState>(
            builder: (context, videoState, child) {
              return SettingsItem.dropdown(
                title: l10n.screenshotDefaultSaveTarget,
                subtitle: l10n.screenshotDefaultSaveTargetMessage,
                icon: Icons.save_alt,
                items: [
                  DropdownMenuItemData(
                    title: ScreenshotSaveTarget.ask.label,
                    value: ScreenshotSaveTarget.ask,
                    isSelected:
                        videoState.screenshotSaveTarget == ScreenshotSaveTarget.ask,
                    description: l10n.screenshotSaveAskDescription,
                  ),
                  DropdownMenuItemData(
                    title: ScreenshotSaveTarget.photos.label,
                    value: ScreenshotSaveTarget.photos,
                    isSelected: videoState.screenshotSaveTarget ==
                        ScreenshotSaveTarget.photos,
                    description: l10n.screenshotSavePhotosDescription,
                  ),
                  DropdownMenuItemData(
                    title: ScreenshotSaveTarget.file.label,
                    value: ScreenshotSaveTarget.file,
                    isSelected:
                        videoState.screenshotSaveTarget == ScreenshotSaveTarget.file,
                    description: l10n.screenshotSaveFileDescription,
                  ),
                ],
                onChanged: (value) {
                  if (value is ScreenshotSaveTarget) {
                    videoState.setScreenshotSaveTarget(value);
                  }
                },
              );
            },
          ),
        ],
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        SettingsItem.button(
          title: l10n.clearImageCache,
          subtitle:
              _isClearingImageCache ? l10n.clearingInProgress : l10n.clearImageCacheHint,
          icon: Ionicons.trash_outline,
          trailingIcon: Ionicons.chevron_forward_outline,
          isDestructive: true,
          enabled: !_isClearingImageCache,
          onTap: _confirmClearImageCache,
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            l10n.imageCacheDescriptionNipaplay,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
          ),
        ),
      ],
    );
  }
}
