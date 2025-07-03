import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../utils/globals.dart' as globals;

class BlurDialog {
  static Future<T?> show<T>({
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
        
        // 使用预计算的对话框宽度和高度
        final dialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
        final dialogHeight = globals.DialogSizes.generalDialogHeight;
        
        // 获取键盘高度，用于动态调整底部间距
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        
        return Dialog(
          backgroundColor: Colors.transparent,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: GlassmorphicContainer(
              width: dialogWidth,
              height: dialogHeight,
              borderRadius: 20,
              blur: 20,
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
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 固定标题区域
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // 可滚动内容区域
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (content != null)
                              Text(
                                content,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                              ),
                            if (contentWidget != null)
                              contentWidget,
                          ],
                        ),
                      ),
                    ),
                    
                    // 固定按钮区域
                    if (actions != null) ...[
                      const SizedBox(height: 16),
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
                        // 正常横向布局
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: actions
                              .map((action) => Padding(
                                    padding: const EdgeInsets.only(left: 8),
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
        );
      },
    );
  }
} 