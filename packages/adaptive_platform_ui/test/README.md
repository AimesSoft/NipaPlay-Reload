# Tests for Adaptive Platform UI

This directory contains comprehensive tests for all adaptive widgets in the package.

## Running Tests

To run all tests:
```bash
flutter test
```

To run a specific test file:
```bash
flutter test test/adaptive_button_test.dart
```

To run tests with coverage:
```bash
flutter test --coverage
```

## Test Files

### Widget Tests

#### `adaptive_button_test.dart`
Tests for `AdaptiveButton` and `IOS26Button` widgets:
- Button creation with label, child, and icon
- onPressed callbacks
- Disabled state
- Different styles (filled, tinted, gray, bordered, plain, glass, prominentGlass)
- Different sizes (small, medium, large)
- Custom colors and padding
- Icon button support
- iconColor parameter

#### `adaptive_text_field_test.dart`
Tests for `AdaptiveTextField` and `AdaptiveTextFormField` widgets:
- Text field creation with placeholder
- onChanged callbacks
- Password fields (obscureText)
- Prefix and suffix icons
- Multiline text fields
- Enabled/disabled state
- TextEditingController support
- Form validation
- Error display
- onSaved callbacks

#### `adaptive_switch_test.dart`
Tests for input control widgets:
- **AdaptiveSwitch**: Value changes, disabled state, custom colors
- **AdaptiveSlider**: Value changes, dragging, min/max values, divisions
- **AdaptiveCheckbox**: Value changes, tristate mode, disabled state
- **AdaptiveRadio**: Group value changes, disabled state

#### `adaptive_card_badge_test.dart`
Tests for container and decoration widgets:
- **AdaptiveCard**: Child rendering, custom padding, colors, border radius, elevation
- **AdaptiveBadge**: Count display, label display, 99+ for large counts, showZero, custom colors, large size
- **AdaptiveTooltip**: Message display, long press behavior, preferBelow, custom height
- **AdaptiveListTile**: Title/subtitle rendering, onTap/onLongPress callbacks, leading/trailing widgets, selected state

#### `adaptive_segmented_control_test.dart`
Tests for selection and dialog widgets:
- **AdaptiveSegmentedControl**: Label rendering, segment selection, icon support, custom colors
- **AdaptiveAlertDialog**: Dialog display, actions, input fields, destructive actions
- **AdaptiveContextMenu**: Long press menu, action callbacks
- **AdaptivePopupMenuButton**: Text and icon buttons, menu display, item selection

#### `adaptive_snackbar_pickers_test.dart`
Tests for pickers and layout widgets:
- **AdaptiveSnackBar**: Message display, different types (info, success, warning, error), action buttons, custom duration
- **AdaptiveDatePicker**: Dialog display, date selection, date range, cancellation
- **AdaptiveTimePicker**: Dialog display, time selection, 24-hour format, cancellation
- **AdaptiveScaffold**: Body rendering, app bar, bottom navigation
- **AdaptiveAppBar**: Title rendering, actions
- **AdaptiveBottomNavigationBar**: Item rendering, selection, badge counts

#### `adaptive_app_test.dart`
Tests for `AdaptiveApp` and related classes:
- **AdaptiveApp**: Home, routes, navigation, builder, themes (light/dark)
- **AdaptiveApp.router**: Router configuration, builder, title
- **MaterialAppData**: Default and custom values
- **CupertinoAppData**: Default and custom values
- **PlatformTarget**: All enum values

#### `adaptive_app_bar_action_test.dart`
Tests for `AdaptiveAppBarAction` data class:
- Action creation with iOS symbol, Android icon, and title
- Assert validation when all parameters are null
- onPressed callback
- Equality (==) operator
- hashCode consistency
- toNativeMap() method for native platform channels

#### `platform_info_test.dart`
Tests for platform detection utilities:
- Platform type detection (iOS, Android, Web)
- iOS version detection
- Version range checking
- Platform description

## Test Coverage

**📊 Current Status: 143 tests covering 23 widgets (100% widget coverage)**

