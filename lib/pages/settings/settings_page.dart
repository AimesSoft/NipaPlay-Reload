import 'package:flutter/material.dart';
import 'package:your_app/globals.dart';
import 'package:your_app/settings_storage.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ... existing sections ...
            
            const SizedBox(height: 20),
            
            // 添加高级设置部分
            const AdvancedSettingsSection(),
            
            const SizedBox(height: 20),
            
            // 其他现有部分...
          ],
        ),
      ),
    );
  }
}

// 添加一个高级设置部分，包含针对SteamDeck/Linux的特殊渲染修复
class AdvancedSettingsSection extends StatelessWidget {
  const AdvancedSettingsSection({super.key});

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
            ),
          ),
        ),
        // 仅在Linux平台上显示此选项
        if (globals.isLinuxPlatform)
          SwitchListTile(
            title: const Text('永久渲染修复'),
            subtitle: Text(
              globals.isSteamDeck 
                ? '对SteamDeck进行视频颜色修复，解决窗口模式下颜色失真' 
                : '修复Linux上的视频渲染问题'
            ),
            value: globals.needsPermanentRenderLayer,
            onChanged: (value) async {
              globals.needsPermanentRenderLayer = value;
              // 保存到本地设置
              await SettingsStorage.saveBool('needsPermanentRenderLayer', value);
              // 强制刷新UI
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('设置已更新，下次启动后生效')),
                );
              }
            },
          ),
      ],
    );
  }
} 