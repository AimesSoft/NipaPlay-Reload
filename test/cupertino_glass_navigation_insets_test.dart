import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/cupertino/utils/cupertino_glass_navigation_insets.dart';

void main() {
  test('fallback glass tab bar keeps its designed content height', () {
    expect(cupertinoGlassTabBarHeight, 64);
  });

  group('resolveGlassTabBarBottomOffset', () {
    test('fully clears Android three-button navigation', () {
      expect(
        resolveGlassTabBarBottomOffset(
          viewPaddingBottom: 48,
        ),
        54,
      );
    });

    test('fully clears Android gesture navigation', () {
      expect(
        resolveGlassTabBarBottomOffset(
          viewPaddingBottom: 24,
        ),
        30,
      );
    });

    test('fully clears the iOS home indicator', () {
      expect(
        resolveGlassTabBarBottomOffset(
          viewPaddingBottom: 34,
        ),
        40,
      );
    });

    test('uses the edge gap when there is no bottom inset', () {
      expect(
        resolveGlassTabBarBottomOffset(
          viewPaddingBottom: 0,
        ),
        6,
      );
    });
  });

  group('resolvePageActionsTrailingOffset', () {
    test('moves the native iOS 26 toolbar eight points inward', () {
      expect(
        resolvePageActionsTrailingOffset(
          viewPaddingRight: 0,
          usesNativeIOS26Toolbar: true,
        ),
        20,
      );
    });

    test('preserves the safe area while moving the native toolbar inward', () {
      expect(
        resolvePageActionsTrailingOffset(
          viewPaddingRight: 6,
          usesNativeIOS26Toolbar: true,
        ),
        26,
      );
    });

    test('keeps the fallback toolbar at its original offset', () {
      expect(
        resolvePageActionsTrailingOffset(
          viewPaddingRight: 6,
          usesNativeIOS26Toolbar: false,
        ),
        18,
      );
    });
  });
}
