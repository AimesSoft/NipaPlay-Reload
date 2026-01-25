import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/services/desktop_exit_preferences.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Define the key for SharedPreferences
const String globalFilterAdultContentKey = 'global_filter_adult_content';
const String defaultPageIndexKey = 'default_page_index';

class GeneralPage extends StatefulWidget {
  const GeneralPage({super.key});

  @override
  State<GeneralPage> createState() => _GeneralPageState();
}

class _GeneralPageState extends State<GeneralPage> {
  bool _filterAdultContent = true;
  int _defaultPageIndex = 0;
  final GlobalKey _defaultPageDropdownKey = GlobalKey();
  DesktopExitBehavior _desktopExitBehavior = DesktopExitBehavior.askEveryTime;
  final GlobalKey _desktopExitBehaviorDropdownKey = GlobalKey();

  // 生成默认页面选项
  List<DropdownMenuItemData<int>> _getDefaultPageItems() {
    List<DropdownMenuItemData<int>> items = [
      DropdownMenuItemData(title: "主页", value: 0, isSelected: _defaultPageIndex == 0),
      DropdownMenuItemData(title: "视频播放", value: 1, isSelected: _defaultPageIndex == 1),
      DropdownMenuItemData(title: "媒体库", value: 2, isSelected: _defaultPageIndex == 2),
    ];

    items.add(DropdownMenuItemData(title: "个人中心", value: 3, isSelected: _defaultPageIndex == 3));

    return items;
  }

  List<DropdownMenuItemData<DesktopExitBehavior>> _getDesktopExitItems() {
    return [
      DropdownMenuItemData(
        title: "每次询问",
        value: DesktopExitBehavior.askEveryTime,
        isSelected: _desktopExitBehavior == DesktopExitBehavior.askEveryTime,
      ),
      DropdownMenuItemData(
        title: "最小化到系统托盘",
        value: DesktopExitBehavior.minimizeToTrayOrTaskbar,
        isSelected:
            _desktopExitBehavior == DesktopExitBehavior.minimizeToTrayOrTaskbar,
      ),
      DropdownMenuItemData(
        title: "直接退出",
        value: DesktopExitBehavior.closePlayer,
        isSelected: _desktopExitBehavior == DesktopExitBehavior.closePlayer,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final desktopExitBehavior = await DesktopExitPreferences.load();
    if (mounted) {
      setState(() {
        _filterAdultContent = prefs.getBool(globalFilterAdultContentKey) ?? true;
        var storedIndex = prefs.getInt(defaultPageIndexKey) ?? 0;
        _desktopExitBehavior = desktopExitBehavior;

        if (storedIndex < 0) {
          storedIndex = 0;
        } else if (storedIndex > 3) {
          storedIndex = 3;
        }

        _defaultPageIndex = storedIndex;
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

  Future<void> _saveDesktopExitBehavior(DesktopExitBehavior behavior) async {
    await DesktopExitPreferences.save(behavior);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppearanceSettingsProvider>(
      builder: (context, appearanceSettings, child) {
        return FutureBuilder<int>(
          future: _loadDefaultPageIndex(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            _defaultPageIndex = snapshot.data ?? 0;

            final colorScheme = Theme.of(context).colorScheme;

            return ListView(
              children: [
                if (globals.isDesktop)
                SettingsItem.dropdown(
                  title: "关闭窗口时",
                  subtitle: "设置关闭按钮的默认行为，可随时修改“记住我的选择”",
                  icon: Ionicons.close_outline,
                  items: _getDesktopExitItems(),
                  onChanged: (behavior) {
                    setState(() {
                      _desktopExitBehavior = behavior as DesktopExitBehavior;
                    });
                    _saveDesktopExitBehavior(behavior as DesktopExitBehavior);
                  },
                  dropdownKey: _desktopExitBehaviorDropdownKey,
                ),
                if (globals.isDesktop)
                Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.dropdown(
                  title: "默认展示页面",
                  subtitle: "选择应用启动后默认显示的页面",
                  icon: Ionicons.home_outline,
                  items: _getDefaultPageItems(),
                  onChanged: (index) {
                    setState(() {
                      _defaultPageIndex = index;
                    });
                    _saveDefaultPagePreference(index);
                  },
                  dropdownKey: _defaultPageDropdownKey,
                ),
                Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.dropdown(
                  title: "番剧卡片点击行为",
                  subtitle: "选择点击番剧卡片后默认展示的内容",
                  icon: Ionicons.card_outline,
                  items: [
                    DropdownMenuItemData(
                      title: "简介",
                      value: AnimeCardAction.synopsis,
                      isSelected: appearanceSettings.animeCardAction == AnimeCardAction.synopsis,
                    ),
                    DropdownMenuItemData(
                      title: "剧集列表",
                      value: AnimeCardAction.episodeList,
                      isSelected: appearanceSettings.animeCardAction == AnimeCardAction.episodeList,
                    ),
                  ],
                  onChanged: (action) {
                    appearanceSettings.setAnimeCardAction(action);
                  },
                ),
                Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                if (!globals.isPhone)
                SettingsItem.toggle(
                  title: "过滤成人内容 (全局)",
                  subtitle: "在新番列表等处隐藏成人内容",
                  icon: Ionicons.shield_outline,
                  value: _filterAdultContent,
                  onChanged: (bool value) {
                    setState(() {
                      _filterAdultContent = value;
                    });
                    _saveFilterPreference(value);
                  },
                ),
                Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.button(
                  title: "清除图片缓存",
                  subtitle: "清除所有缓存的图片文件",
                  icon: Ionicons.trash_outline,
                  trailingIcon: Ionicons.trash_outline,
                  isDestructive: true,
                  onTap: () async {
                    final bool? confirm = await BlurDialog.show<bool>(
                      context: context,
                      title: '确认清除缓存',
                      content: '确定要清除所有缓存的图片文件吗？',
                      actions: [
                        TextButton(
                          child: Text(
                            '取消',
                            locale:Locale("zh-Hans","zh"),
style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                          ),
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                        TextButton(
                          child: Text(
                            '确定',
                            locale:Locale("zh-Hans","zh"),
style: TextStyle(color: colorScheme.onSurface),
                          ),
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ],
                    );

                    if (confirm == true) {
                      try {
                        await ImageCacheManager.instance.clearCache();
                        if (context.mounted) {
                          BlurSnackBar.show(context, '图片缓存已清除');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          BlurSnackBar.show(context, '清除缓存失败: $e');
                        }
                      }
                    }
                  },
                ),
                Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
              ],
            );
          },
        );
      },
    );
  }
}

Future<int> _loadDefaultPageIndex() async {
  final prefs = await SharedPreferences.getInstance();
  final index = prefs.getInt(defaultPageIndexKey) ?? 0;
  if (index < 0) {
    return 0;
  }
  if (index > 3) {
    return 3;
  }
  return index;
}
 
