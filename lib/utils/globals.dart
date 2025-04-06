// globals.dart
library globals;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

//////全局变量/////
double mobileThreshold = 550;
double blurPower = 25;
// ignore: non_constant_identifier_names
String Appversion = "1.0.0";
String backgroundImageMode = "看板娘"; // 添加背景图像模式变量
String customBackgroundPath = 'assets/main_image.png'; // 添加自定义背景图片路径变量
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
  //移动平台
  if (!kIsWeb) {
    return Platform.isIOS || Platform.isAndroid;
  }else{
    return false;
  }
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
  //没有三大键的设备
  return kIsWeb ||
      !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS;
}
bool get winLinDesktop {
  //windows和linux桌面平台
  return !kIsWeb && (Platform.isWindows || Platform.isLinux);
}
bool get isDesktop {
  //windows和linux和macOS桌面平台
  return !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
}
//////设备类型判断/////
///
//////文本//////
String settingTitle = "设置";
String playVideoTitle = "视频播放";
String libraryTitle = "媒体库";
//////文本//////