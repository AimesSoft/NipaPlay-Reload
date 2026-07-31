import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/platform_identity.dart';

class Next2PlatformSupport {
  const Next2PlatformSupport._();

  /// Next2 uses Rust for layout on every native app platform.
  /// Web is intentionally excluded because the current Rust runtime is not
  /// packaged as a wasm module for the Flutter web target.
  static bool get isKernelSupported {
    if (kIsWeb || isTvOS) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.fuchsia:
        return false;
      default:
        // HarmonyOS packages the Rust layout APIs, but Next2/DFM+ currently
        // require the native texture renderer as well.
        return false;
    }
  }

  /// Native texture rendering is required on every non-web platform.
  static bool get isNativeTextureSupported {
    if (kIsWeb || isTvOS) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.fuchsia:
        return false;
      default:
        // HarmonyOS still needs a TextureRegistry + native surface bridge for
        // the Rust/wgpu renderer.
        return false;
    }
  }

  static const String description =
      'NipaPlay Next2\nRust 负责弹幕轨道分配与逐帧布局，渲染走原生 texture（Android / iOS / macOS / Windows / Linux）。Web 不支持。';
}
