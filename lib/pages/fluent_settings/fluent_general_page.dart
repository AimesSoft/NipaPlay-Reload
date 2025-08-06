import 'package:fluent_ui/fluent_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_info_bar.dart';

// 定义SharedPreferences键值
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

  final List<String> _pageNames = [
    '主页',
    '视频播放',
    '媒体库',
    '新番更新',
    '设置',
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _filterAdultContent = prefs.getBool(globalFilterAdultContentKey) ?? true;
          _defaultPageIndex = prefs.getInt(defaultPageIndexKey) ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
        content: Center(
          child: ProgressRing(),
        ),
      );
    }

    return ScaffoldPage(
      header: const PageHeader(
        title: Text('通用设置'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // 默认页面设置
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
            
            // 内容过滤设置
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
            
            // 缓存管理
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
    );
  }
}