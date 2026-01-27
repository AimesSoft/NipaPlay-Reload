import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('AdaptiveAppBarAction', () {
    test('creates action with iOS symbol', () {
      final action = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        onPressed: () {},
      );

      expect(action.iosSymbol, 'info.circle');
      expect(action.icon, isNull);
      expect(action.title, isNull);
    });

    test('creates action with icon', () {
      final action = AdaptiveAppBarAction(icon: Icons.info, onPressed: () {});

      expect(action.icon, Icons.info);
      expect(action.iosSymbol, isNull);
      expect(action.title, isNull);
    });

    test('creates action with title', () {
      final action = AdaptiveAppBarAction(title: 'Info', onPressed: () {});

      expect(action.title, 'Info');
      expect(action.iosSymbol, isNull);
      expect(action.icon, isNull);
    });

    test('creates action with all parameters', () {
      final action = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        icon: Icons.info,
        title: 'Info',
        onPressed: () {},
      );

      expect(action.iosSymbol, 'info.circle');
      expect(action.icon, Icons.info);
      expect(action.title, 'Info');
    });

    test('throws assertion error when all parameters are null', () {
      expect(
        () => AdaptiveAppBarAction(onPressed: () {}),
        throwsAssertionError,
      );
    });

    test('calls onPressed when action is pressed', () {
      bool pressed = false;
      final action = AdaptiveAppBarAction(
        title: 'Test',
        onPressed: () {
          pressed = true;
        },
      );

      action.onPressed();
      expect(pressed, isTrue);
    });

    test('equality works correctly', () {
      final action1 = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        icon: Icons.info,
        title: 'Info',
        onPressed: () {},
      );

      final action2 = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        icon: Icons.info,
        title: 'Info',
        onPressed: () {},
      );

      final action3 = AdaptiveAppBarAction(
        iosSymbol: 'settings',
        icon: Icons.settings,
        title: 'Settings',
        onPressed: () {},
      );

      expect(action1, equals(action2));
      expect(action1, isNot(equals(action3)));
    });

    test('identical instances are equal', () {
      final action = AdaptiveAppBarAction(title: 'Test', onPressed: () {});

      expect(action, equals(action));
    });

    test('hashCode is consistent with equality', () {
      final action1 = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        icon: Icons.info,
        title: 'Info',
        onPressed: () {},
      );

      final action2 = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        icon: Icons.info,
        title: 'Info',
        onPressed: () {},
      );

      expect(action1.hashCode, equals(action2.hashCode));
    });

    test('different actions have different hash codes', () {
      final action1 = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        onPressed: () {},
      );

      final action2 = AdaptiveAppBarAction(
        iosSymbol: 'settings',
        onPressed: () {},
      );

      // Note: Different objects *can* have same hash code, but it's unlikely
      // This test may occasionally fail by chance, but that's acceptable
      expect(action1.hashCode, isNot(equals(action2.hashCode)));
    });

    test('toNativeMap includes iosSymbol when present', () {
      final action = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        onPressed: () {},
      );

      final map = action.toNativeMap();

      expect(map['icon'], 'info.circle');
      expect(map.containsKey('title'), isFalse);
    });

    test('toNativeMap includes title when present', () {
      final action = AdaptiveAppBarAction(title: 'Info', onPressed: () {});

      final map = action.toNativeMap();

      expect(map['title'], 'Info');
      expect(map.containsKey('icon'), isFalse);
    });

    test('toNativeMap includes both iosSymbol and title', () {
      final action = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        title: 'Info',
        onPressed: () {},
      );

      final map = action.toNativeMap();

      expect(map['icon'], 'info.circle');
      expect(map['title'], 'Info');
    });

    test('toNativeMap excludes icon parameter', () {
      final action = AdaptiveAppBarAction(
        icon: Icons.info,
        iosSymbol: 'info.circle',
        onPressed: () {},
      );

      final map = action.toNativeMap();

      expect(map.containsKey('androidIcon'), isFalse);
      expect(map['icon'], 'info.circle');
    });

    test('toNativeMap returns only spacerAfter when only icon is provided', () {
      final action = AdaptiveAppBarAction(icon: Icons.info, onPressed: () {});

      final map = action.toNativeMap();

      expect(map.containsKey('icon'), isFalse);
      expect(map.containsKey('title'), isFalse);
      expect(map.containsKey('spacerAfter'), isTrue);
      expect(map['spacerAfter'], 0); // Default is ToolbarSpacerType.none
    });

    test('equality ignores onPressed callback', () {
      final action1 = AdaptiveAppBarAction(title: 'Test', onPressed: () {});

      final action2 = AdaptiveAppBarAction(
        title: 'Test',
        onPressed: () {}, // Different callback instance
      );

      // Equality should only check iosSymbol, icon, and title
      expect(action1, equals(action2));
    });

    test('toNativeMap includes spacerAfter as none by default', () {
      final action = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        onPressed: () {},
      );

      final map = action.toNativeMap();

      expect(map['spacerAfter'], 0); // ToolbarSpacerType.none.index
    });

    test('toNativeMap includes spacerAfter as fixed', () {
      final action = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        onPressed: () {},
        spacerAfter: ToolbarSpacerType.fixed,
      );

      final map = action.toNativeMap();

      expect(map['spacerAfter'], 1); // ToolbarSpacerType.fixed.index
    });

    test('toNativeMap includes spacerAfter as flexible', () {
      final action = AdaptiveAppBarAction(
        iosSymbol: 'info.circle',
        onPressed: () {},
        spacerAfter: ToolbarSpacerType.flexible,
      );

      final map = action.toNativeMap();

      expect(map['spacerAfter'], 2); // ToolbarSpacerType.flexible.index
    });
  });
}