The test suite covers:
- ✅ **23 adaptive widgets** with comprehensive test cases
- ✅ **Widget creation** and rendering
- ✅ **User interactions** (tap, long press, drag)
- ✅ **State management** (value changes, selections)
- ✅ **Callbacks** (onPressed, onChanged, onTap, etc.)
- ✅ **Validation** (form fields, error messages)
- ✅ **Custom styling** (colors, padding, sizes)
- ✅ **Platform detection** (iOS, Android, version checking)
- ✅ **Data classes** (equality, hashCode, serialization)
- ✅ **App configuration** (themes, routes, navigation)

## Test Structure

Each test file follows this structure:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('WidgetName', () {
    testWidgets('test description', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WidgetUnderTest(),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Button'));
      await tester.pump();

      // Assert
      expect(result, expectedValue);
    });
  });
}
```

## Known Test Limitations

1. **Native iOS 26 Components**: Tests use fallback implementations since native UiKitView cannot be tested in Flutter test environment
2. **Platform-Specific Rendering**: Tests run on the test platform (typically macOS) and may not catch platform-specific rendering issues
3. **Overflow Warnings**: Some tests show rendering overflow warnings which are expected in constrained test environments

## Adding New Tests

When adding tests for new widgets:

1. Create a new test file: `test/adaptive_[widget_name]_test.dart`
2. Import necessary packages
3. Create test groups for each widget
4. Test widget creation, interactions, callbacks, and edge cases
5. Run tests to ensure they pass: `flutter test`

Example:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('AdaptiveNewWidget', () {
    testWidgets('creates widget with properties', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveNewWidget(
              property: 'value',
            ),
          ),
        ),
      );

      expect(find.text('value'), findsOneWidget);
    });

    testWidgets('calls callback when interacted', (WidgetTester tester) async {
      bool called = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveNewWidget(
              onAction: () {
                called = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AdaptiveNewWidget));
      await tester.pump();

      expect(called, isTrue);
    });
  });
}
```

## Continuous Integration

[![CI](https://github.com/berkaycatak/adaptive_platform_ui/workflows/CI/badge.svg)](https://github.com/berkaycatak/adaptive_platform_ui/actions)
[![codecov](https://codecov.io/gh/berkaycatak/adaptive_platform_ui/branch/main/graph/badge.svg)](https://codecov.io/gh/berkaycatak/adaptive_platform_ui)

All tests are automatically run on every push and pull request via GitHub Actions.

### CI Pipeline

The CI pipeline runs three jobs:

1. **Analyze** - Code quality checks:
   - `dart format` - Code formatting verification
   - `flutter analyze` - Static analysis and linting

2. **Test** - Run test suite:
   - `flutter test --coverage` - All unit and widget tests
   - Coverage report uploaded to Codecov

3. **Build** - Build verification:
   - Build example app for Android (APK)
   - Build example app for iOS (no codesign)

### Viewing CI Results

- Check the **Actions** tab on GitHub for detailed logs
- View coverage reports on Codecov
- All PRs show CI status before merging

### Running CI Locally

Before pushing, verify your changes pass CI:

```bash
# 1. Format check
dart format --output=none --set-exit-if-changed .

# 2. Analyze
flutter analyze --fatal-infos

# 3. Test
flutter test --coverage

# 4. Build (optional)
cd example && flutter build apk --debug
```

### CI Configuration

See `.github/workflows/ci.yml` for the complete CI configuration.

## Best Practices

1. **Test widget behavior, not implementation**: Focus on what the widget does, not how it does it
2. **Use meaningful test descriptions**: Clear descriptions help identify failures
3. **Test edge cases**: Empty states, null values, extreme values
4. **Keep tests independent**: Each test should work in isolation
5. **Use setUp and tearDown**: Initialize and clean up resources properly
6. **Mock external dependencies**: Don't rely on network, filesystem, or platform channels in unit tests
7. **Test accessibility**: Ensure widgets work with screen readers and accessibility tools

## Future Improvements

- [ ] Add golden tests for visual regression testing
- [ ] Add integration tests for complex user flows
- [ ] Increase test coverage to 90%+
- [ ] Add performance benchmarks
- [ ] Test platform-specific rendering on actual devices
- [ ] Add tests for error handling and edge cases
- [ ] Test theme and localization support
