import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/settings_storage.dart';

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
    return Scaffold(
      body: ListView(
        children: [
          const SizedBox(height: 20),
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
          const SizedBox(height: 20),
          const AdvancedSettingsSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// 添加一个高级设置部分，包含针对SteamDeck/Linux的特殊渲染修复
class AdvancedSettingsSection extends StatefulWidget {
  const AdvancedSettingsSection({super.key});

  @override
  State<AdvancedSettingsSection> createState() => _AdvancedSettingsSectionState();
}

class _AdvancedSettingsSectionState extends State<AdvancedSettingsSection> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '高级设置',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        // 仅在Linux平台上显示此选项
        if (globals.isLinuxPlatform)
          SwitchListTile(
            title: const Text('永久渲染修复', 
              style: TextStyle(color: Colors.white)
            ),
            subtitle: Text(
              globals.isSteamDeck 
                ? '对SteamDeck进行视频颜色修复，解决窗口模式下颜色失真' 
                : '修复Linux上的视频渲染问题',
              style: const TextStyle(color: Colors.grey),
            ),
            value: globals.needsPermanentRenderLayer,
            onChanged: (value) async {
              setState(() {
                globals.needsPermanentRenderLayer = value;
              });
              // 保存到本地设置
              await SettingsStorage.saveBool('needsPermanentRenderLayer', value);
              // 强制刷新UI
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('设置已更新，下次启动后生效')),
                );
              }
            },
          ),
        
        // 只在渲染层启用时显示渲染模式选择
        if (globals.isLinuxPlatform && globals.needsPermanentRenderLayer)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '渲染层模式',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '如果默认模式无效，请尝试其他模式',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8.0,
                  children: [
                    _buildModeChip(1, '默认模式'),
                    _buildModeChip(2, '带模糊效果'),
                    _buildModeChip(3, '设置菜单模式'),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
  
  Widget _buildModeChip(int mode, String label) {
    final isSelected = globals.renderLayerMode == mode;
    
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.black : Colors.white,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) async {
        if (selected) {
          setState(() {
            globals.renderLayerMode = mode;
          });
          // 保存设置
          await SettingsStorage.saveInt('renderLayerMode', mode);
          // 刷新UI
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('渲染模式已更新，下次启动后生效')),
            );
          }
        }
      },
      backgroundColor: Colors.black12,
      selectedColor: Colors.white,
      checkmarkColor: Colors.black,
    );
  }
} 