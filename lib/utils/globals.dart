// globals.dart
library globals;
import 'dart:io';
import 'package:flutter/foundation.dart';
//////全局变量/////
int globalVariable = 10;
bool modeSwitch = false;
bool isDarkModeValue = false;
String baseLightColor = "#FFFFFF"; // 亮色基础颜色
bool sidebarBlurEffect = false;
String backGirl = "assets/backgirl.png";
String backEmpty = "assets/backempty.png";
String backUp = backEmpty;
String backImage = backGirl;
int backImageNumber = 0;
//////全局变量/////
///
//////设备类型判断/////
bool get isMobile {
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
//////文本//////