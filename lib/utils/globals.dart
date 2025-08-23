// globals.dart
library globals;
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final strokeWidth = isPhone ? 0.7 : 1.0;
//////全局变量/////
double mobileThreshold = 550;
// ignore: non_constant_identifier_names
String Appversion = "1.0.0";
String backgroundImageMode = "看板娘"; // 添加背景图像模式变量
String customBackgroundPath = 'assets/images/main_image.png'; // 添加自定义背景图片路径变量
//////全局变量/////
///
//////设备类型判断/////
bool get isMobile {
  // 获取屏幕宽度
  // ignore: deprecated_member_use
  double screenWidth = WidgetsBinding.instance.window.physicalSize.width / WidgetsBinding.instance.window.devicePixelRatio;
    // 排除平板设备，通常平板设备的宽度大于 600
    return screenWidth < mobileThreshold;
}

bool get isPhone {
  if (kIsWeb) {
    // 对于Web平台，我们总是认为它需要采用手机式的响应式布局逻辑，
    // 这样就可以直接复用 isTablet 来判断横竖屏。
    return true;
  }
  //移动平台
  return Platform.isIOS || Platform.isAndroid;
}

// 判断是否为平板设备（屏幕宽度大于高度的移动设备）
bool get isTablet {
  // 由于 isPhone 对于移动端和Web端现在都返回 true，
  // 这个 getter 现在等同于一个纯粹的横屏方向检测器。
  if (!isPhone) return false;
  final window = WidgetsBinding.instance.window;
  final size = window.physicalSize / window.devicePixelRatio;
  return size.width > size.height;
}
bool get isTouch {
  //移动平台
  if (kIsWeb) {
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  } else {
    return Platform.isIOS || Platform.isAndroid;
  }
}
bool get noMenuButton {
  if (kIsWeb) {
    return true;
  }
  //没有三大键的设备
  return !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS;
}
bool get winLinDesktop {
  //windows和linux桌面平台
  return !kIsWeb && (Platform.isWindows || Platform.isLinux);
}
bool get isDesktop {
  //windows和linux和macOS桌面平台
  return !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
}

bool get isDesktopOrTablet {
  //桌面平台或平板设备（横屏移动设备）
  return isDesktop || isTablet;
}
//////设备类型判断/////
///
/// 对话框尺寸管理
class DialogSizes {
  static double _screenHeight = 0.0;
  static double _screenWidth = 0.0;
  static bool _initialized = false;
  
  /// 预设的对话框高度 - 在应用启动时计算
  static double loginDialogHeight = 400.0;
  static double serverDialogHeight = 500.0;
  static double generalDialogHeight = 350.0;
  
  /// 初始化对话框尺寸（在应用启动时调用）
  static void initialize(double screenWidth, double screenHeight) {
    if (_initialized) return;
    
    _screenWidth = screenWidth;
    _screenHeight = screenHeight;
    _initialized = true;
    
    // 计算适合的对话框高度
    final isLandscape = screenWidth > screenHeight;
    final shortestSide = screenWidth < screenHeight ? screenWidth : screenHeight;
    final isPhone = shortestSide < 600;
    
    if (isPhone) {
      // 手机设备
      if (isLandscape) {
        // 手机横屏：确保不超过屏幕高度的90%
        final maxHeight = screenHeight * 0.9;
        loginDialogHeight = (screenHeight * 0.70).clamp(250.0, maxHeight);
        serverDialogHeight = (screenHeight * 0.80).clamp(300.0, maxHeight);
        generalDialogHeight = (screenHeight * 0.65).clamp(220.0, maxHeight);
      } else {
        // 手机竖屏：标准高度，有足够空间
        loginDialogHeight = (screenHeight * 0.5).clamp(380.0, 450.0);
        serverDialogHeight = (screenHeight * 0.6).clamp(500.0, 600.0);
        generalDialogHeight = (screenHeight * 0.45).clamp(350.0, 400.0);
      }
    } else {
      // 平板/桌面设备：固定高度
      loginDialogHeight = 450.0;
      serverDialogHeight = 600.0;
      generalDialogHeight = 400.0;
    }
    
    print('[DialogSizes] 初始化完成 - 屏幕: ${screenWidth}x$screenHeight, 登录框: $loginDialogHeight, 服务器框: $serverDialogHeight');
  }
  
  /// 获取适合的对话框宽度
  static double getDialogWidth(double screenWidth) {
    final shortestSide = screenWidth < _screenHeight ? screenWidth : _screenHeight;
    final isPhone = shortestSide < 600;
    
    if (isPhone) {
      return (screenWidth * 0.9).clamp(300.0, 450.0);
    } else if (shortestSide < 900) {
      return (screenWidth * 0.7).clamp(400.0, 600.0);
    } else {
      return 500.0;
    }
  }
  
  /// 检查是否已初始化
  static bool get isInitialized => _initialized;
}