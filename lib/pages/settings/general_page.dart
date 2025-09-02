import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dropdown.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/settings_item.dart';
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

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _filterAdultContent = prefs.getBool(globalFilterAdultContentKey) ?? true;
        _defaultPageIndex = prefs.getInt(defaultPageIndexKey) ?? 0;
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

            return ListView(
              children: [
                SettingsItem.dropdown(
                  title: "默认展示页面",
                  subtitle: "选择应用启动后默认显示的页面",
                  icon: Ionicons.home_outline,
                  items: [
                    DropdownMenuItemData(title: "主页", value: 0, isSelected: _defaultPageIndex == 0),
                    DropdownMenuItemData(title: "视频播放", value: 1, isSelected: _defaultPageIndex == 1),
                    DropdownMenuItemData(title: "媒体库", value: 2, isSelected: _defaultPageIndex == 2),
                    DropdownMenuItemData(title: "新番更新", value: 3, isSelected: _defaultPageIndex == 3),
                    DropdownMenuItemData(title: "设置", value: 4, isSelected: _defaultPageIndex == 4),
                  ],
                  onChanged: (index) {
                    setState(() {
                      _defaultPageIndex = index;
                    });
                    _saveDefaultPagePreference(index);
                  },
                  dropdownKey: _defaultPageDropdownKey,
                ),
                const Divider(color: Colors.white12, height: 1),
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
                const Divider(color: Colors.white12, height: 1),
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
                const Divider(color: Colors.white12, height: 1),
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
                          child: const Text(
                            '取消',
                            locale:Locale("zh","CN"),
style: TextStyle(color: Colors.white70),
                          ),
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                        TextButton(
                          child: const Text(
                            '确定',
                            locale:Locale("zh","CN"),
style: TextStyle(color: Colors.white),
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
                const Divider(color: Colors.white12, height: 1),
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
  return prefs.getInt(defaultPageIndexKey) ?? 0;
}
 