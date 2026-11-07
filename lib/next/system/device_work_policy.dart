import 'dart:io';

/// 无界面版运行于桌面系统；移动设备与电视不能在后台持续广播。
abstract final class DeviceWorkPolicy {
  static bool get foregroundDiscovery => const {
        'ios',
        'android',
        'tvos',
        'ohos'
      }.contains(Platform.operatingSystem);
  static bool get downloads =>
      const {'macos', 'linux', 'windows'}.contains(Platform.operatingSystem);
}
