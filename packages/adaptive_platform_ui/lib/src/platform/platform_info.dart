import 'dart:io';
import 'package:flutter/foundation.dart';

enum PlatformOverride {
  ios,
  android,
  macos,
  windows,
  linux,
  fuchsia,
  web,
  other,
}

/// Provides platform detection and iOS version information
///
/// This class helps determine the current platform and iOS version
/// to enable adaptive widget rendering based on platform capabilities.
class PlatformInfo {
  static PlatformOverride? _overridePlatform;
  static int? _overrideIOSVersion;

  static void setPlatformOverride(
    PlatformOverride? platform, {
    int? iosVersion,
  }) {
    _overridePlatform = platform;
    _overrideIOSVersion = iosVersion;
  }

  static void clearPlatformOverride() {
    _overridePlatform = null;
    _overrideIOSVersion = null;
  }

  /// Returns true if the current platform is iOS
  static bool get isIOS {
    if (_overridePlatform != null) {
      return _overridePlatform == PlatformOverride.ios;
    }
    return !kIsWeb && Platform.isIOS;
  }

  /// Returns true if the current platform is Android
  static bool get isAndroid {
    if (_overridePlatform != null) {
      return _overridePlatform == PlatformOverride.android;
    }
    return !kIsWeb && Platform.isAndroid;
  }

  /// Returns true if the current platform is macOS
  static bool get isMacOS {
    if (_overridePlatform != null) {
      return _overridePlatform == PlatformOverride.macos;
    }
    return !kIsWeb && Platform.isMacOS;
  }

  /// Returns true if the current platform is Windows
  static bool get isWindows {
    if (_overridePlatform != null) {
      return _overridePlatform == PlatformOverride.windows;
    }
    return !kIsWeb && Platform.isWindows;
  }

  /// Returns true if the current platform is Linux
  static bool get isLinux {
    if (_overridePlatform != null) {
      return _overridePlatform == PlatformOverride.linux;
    }
    return !kIsWeb && Platform.isLinux;
  }

  /// Returns true if the current platform is Fuchsia
  static bool get isFuchsia {
    if (_overridePlatform != null) {
      return _overridePlatform == PlatformOverride.fuchsia;
    }
    return !kIsWeb && Platform.isFuchsia;
  }

  /// Returns true if running on web
  static bool get isWeb {
    if (_overridePlatform != null) {
      return _overridePlatform == PlatformOverride.web;
    }
    return kIsWeb;
  }

  /// Returns the iOS major version number
  ///
  /// Returns 0 if not running on iOS or if version cannot be determined.
  /// Example: For iOS 26.1.2, returns 26
  static int get iOSVersion {
    if (_overridePlatform == PlatformOverride.ios) {
      return _overrideIOSVersion ?? 18;
    }
    if (!isIOS) return 0;

    try {
      final version = Platform.operatingSystemVersion;
      // Extract major version from string like "Version 26.1.2 (Build 20A123)"
      final match = RegExp(r'Version (\d+)').firstMatch(version);
      if (match != null) {
        return int.parse(match.group(1)!);
      }

      // Fallback: try to parse the first number in the version string
      final fallbackMatch = RegExp(r'(\d+)').firstMatch(version);
      if (fallbackMatch != null) {
        return int.parse(fallbackMatch.group(1)!);
      }
    } catch (e) {
      debugPrint('Error parsing iOS version: $e');
    }

    return 0;
  }

  /// Returns true if iOS version is 26 or higher
  ///
  /// This is used to determine if iOS 26+ specific widgets should be used.
  static bool isIOS26OrHigher() {
    return isIOS && iOSVersion >= 26;
  }

  /// Returns true if iOS version is 18 or lower (pre-iOS 26)
  ///
  /// This is used to determine if legacy Cupertino widgets should be used.
  static bool isIOS18OrLower() {
    return isIOS && iOSVersion > 0 && iOSVersion < 26;
  }

  /// Returns true if iOS version is in a specific range
  ///
  /// [min] - Minimum iOS version (inclusive)
  /// [max] - Maximum iOS version (inclusive)
  static bool isIOSVersionInRange(int min, int max) {
    return isIOS && iOSVersion >= min && iOSVersion <= max;
  }

  /// Returns a human-readable platform description
  static String get platformDescription {
    if (isIOS) return 'iOS $iOSVersion';
    if (isAndroid) return 'Android';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    if (isFuchsia) return 'Fuchsia';
    if (isWeb) return 'Web';
    return 'Unknown';
  }
}
