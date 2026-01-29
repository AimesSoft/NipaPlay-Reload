import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';
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
        BlurSnackBar.show(context, '已启用启动时清理弹幕缓存');
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
        BlurSnackBar.show(context, '弹幕缓存已清理');
      }
    } catch (e) {
      if (mounted && showSnack) {
        BlurSnackBar.show(context, '清理弹幕缓存失败: $e');
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
        BlurSnackBar.show(context, '图片缓存已清除');
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '清除图片缓存失败: $e');
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
      title: '确认清除缓存',
      content: '确定要清除封面与缩略图等图片缓存吗？',
      actions: [
        HoverScaleTextButton(
          child: Text(
            '取消',
            locale: const Locale('zh-Hans', 'zh'),
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
          ),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        HoverScaleTextButton(
          child: Text(
            '确定',
            locale: const Locale('zh-Hans', 'zh'),
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      children: [
        SettingsItem.toggle(
          title: '每次启动时清理弹幕缓存',
          subtitle: '重启应用时自动删除所有已缓存的弹幕文件，确保数据实时',
          icon: Ionicons.refresh_outline,
          value: _clearOnLaunch,
          onChanged: _updateClearOnLaunch,
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        SettingsItem.button(
          title: '立即清理弹幕缓存',
          subtitle: _isClearing ? '正在清理...' : '删除缓存/缓存异常时可手动清理',
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
            '弹幕缓存文件存储在 cache/danmaku/ 目录下，占用空间较大时可随时清理。',
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
              title: '截图保存位置',
              subtitle: currentPath.isEmpty ? '默认：下载目录' : currentPath,
              icon: Icons.camera_alt_outlined,
              onTap: () async {
                final selected = await FilePickerService().pickDirectory(
                  initialDirectory: currentPath.isEmpty ? null : currentPath,
                );
                if (selected == null || selected.trim().isEmpty) return;
                await videoState.setScreenshotSaveDirectory(selected);
                if (!context.mounted) return;
                BlurSnackBar.show(context, '截图保存位置已更新');
              },
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        SettingsItem.button(
          title: '清除图片缓存',
          subtitle: _isClearingImageCache ? '正在清理...' : '清除封面与缩略图等图片缓存',
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
            '图片缓存包含封面与播放缩略图，存储在应用缓存目录中，可定期清理。',
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
