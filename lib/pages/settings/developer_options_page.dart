import 'package:flutter/material.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/pages/settings/debug_log_viewer_page.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:glassmorphism/glassmorphism.dart';

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
            
            // 调试日志收集开关
            SwitchListTile(
              title: const Text(
                '调试日志收集',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                '收集应用的所有打印输出，用于调试和问题诊断',
                style: TextStyle(color: Colors.white70),
              ),
              value: devOptions.enableDebugLogCollection,
              onChanged: (bool value) async {
                await devOptions.setEnableDebugLogCollection(value);
                
                // 根据设置控制日志服务
                final logService = DebugLogService();
                if (value) {
                  logService.startCollecting();
                } else {
                  logService.stopCollecting();
                }
              },
              activeColor: Colors.white,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color.fromARGB(255, 0, 0, 0),
            ),
            
            const Divider(color: Colors.white12, height: 1),
            
            // 终端输出查看器
            ListTile(
              title: const Text(
                '终端输出',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                '查看应用的所有打印输出，支持搜索、过滤和复制',
                style: TextStyle(color: Colors.white70),
              ),
              trailing: const Icon(Ionicons.chevron_forward_outline, color: Colors.white),
              onTap: () {
                _openDebugLogViewer(context);
              },
            ),
            
            const Divider(color: Colors.white12, height: 1),
            
            // 这里可以添加更多开发者选项
          ],
        );
      },
    );
  }

  void _openDebugLogViewer(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierLabel: '关闭终端输出',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: GlassmorphicContainer(
            width: MediaQuery.of(context).size.width * 0.95,
            height: MediaQuery.of(context).size.height * 0.85,
            borderRadius: 12,
            blur: 25,
            alignment: Alignment.center,
            border: 1,
            linearGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.05),
              ],
            ),
            borderGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.5),
                Colors.white.withOpacity(0.2),
              ],
            ),
            child: Column(
              children: [
                // 标题栏
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.terminal,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '终端输出',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white70,
                          size: 24,
                        ),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
                // 日志查看器内容
                const Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    child: DebugLogViewerPage(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }
} 