import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart';

class FluentDialog {
  static Future<T?> show<T>({
    required material.BuildContext context,
    required String title,
    String? content,
    material.Widget? contentWidget,
    List<material.Widget>? actions,
    bool barrierDismissible = true,
  }) async {
    // 简化的实现：将 Material actions 转换为 Fluent UI actions
    List<Widget>? fluentActions;
    if (actions != null) {
      fluentActions = actions.map((action) {
        // 简单的转换逻辑：提取文本和回调
        String buttonText = '确定';
        VoidCallback? onPressed;
        
        if (action is material.ElevatedButton) {
          if (action.child is material.Text) {
            buttonText = (action.child as material.Text).data ?? '确定';
          }
          onPressed = action.onPressed;
          return FilledButton(
            onPressed: onPressed,
            child: Text(buttonText),
          );
        } else if (action is material.TextButton) {
          if (action.child is material.Text) {
            buttonText = (action.child as material.Text).data ?? '取消';
          }
          onPressed = action.onPressed;
          return Button(
            onPressed: onPressed,
            child: Text(buttonText),
          );
        } else if (action is material.OutlinedButton) {
          if (action.child is material.Text) {
            buttonText = (action.child as material.Text).data ?? '取消';
          }
          onPressed = action.onPressed;
          return OutlinedButton(
            onPressed: onPressed,
            child: Text(buttonText),
          );
        }
        
        // 兜底方案：创建一个基本按钮
        return Button(
          onPressed: () {},
          child: Text(buttonText),
        );
      }).toList();
    }

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext context) {
        return ContentDialog(
          title: Text(title),
          content: contentWidget ?? (content != null ? Text(content) : null),
          actions: fluentActions,
        );
      },
    );
  }
}