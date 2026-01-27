import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/utils/settings_storage.dart';

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
                ],
              ),
      ),
    );
  }
}
