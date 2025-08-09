import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dropdown.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';

class UIThemePage extends StatefulWidget {
  const UIThemePage({super.key});

  @override
  State<UIThemePage> createState() => _UIThemePageState();
}

class _UIThemePageState extends State<UIThemePage> {
  final GlobalKey _themeDropdownKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Consumer<UIThemeProvider>(
      builder: (context, uiThemeProvider, child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                const Text(
                  '控件主题',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '选择应用的控件主题风格',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),

                // 主题选择
                _buildThemeSelector(uiThemeProvider),
                
                const SizedBox(height: 24),
                
                // 主题预览区域
                _buildThemePreview(uiThemeProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemeSelector(UIThemeProvider uiThemeProvider) {
    return Row(
      children: [
        const Text(
          '主题风格',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: BlurDropdown<UIThemeType>(
            dropdownKey: _themeDropdownKey,
            items: UIThemeType.values.map((theme) {
              return DropdownMenuItemData<UIThemeType>(
                title: uiThemeProvider.getThemeName(theme),
                value: theme,
                isSelected: uiThemeProvider.currentTheme == theme,
              );
            }).toList(),
            onItemSelected: (UIThemeType newTheme) {
              if (uiThemeProvider.currentTheme != newTheme) {
                _showThemeChangeConfirmDialog(newTheme, uiThemeProvider);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildThemePreview(UIThemeProvider uiThemeProvider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withOpacity(0.1),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '当前主题预览',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          _buildThemeDescription(uiThemeProvider.currentTheme),
        ],
      ),
    );
  }

  Widget _buildThemeDescription(UIThemeType theme) {
    switch (theme) {
      case UIThemeType.nipaplay:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NipaPlay 主题',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '• 磨砂玻璃效果\n• 渐变背景\n• 圆角设计\n• 适合多媒体应用',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        );
      case UIThemeType.fluentUI:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fluent UI 主题',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '• Microsoft 设计语言\n• 亚克力材质\n• 现代化界面\n• 统一的交互体验',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        );
    }
  }

  /// 显示主题切换确认弹窗
  void _showThemeChangeConfirmDialog(UIThemeType newTheme, UIThemeProvider provider) {
    BlurDialog.show(
      context: context,
      title: '主题切换提示',
      content: '切换到 ${provider.getThemeName(newTheme)} 主题需要重启应用才能完全生效。\n\n是否要立即重启应用？',
      barrierDismissible: true,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () async {
            // 先保存主题设置
            await provider.setTheme(newTheme);
            Navigator.of(context).pop();
            // 退出应用
            _exitApplication();
          },
          child: const Text('重启应用', style: TextStyle(color: Colors.white)),
        ),
      ],
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
      BlurSnackBar.show(context, '请手动刷新页面以应用新主题');
    }
  }


}