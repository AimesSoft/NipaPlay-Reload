import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_dialog.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

class BlurDialog {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    // 根据主题设置选择使用哪个dialog
    final uiThemeProvider = Provider.of<UIThemeProvider>(context, listen: false);
    
    if (uiThemeProvider.isFluentUITheme) {
      return FluentDialog.show<T>(
        context: context,
        title: title,
        content: content,
        contentWidget: contentWidget,
        actions: actions,
        barrierDismissible: barrierDismissible,
      );
    }
    
    // 默认使用 NipaPlay 主题
    return _showNipaplayDialog<T>(
      context: context,
      title: title,
      content: content,
      contentWidget: contentWidget,
      actions: actions,
      barrierDismissible: barrierDismissible,
    );
  }

  static Future<T?> _showNipaplayDialog<T>({
    required BuildContext context,
    required String title,
    String? content,
    Widget? contentWidget,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        final screenSize = MediaQuery.of(context).size;
        
        // 使用预计算的对话框宽度
        final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
        
        // 获取键盘高度，用于动态调整底部间距
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        
                return Dialog(
          backgroundColor: Colors.transparent,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: screenSize.height * 0.8, // 最大高度限制
                maxWidth: dialogWidth, // 最大宽度限制
              ),
              child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.15),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0,
                        sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min, // 关键：让Column根据内容自适应
                          crossAxisAlignment: CrossAxisAlignment.center, // 居中对齐
                          children: [
                            // 标题区域 - 居中
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center, // 标题居中
                            ),
                            const SizedBox(height: 20),
                            
                            // 内容区域 - 居中，真正的内容自适应
                            if (content != null)
                              Text(
                                content,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center, // 内容文本居中
                              ),
                            if (contentWidget != null)
                              contentWidget,
                            
                            // 按钮区域 - 底部居中
                            if (actions != null) ...[
                              const SizedBox(height: 24),
                              if ((globals.isPhone && !globals.isTablet) && actions.length > 2)
                                // 手机垂直布局
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: actions.map((action) => 
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: action,
                                    )
                                  ).toList(),
                                )
                              else
                                // 正常横向布局 - 居中
                                Row(
                                  mainAxisSize: MainAxisSize.min, // 让Row也根据内容自适应
                                  mainAxisAlignment: MainAxisAlignment.center, // 按钮居中
                                  children: actions
                                      .map((action) => Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            child: action,
                                          ))
                                      .toList(),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ),
          ),
        );
      },
    );
  }
} 