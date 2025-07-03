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
        final isPortrait = screenSize.height > screenSize.width;
        
        // 响应式宽度计算
        double dialogWidth;
        if (globals.isPhone) {
          // 手机设备：使用屏幕宽度的90%，最小280，最大450
          dialogWidth = (screenSize.width * 0.9).clamp(280.0, 450.0);
        } else if (globals.isTablet) {
          // 平板设备：使用屏幕宽度的70%，最小400，最大600
          dialogWidth = (screenSize.width * 0.7).clamp(400.0, 600.0);
        } else {
          // 桌面设备：固定400
          dialogWidth = 400.0;
        }
        
        // 响应式最大高度计算
        final maxHeight = screenSize.height * 0.8; // 最大不超过屏幕高度的80%
        
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogWidth,
              maxHeight: maxHeight,
            ),
            child: GlassmorphicContainer(
              width: dialogWidth,
              height: contentWidget != null ? maxHeight : 200,
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
                padding: EdgeInsets.all(globals.isPhone ? 16 : 20),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: globals.isPhone ? 18 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: globals.isPhone ? 16 : 20),
                      
                      // 内容区域 - 可滚动
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (content != null)
                                Text(
                                  content,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: globals.isPhone ? 14 : 16,
                                    height: 1.4, // 增加行高提升可读性
                                  ),
                                ),
                              if (contentWidget != null)
                                contentWidget,
                            ],
                          ),
                        ),
                      ),
                      
                      // 按钮区域
                      if (actions != null) ...[
                        SizedBox(height: globals.isPhone ? 16 : 20),
                        // 在手机设备上，如果按钮较多，使用垂直布局
                        if (globals.isPhone && actions.length > 2)
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
                          // 正常的横向布局
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
          ),
        );
      },
    );
  }
} 