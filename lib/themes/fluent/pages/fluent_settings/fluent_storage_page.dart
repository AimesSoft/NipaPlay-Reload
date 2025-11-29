import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/themes/fluent/widgets/fluent_info_bar.dart';
import 'package:nipaplay/utils/settings_storage.dart';

class FluentStoragePage extends StatefulWidget {
  const FluentStoragePage({super.key});

  @override
  State<FluentStoragePage> createState() => _FluentStoragePageState();
}

class _FluentStoragePageState extends State<FluentStoragePage> {
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
      await _clearDanmakuCache(showSuccess: false);
      if (mounted) {
        FluentInfoBar.show(
          context,
          '已启用启动时清理弹幕缓存',
          severity: InfoBarSeverity.info,
        );
      }
    }
  }

  Future<void> _clearDanmakuCache({bool showSuccess = true}) async {
    if (_isClearing) return;
    setState(() {
      _isClearing = true;
    });
    try {
      await DanmakuCacheManager.clearAllCache();
      if (mounted && showSuccess) {
        FluentInfoBar.show(
          context,
          '弹幕缓存已清理',
          severity: InfoBarSeverity.success,
        );
      }
    } catch (e) {
      if (mounted) {
        FluentInfoBar.show(
          context,
          '清理弹幕缓存失败',
          content: e.toString(),
          severity: InfoBarSeverity.error,
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
    if (_isLoading) {
      return const ScaffoldPage(
        content: Center(child: ProgressRing()),
      );
    }

    return ScaffoldPage(
      header: const PageHeader(
        title: Text('存储设置'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '弹幕缓存策略',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: 12),
                      ToggleSwitch(
                        checked: _clearOnLaunch,
                        onChanged: _toggleClearOnLaunch,
                        content: const Text('每次启动时清理弹幕缓存'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '启用后，应用启动时将自动删除 cache/danmaku/ 目录下的缓存弹幕，以确保匹配结果最新。',
                        style: FluentTheme.of(context).typography.caption,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '手动清理',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed:
                            _isClearing ? null : () => _clearDanmakuCache(),
                        style: ButtonStyle(
                          backgroundColor: ButtonState.resolveWith((states) {
                            if (states.isDisabled) {
                              return FluentTheme.of(context)
                                  .inactiveColor
                                  .withOpacity(0.2);
                            }
                            return Colors.red;
                          }),
                        ),
                        child: _isClearing
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: ProgressRing(strokeWidth: 2),
                              )
                            : const Text('立即清理弹幕缓存'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '当弹幕出现异常或占用空间较大时，可使用此按钮立即清理缓存。',
                        style: FluentTheme.of(context).typography.caption,
                      ),
                    ],
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
