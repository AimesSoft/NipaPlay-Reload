import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('PlatformInfo', () {
    test('returns valid platform type', () {
      // At least one platform should be detected
      final hasValidPlatform =
          PlatformInfo.isIOS ||
          PlatformInfo.isAndroid ||
          PlatformInfo.isMacOS ||
          PlatformInfo.isWindows ||
          PlatformInfo.isLinux ||
          PlatformInfo.isFuchsia ||
          PlatformInfo.isWeb;

      expect(hasValidPlatform, isTrue);
    });

    test('iOS version methods work correctly', () {
      if (PlatformInfo.isIOS) {
        expect(PlatformInfo.iOSVersion, greaterThanOrEqualTo(0));

        // Version checks should be consistent
        final version = PlatformInfo.iOSVersion;
        if (version >= 26) {
          expect(PlatformInfo.isIOS26OrHigher(), isTrue);
          expect(PlatformInfo.isIOS18OrLower(), isFalse);
        } else if (version > 0 && version < 26) {
          expect(PlatformInfo.isIOS26OrHigher(), isFalse);
          expect(PlatformInfo.isIOS18OrLower(), isTrue);
        }
      } else {
        // Non-iOS platforms should return 0 for iOS version
        expect(PlatformInfo.iOSVersion, equals(0));
        expect(PlatformInfo.isIOS26OrHigher(), isFalse);
        expect(PlatformInfo.isIOS18OrLower(), isFalse);
      }
    });

    test('isIOSVersionInRange works correctly', () {
      if (PlatformInfo.isIOS) {
        final version = PlatformInfo.iOSVersion;
        if (version > 0) {
          expect(PlatformInfo.isIOSVersionInRange(version, version), isTrue);
          expect(
            PlatformInfo.isIOSVersionInRange(version - 1, version + 1),
            isTrue,
          );
          expect(
            PlatformInfo.isIOSVersionInRange(version + 1, version + 2),
            isFalse,
          );
        }
      } else {
        expect(PlatformInfo.isIOSVersionInRange(1, 100), isFalse);
      }
    });

    test('platformDescription returns non-empty string', () {
      expect(PlatformInfo.platformDescription.isNotEmpty, isTrue);
    });

    test('only one primary platform is detected', () {
      // On native platforms, only one platform should be true
      if (!PlatformInfo.isWeb) {
        final platformCount = [
          PlatformInfo.isIOS,
          PlatformInfo.isAndroid,
          PlatformInfo.isMacOS,
          PlatformInfo.isWindows,
          PlatformInfo.isLinux,
          PlatformInfo.isFuchsia,
        ].where((p) => p).length;

        expect(platformCount, equals(1));
      }
    });
  });
}
