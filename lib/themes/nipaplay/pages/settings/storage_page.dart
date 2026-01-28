import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/utils/settings_storage.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  bool _clearOnLaunch = false;
  bool _isLoading = true;
  bool _isClearing = false;

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
      ],
    );
  }
}
