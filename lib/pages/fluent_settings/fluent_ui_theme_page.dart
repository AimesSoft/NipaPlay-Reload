import 'package:flutter/material.dart' as material;
import 'package:flutter/foundation.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_info_bar.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';

class FluentUIThemePage extends StatefulWidget {
  const FluentUIThemePage({super.key});

  @override
  State<FluentUIThemePage> createState() => _FluentUIThemePageState();
}

class _FluentUIThemePageState extends State<FluentUIThemePage> {
  @override
  Widget build(BuildContext context) {
    return Consumer<UIThemeProvider>(
      builder: (context, uiThemeProvider, child) {
        return ScaffoldPage(
          header: const PageHeader(
            title: Text('界面主题'),
          ),
          content: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 主题选择卡片
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '界面风格',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '选择应用的界面主题风格',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                        const SizedBox(height: 16),
                        
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('当前主题'),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ComboBox<UIThemeType>(
                                value: uiThemeProvider.currentTheme,
                                items: UIThemeType.values.map((theme) {
                                  return ComboBoxItem<UIThemeType>(
                                    value: theme,
                                    child: Text(uiThemeProvider.getThemeName(theme)),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null && uiThemeProvider.currentTheme != value) {
                                    _showThemeChangeConfirmDialog(value, uiThemeProvider);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 主题预览卡片
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前主题预览',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                        const SizedBox(height: 16),
                        _buildThemePreview(uiThemeProvider.currentTheme),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 说明信息
                InfoBar(
                  title: const Text('说明'),
                  content: const Text('Fluent UI 主题仅在桌面端生效，移动端将继续使用 NipaPlay 主题以保持最佳体验。'),
                  severity: InfoBarSeverity.info,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemePreview(UIThemeType theme) {
    switch (theme) {
      case UIThemeType.nipaplay:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        colors: [
                          material.Colors.purple,
                          material.Colors.blue,
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NipaPlay 主题'),
                      SizedBox(height: 4),
                      Text('现代化的磨砂玻璃设计风格'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '特色功能：',
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: 8),
            const Text('• 磨砂玻璃效果\n• 渐变色彩\n• 圆角设计\n• 动态模糊'),
          ],
        );
        
      case UIThemeType.fluentUI:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: const Color(0xFF0078D4),
                    ),
                    child: const Icon(
                      FluentIcons.app_icon_default,
                      color: material.Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fluent UI 主题'),
                      SizedBox(height: 4),
                      Text('微软 Fluent Design 设计语言'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '特色功能：',
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: 8),
            const Text('• 亚克力材质\n• 统一的导航\n• 现代化控件\n• 桌面端优化'),
          ],
        );
    }
  }

  /// 显示主题切换确认弹窗
  void _showThemeChangeConfirmDialog(UIThemeType newTheme, UIThemeProvider provider) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return ContentDialog(
          title: const Text('主题切换提示'),
          content: Text('切换到 ${provider.getThemeName(newTheme)} 主题需要重启应用才能完全生效。\n\n是否要立即重启应用？'),
          actions: [
            Button(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                // 先保存主题设置
                await provider.setTheme(newTheme);
                Navigator.of(context).pop();
                // 退出应用
                _exitApplication();
              },
              child: const Text('重启应用'),
            ),
          ],
        );
      },
    );
  }

  /// 退出应用
  void _exitApplication() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // 移动平台
      exit(0);
    } else if (!kIsWeb) {
      // 桌面平台
      windowManager.close();
    } else {
      // Web 平台提示用户手动刷新
      FluentInfoBar.show(
        context,
        '请手动刷新页面以应用新主题',
        severity: InfoBarSeverity.info,
      );
    }
  }


}