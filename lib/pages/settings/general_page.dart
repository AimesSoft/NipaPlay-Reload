import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

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
    return ListView(
      children: [
        ListTile(
          title: const Text(
            "默认展示页面",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            "选择应用启动后默认显示的页面",
            style: TextStyle(color: Colors.white70),
          ),
          trailing: BlurDropdown<int>(
            dropdownKey: _defaultPageDropdownKey,
            items: [
              DropdownMenuItemData(title: "视频播放", value: 0, isSelected: _defaultPageIndex == 0),
              DropdownMenuItemData(title: "媒体库", value: 1, isSelected: _defaultPageIndex == 1),
              DropdownMenuItemData(title: "新番更新", value: 2, isSelected: _defaultPageIndex == 2),
              DropdownMenuItemData(title: "设置", value: 3, isSelected: _defaultPageIndex == 3),
            ],
            onItemSelected: (index) {
              setState(() {
                _defaultPageIndex = index;
              });
              _saveDefaultPagePreference(index);
            },
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        SwitchListTile(
          title: const Text(
            "过滤成人内容 (全局)",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            "在新番列表等处隐藏成人内容",
            style: TextStyle(color: Colors.white70),
          ),
          value: _filterAdultContent,
          onChanged: (bool value) {
            setState(() {
              _filterAdultContent = value;
            });
            _saveFilterPreference(value);
          },
          activeColor: Colors.white,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: const Color.fromARGB(255, 0, 0, 0),
        ),
        const Divider(color: Colors.white12, height: 1),
        ListTile(
          title: const Text(
            "清除图片缓存",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            "清除所有缓存的图片文件",
            style: TextStyle(color: Colors.white70),
          ),
          trailing: const Icon(Ionicons.trash_outline, color: Colors.white),
          onTap: () async {
            final bool? confirm = await BlurDialog.show<bool>(
              context: context,
              title: '确认清除缓存',
              content: '确定要清除所有缓存的图片文件吗？',
              actions: [
                TextButton(
                  child: const Text(
                    '取消',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  child: const Text(
                    '确定',
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
  }
} 