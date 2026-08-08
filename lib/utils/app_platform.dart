
// lib/utils/app_platform.dart
// 表示当前运行的应用平台

import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/platform_utils.dart' as io;


/// 表示当前运行的应用平台
enum AppPlatform {
  linux,
  windows,
  macOS,
  android,
  web,
  iOS,
  unknown;

  /// 获取当前运行的应用平台
  static AppPlatform get current {

    if (kIsWeb                ) return AppPlatform.web;
    if (io.Platform.isWindows ) return AppPlatform.windows;
    if (io.Platform.isMacOS   ) return AppPlatform.macOS;
    if (io.Platform.isLinux   ) return AppPlatform.linux;
    if (io.Platform.isAndroid ) return AppPlatform.android;
    if (io.Platform.isIOS     ) return AppPlatform.iOS;

    return AppPlatform.unknown;
  }

  bool get isDesktop => this == AppPlatform.windows || this == AppPlatform.macOS || this == AppPlatform.linux;
  bool get supportsExternalPlayer => isDesktop;
}
