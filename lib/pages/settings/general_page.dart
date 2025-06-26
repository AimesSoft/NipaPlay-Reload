import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/widgets/file_association_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Define the key for SharedPreferences
const String globalFilterAdultContentKey = 'global_filter_adult_content';

class GeneralPage extends StatefulWidget {
  const GeneralPage({super.key});

  @override
  State<GeneralPage> createState() => _GeneralPageState();
}

class _GeneralPageState extends State<GeneralPage> {
  bool _filterAdultContent = true;

  @override
  void initState() {
    super.initState();
    _loadFilterPreference();
  }

  Future<void> _loadFilterPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _filterAdultContent = prefs.getBool(globalFilterAdultContentKey) ?? true;
      });
    }
  }

  Future<void> _saveFilterPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(globalFilterAdultContentKey, value);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // 文件关联设置
        const FileAssociationSettings(),
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
          //secondary: Icon(Ionicons.eye_off_outline, color: _filterAdultContent ? const Color.fromARGB(255, 255, 255, 255) : const Color.fromARGB(184, 236, 236, 236)),
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
      ],
    );
  }
} 