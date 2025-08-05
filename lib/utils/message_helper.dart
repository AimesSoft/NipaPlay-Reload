import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';

class MessageHelper {
  /// 显示消息提示，自动适配当前UI主题
  static void showMessage(
    material.BuildContext context,
    String message, {
    bool isError = false,
    Duration? duration,
  }) {
    try {
      final uiThemeProvider = Provider.of<UIThemeProvider>(context, listen: false);
      
      if (uiThemeProvider.isFluentUITheme) {
        // 使用 Fluent UI 的 InfoBar
        fluent.displayInfoBar(
          context,
          builder: (context, close) {
            return fluent.InfoBar(
              title: material.Text(message),
              severity: isError 
                  ? fluent.InfoBarSeverity.error 
                  : fluent.InfoBarSeverity.info,
            );
          },
          duration: duration ?? const Duration(seconds: 3),
        );
      } else {
        // 使用 Material 的 SnackBar
        try {
          material.ScaffoldMessenger.of(context).showSnackBar(
            material.SnackBar(
              content: material.Text(message),
              backgroundColor: isError ? material.Colors.red : null,
              duration: duration ?? const Duration(seconds: 3),
            ),
          );
        } catch (e) {
          // 如果 ScaffoldMessenger 不可用，尝试显示对话框
          _showFallbackDialog(context, message, isError);
        }
      }
    } catch (e) {
      // 如果所有方式都失败，尝试显示简单对话框
      _showFallbackDialog(context, message, isError);
    }
  }

  static void _showFallbackDialog(
    material.BuildContext context,
    String message,
    bool isError,
  ) {
    try {
      material.showDialog(
        context: context,
        builder: (context) => material.AlertDialog(
          title: material.Text(isError ? '错误' : '提示'),
          content: material.Text(message),
          actions: [
            material.TextButton(
              onPressed: () => material.Navigator.of(context).pop(),
              child: const material.Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      // 如果连对话框都显示不了，只能输出到控制台
      material.debugPrint('消息提示失败: $message');
    }
  }
}