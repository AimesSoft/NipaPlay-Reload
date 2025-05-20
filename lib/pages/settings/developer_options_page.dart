import 'package:flutter/material.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// 开发者选项设置页面
class DeveloperOptionsPage extends StatelessWidget {
  const DeveloperOptionsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<DeveloperOptionsProvider>(
      builder: (context, devOptions, child) {
        return ListView(
          children: [
            // 显示系统资源监控开关（所有平台可用）
            SwitchListTile(
              title: const Text(
                '显示系统资源监控',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                '在界面右上角显示CPU、内存和帧率信息',
                style: TextStyle(color: Colors.white70),
              ),
              value: devOptions.showSystemResources,
              onChanged: (bool value) {
                devOptions.setShowSystemResources(value);
              },
              activeColor: Colors.white,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color.fromARGB(255, 0, 0, 0),
            ),
            
            const Divider(color: Colors.white12, height: 1),
            
            // 这里可以添加更多开发者选项
          ],
        );
      },
    );
  }
} 