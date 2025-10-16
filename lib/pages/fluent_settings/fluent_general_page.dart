import 'package:fluent_ui/fluent_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_info_bar.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'dart:io';

const String globalFilterAdultContentKey = 'global_filter_adult_content';
const String defaultPageIndexKey = 'default_page_index';

class FluentGeneralPage extends StatefulWidget {
  const FluentGeneralPage({super.key});

  @override
  State<FluentGeneralPage> createState() => _FluentGeneralPageState();
}

class _FluentGeneralPageState extends State<FluentGeneralPage> {
  bool _filterAdultContent = true;
  int _defaultPageIndex = 0;
  bool _isLoading = true;

  // 根据平台生成页面名称列表
  List<String> get _pageNames {
    List<String> names = [
      '主页',
      '视频播放',
      '媒体库',
    ];

    // 仅在非iOS平台添加新番更新
    if (!Platform.isIOS) {
      names.add('新番更新');
    }

    names.add('设置');
    return names;
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _filterAdultContent = prefs.getBool(globalFilterAdultContentKey) ?? true;
        var storedIndex = prefs.getInt(defaultPageIndexKey) ?? 0;

        // 在iOS平台上，如果存储的索引是新番更新页面(3)或设置页面(4)，调整为设置页面(3)
        if (Platform.isIOS && storedIndex >= 3) {
          storedIndex = 3; // iOS上设置页面的索引
        }

        _defaultPageIndex = storedIndex;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveFilterPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(globalFilterAdultContentKey, value);
  }

  Future<void> _saveDefaultPagePreference(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(defaultPageIndexKey, index);
  }

  Future<void> _clearImageCache() async {
    try {
      await ImageCacheManager.instance.clearCache();
      if (mounted) {
        FluentInfoBar.show(
          context,
          '图片缓存已清除',
          severity: InfoBarSeverity.success,
        );
      }
    } catch (e) {
      if (mounted) {
        FluentInfoBar.show(
          context,
          '清除缓存失败',
          content: e.toString(),
          severity: InfoBarSeverity.error,
        );
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

    final appearanceSettings = context.watch<AppearanceSettingsProvider>();

    return ScaffoldPage(
      header: const PageHeader(
        title: Text('通用设置'),
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
                        '启动设置',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('默认展示页面'),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ComboBox<int>(
                              value: _defaultPageIndex,
                              items: List.generate(_pageNames.length, (index) {
                                return ComboBoxItem<int>(
                                  value: index,
                                  child: Text(_pageNames[index]),
                                );
                              }),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _defaultPageIndex = value;
                                  });
                                  _saveDefaultPagePreference(value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '选择应用启动后默认显示的页面',
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
                        '番剧卡片行为',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('点击行为'),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ComboBox<AnimeCardAction>(
                              value: appearanceSettings.animeCardAction,
                              items: const [
                                ComboBoxItem<AnimeCardAction>(
                                  value: AnimeCardAction.synopsis,
                                  child: Text('简介'),
                                ),
                                ComboBoxItem<AnimeCardAction>(
                                  value: AnimeCardAction.episodeList,
                                  child: Text('剧集列表'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  appearanceSettings.setAnimeCardAction(value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '选择点击番剧卡片后的默认展示内容。',
                        style: FluentTheme.of(context).typography.caption,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (!globals.isPhone) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '内容过滤',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('过滤成人内容 (全局)'),
                                  const SizedBox(height: 4),
                                  Text(
                                    '在新番列表等处隐藏成人内容',
                                    style: FluentTheme.of(context).typography.caption,
                                  ),
                                ],
                              ),
                            ),
                            ToggleSwitch(
                              checked: _filterAdultContent,
                              onChanged: (value) {
                                setState(() {
                                  _filterAdultContent = value;
                                });
                                _saveFilterPreference(value);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '缓存管理',
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('清除图片缓存'),
                                const SizedBox(height: 4),
                                Text(
                                  '清除所有已缓存的图片文件',
                                  style: FluentTheme.of(context).typography.caption,
                                ),
                              ],
                            ),
                          ),
                          Button(
                            onPressed: _clearImageCache,
                            child: const Text('清除'),
                          ),
                        ],
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
