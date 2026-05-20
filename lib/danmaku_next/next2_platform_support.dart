import 'package:flutter/foundation.dart';

class Next2PlatformSupport {
  const Next2PlatformSupport._();

  /// Next2 uses Rust for layout on every native app platform.
  /// Web is intentionally excluded because the current Rust runtime is not
  /// packaged as a wasm module for the Flutter web target.
  static bool get isKernelSupported {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// Native texture rendering is required on every non-web platform.
  static bool get isNativeTextureSupported {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  static const String description =
      'NipaPlay Next2\nRust 负责弹幕轨道分配与逐帧布局，渲染走原生 texture（Android / iOS / macOS / Windows / Linux）。Web 不支持。';
}
