# Changelog

## [0.1.98]
* **NEW**: Added `selectedItemColor` and `unselectedItemColor` support for AdaptiveBottomNavigationBar
  * iOS 26+: Icon colors via renderingMode (`.alwaysOriginal` for unselected, `.alwaysTemplate` for selected)
  * iOS <26 & Android: Native color properties
  * Customizable tab bar item colors for better UI flexibility
* **NEW**: Added `useSmoothRectangleBorder` parameter to AdaptiveButton (iOS 26+)
  * Default `true`: Smooth rectangle corners
  * Set to `false`: Perfect circular/capsule shape for icon buttons
* **BREAKING**: Split AdaptiveAlertDialog methods for different use cases
  * `show()` - Standard dialog (returns void)
  * `inputShow()` - Text input dialog (returns String?)
  * Cancel button now correctly returns null for input dialogs
* **FIX**: Fixed dynamic label updates not working in AdaptivePopupMenuItem
  * Labels now properly update when state changes
* **FIX**: Fixed dark mode not updating in AdaptiveDatePicker and AdaptiveTimePicker
  * Pickers now respond to theme changes dynamically
## [0.1.97]
* **NEW**: Added `spacerAfter` parameter (ToolbarSpacerType) to AdaptiveAppBarAction for iOS 26+ Liquid Glass toolbar grouping
  * `ToolbarSpacerType.fixed` - 12pt fixed space using UIBarButtonItem.fixedSpace() for spacing within groups
  * `ToolbarSpacerType.flexible` - Flexible space using UIBarButtonItem.flexibleSpace() for left/right group separation
  * `ToolbarSpacerType.none` - No spacer (default)
  * Follows iOS 26+ Liquid Glass design guidelines per Apple HIG
  * Example: `AdaptiveAppBarAction(iosSymbol: 'arrow.uturn.forward', onPressed: () {}, spacerAfter: ToolbarSpacerType.flexible)`


## [0.1.96]
* **FIX**: Added automatic localization support for AdaptiveDatePicker, AdaptiveTimePicker, and popup menu buttons
  * Platform-specific localizations: CupertinoLocalizations for iOS, MaterialLocalizations for Android
  * Supports 70+ languages automatically based on system locale
* **FIX**: Increased default height of AdaptiveSegmentedControl from 32 to 36 pixels to prevent overflow on iOS <26
  * Resolves RenderConstraintsTransformBox overflow issue with CupertinoSlidingSegmentedControl
* **FIX**: Fixed tab bar minimizing during pull-to-refresh bounce animation
  * Tab bar now ignores scroll events when content is overscrolling (pixels outside minScrollExtent/maxScrollExtent)
  * Prevents unwanted tab bar animation during iOS elastic scroll bounce

## [0.1.95]
* **NEW**: Added `AdaptiveTabBarView` widget - Platform-specific swipeable tab bar view with color customization
* **NEW**: Added `AdaptiveFloatingActionButton` widget - Platform-specific FAB with custom colors, mini size, hero transitions
* **NEW**: Added `AdaptiveFormSection` widget - Platform-specific form sections (iOS: CupertinoFormSection, Android: Card)
  * Two constructors: default and insetGrouped
  * Works with CupertinoFormRow and adaptive components
* **NEW**: Added `AdaptiveExpansionTile` widget - Modern expandable/collapsible content
  * iOS: Custom design with rounded corners, smooth shadows, animated chevron, gradient separator, modern child items with tap feedback
  * Android: Material ExpansionTile with InkWell effects
  * Full customization support (colors, padding, callbacks, alignment)
* **BREAKING CHANGE**: Renamed `AdaptiveAppBarAction.androidIcon` to `icon`
  * `iosSymbol` for iOS 26+ only, `icon` for iOS <26 and Android
  * Migration: Replace `androidIcon:` with `icon:`
* **IMPROVEMENT**: Updated `AdaptiveSegmentedControl` for iOS <26 to use CupertinoSlidingSegmentedControl
* Added comprehensive tests and demo pages for all new widgets

## [0.1.94+1]
* fix: improve pub.dev score and CI compatibility

## [0.1.94]
* **NEW**: Added `AdaptiveTextField` for platform-specific text input
  * iOS: Uses `CupertinoTextField` with tertiarySystemBackground color and rounded corners
  * Android: Uses Material `TextField` with outlined border
  * Supports all standard text field parameters: placeholder, keyboard type, obscure text, max length, etc.
  * Supports prefix and suffix icons on both platforms
  * Automatic platform-specific styling and behavior
* **NEW**: Added `AdaptiveTextFormField` for form validation support
  * iOS: Uses custom `FormField` wrapper with `CupertinoTextField` for proper validation
  * Android: Uses Material `TextFormField`
  * Full form validation support with validator, onSaved, and autovalidateMode
  * Displays error messages with red border on iOS, standard Material error styling on Android
  * Supports prefix and suffix icons with proper validation state handling
* **FIX**: Fixed prefix/suffix icon support in text fields
  * Icons now display correctly on both iOS and Android
  * iOS icons wrapped in proper padding for consistent spacing
  * Added GestureDetector to prevent focus when tapping icons
* **FIX**: Fixed iOS26 button icon tap area issue
  * Child widgets in `IOS26Button.child` now wrapped with `IgnorePointer`
  * Icon buttons now respond to taps anywhere on the icon, not just the edges
  * Resolves issue where `AdaptiveButton.icon` had limited tap area
* **IMPROVEMENT**: Added `iconColor` parameter to `AdaptiveButton.icon`
  * Separate color control for icon buttons
  * `textColor` remains for label buttons, `iconColor` for icon buttons
  * Consistent API across all button constructors
* Added comprehensive demo page showcasing all text field features
*
* @amolon615, thanks for the changes below.
* Updated documentation with text field examples
* * **NEW**: Added badge counter support to `AdaptiveNavigationDestination`
  * Added `badgeCount` parameter to `AdaptiveNavigationDestination` class
  * iOS 26+: Uses native `UITabBarItem.badgeValue` for native badge display
  * iOS <26 and Android: Uses `AdaptiveBadge` widget for cross-platform badge display
  * Supports dynamic badge updates and proper badge clearing
  * Badge counts > 99 display as "99+" following iOS conventions
  * Added comprehensive demo page showcasing badge navigation functionality


## [0.1.93]
* **NEW**: Added `AdaptiveDatePicker` for platform-specific date selection
  * iOS: Uses `CupertinoDatePicker` in a modal bottom sheet with Cancel/Done buttons
  * Android: Uses Material `DatePickerDialog`
  * Supports date, dateTime, and time modes
  * Configurable date range with firstDate and lastDate parameters
  * Returns `Future<DateTime?>` with selected date or null if cancelled
* **NEW**: Added `AdaptiveTimePicker` for platform-specific time selection
  * iOS: Uses `CupertinoDatePicker` in time mode in a modal bottom sheet
  * Android: Uses Material `TimePickerDialog`
  * Supports both 12-hour and 24-hour formats
  * Returns `Future<TimeOfDay?>` with selected time or null if cancelled
* **NEW**: Added `AdaptiveListTile` for platform-specific list item tiles
  * iOS: Uses CupertinoListTile-like styling with bottom border separator
  * Android: Uses Material `ListTile`
  * Supports leading, title, subtitle, and trailing widgets
  * Includes onTap and onLongPress callbacks
  * Supports selected state and disabled state
  * Customizable backgroundColor and padding
* Updated README with comprehensive examples for new widgets
* Updated widget catalog to include all new widgets

## [0.1.92]
* AdaptiveSegmentedControl now renders icons directly based on platform.
* Maintained existing height, padding, and shrinkWrap behavior.

## [0.1.91]
* Enhance AdaptivePopupMenuButton to support dynamic icon types for iOS and Android

## [0.1.9]
* **NEW**: Added text input support to `AdaptiveAlertDialog`
  * Added `AdaptiveAlertDialogInput` class for input configuration
  * iOS 26+: Native UITextField with native keyboard types
  * iOS <26: CupertinoTextField with scrollable content
  * Android: Material TextField
  * Returns `Future<String?>` with user input
  * Supports placeholder, initial value, keyboard type, obscure text, and max length
* **NEW**: Added `AdaptiveContextMenu` widget for long-press context menus
  * iOS: Uses `CupertinoContextMenu.builder` with native animations
  * Android: Uses `PopupMenuButton` with Material Design styling
  * Supports icons, destructive actions, and disabled states
  * Long press to show, tap to select action
* **IMPROVEMENT**: Changed `AdaptiveAlertDialog` icon parameter to dynamic type
  * iOS 26+: Accepts SF Symbol strings (e.g., "checkmark.circle.fill")
  * iOS <26 and Android: Accepts IconData
  * Automatically handles platform-specific icon rendering

## [0.1.8]
* **NEW**: Added `AdaptiveBottomNavigationBar` class for cleaner bottom navigation configuration
  * Centralized bottom navigation configuration with `bottomNavigationBar` parameter in `AdaptiveScaffold`
  * Replaces individual `destinations`, `selectedIndex`, `onDestinationSelected` parameters
  * If `bottomNavigationBar` is null, no bottom navigation will be shown
* **NEW**: Added custom bottom navigation bar support via `AdaptiveBottomNavigationBar`
  * `items` parameter: Navigation items (renamed from `destinations`)
  * `selectedIndex` parameter: Currently selected item index
  * `onTap` parameter: Callback when item is tapped (renamed from `onDestinationSelected`)
  * `useNativeBottomBar` parameter: Control iOS 26+ native bottom bar (default: `true`)
  * `cupertinoTabBar` parameter: Provide custom `CupertinoTabBar` for iOS
  * `bottomNavigationBar` parameter: Provide custom `NavigationBar` or `BottomNavigationBar` for Android
* **IMPORTANT**: `useNativeBottomBar` priority behavior on iOS
  * iOS 26+ with `useNativeBottomBar: true`: Native UITabBar with Liquid Glass effect is shown, custom `cupertinoTabBar` is ignored
  * iOS 26+ with `useNativeBottomBar: false`: Custom `cupertinoTabBar` is used if provided, otherwise auto-generated from items
  * iOS <26: Custom `cupertinoTabBar` is used if provided, otherwise auto-generated from items (useNativeBottomBar is ignored)
* **FIX**: Fixed icon type handling in bottom navigation
  * SF Symbol strings (e.g., "house.fill") are now properly converted to IconData for CupertinoTabBar
  * Android NavigationBar handles both IconData and SF Symbol strings with appropriate fallbacks
* **BREAKING CHANGE**: `AdaptiveScaffold` bottom navigation parameters refactored
  * Removed: Direct `destinations`, `selectedIndex`, `onDestinationSelected` parameters
  * Added: Single `bottomNavigationBar` parameter of type `AdaptiveBottomNavigationBar?`
  * Migration: Wrap existing parameters in `AdaptiveBottomNavigationBar()`
  ```dart
  // Before
  AdaptiveScaffold(
    destinations: [...],
    selectedIndex: 0,
    onDestinationSelected: (index) {},
  )

  // After
  AdaptiveScaffold(
    bottomNavigationBar: AdaptiveBottomNavigationBar(
      items: [...],
      selectedIndex: 0,
      onTap: (index) {},
    ),
  )
  ```

## [0.1.7+1]
  * Updated README.md

## [0.1.7]
* **NEW**: Added `AdaptiveAppBar` class for cleaner app bar configuration
  * Centralized app bar configuration with `appBar` parameter in `AdaptiveScaffold`
  * Replaces individual `title`, `actions`, `leading`, `useNativeToolbar` parameters
  * If `appBar` is null, no app bar or toolbar will be shown
* **NEW**: Added custom navigation bar support via `AdaptiveAppBar`
  * `cupertinoNavigationBar` parameter: Provide custom `CupertinoNavigationBar` for iOS
  * `appBar` parameter: Provide custom `AppBar` for Android
  * Custom navigation bars take priority over auto-generated ones
* **IMPORTANT**: `useNativeToolbar` priority behavior on iOS
  * When `useNativeToolbar: true`: Native iOS 26 toolbar is shown, custom `cupertinoNavigationBar` is ignored
  * When `useNativeToolbar: false` or not set: Custom `cupertinoNavigationBar` is used if provided
* **BREAKING CHANGE**: `AdaptiveScaffold` parameters refactored
  * Removed: Direct `title`, `actions`, `leading`, `useNativeToolbar` parameters
  * Added: Single `appBar` parameter of type `AdaptiveAppBar?`
  * Migration: Wrap existing parameters in `AdaptiveAppBar()`
  ```dart
  // Before
  AdaptiveScaffold(
    title: 'My App',
    actions: [...],
    useNativeToolbar: true,
  )

  // After
  AdaptiveScaffold(
    appBar: AdaptiveAppBar(
      title: 'My App',
      actions: [...],
      useNativeToolbar: true,
    ),
  )
  ```

## [0.1.6]
* **NEW**: Added `AdaptivePopupMenuButton.widget()` constructor for custom widget support
  * iOS <26: GestureDetector with CupertinoActionSheet fallback
  * Android: Material PopupMenuButton with custom child
  * Added demo examples: Custom Button, Card Style, and Chip Style

## [0.1.5+2]
  * Updated README.md

## [0.1.5+1]
  * Updated README.md

## [0.1.5]

* **NEW**: Added `AdaptiveSnackBar` widget for platform-specific notifications
  * iOS: Banner-style notification at the top with slide/fade animations
    - Tap to dismiss
    - Icon indicators for different types
    - Action button support with blur effect
    - Automatic dismissal
  * Android: Material SnackBar at the bottom
    - Standard Material Design appearance
    - Action button support
  * Supports 4 types: info, success, warning, error
  * Customizable duration and action callbacks
* **BREAKING CHANGE**: iOS 26 Native Toolbar is now optional due to stability issues with GoRouter and other router packages
  * Native toolbar can still be enabled via `useNativeToolbar: true` parameter in `AdaptiveScaffold`
  * Default behavior now uses `CupertinoNavigationBar` for better compatibility
  * iOS 26+ users will get custom animated back button when `useNativeToolbar: false`
  * Resolves touch callback issues and navigation conflicts with router-based navigation
* **IMPROVEMENT**: Added automatic back button with fade animation for iOS 26+ when using `useNativeToolbar: false`
  * Appears automatically when page can pop
  * Prevents native back button conflicts during transitions
  * Smooth fade-out animation on tap
* **FIX**: Fixed icon handling in bottom navigation - icons now properly support both SF Symbol strings and IconData
* Updated demo app with comprehensive snackbar examples

## [0.1.4+1]
  * Updated README.md

## [0.1.4]

* **NEW**: Added `AdaptiveCard` widget for platform-specific card styling
  * iOS: Custom iOS-style card with Cupertino design (border, subtle shadow, rounded corners)
  * Android: Material Design Card with elevation support
  * Support for custom colors, border radius, padding, margin, and clip behavior
* **NEW**: Added `AdaptiveRadio` widget for radio button groups
  * iOS: Custom iOS-style radio with circular design
  * Android: Material Design Radio
  * Support for custom colors, toggleable mode, and disabled state
* **NEW**: Added `AdaptiveBadge` widget for notification badges
  * iOS: Custom iOS-style badge with rounded design
  * Android: Material Design Badge
  * Support for count/label display, custom colors, show zero option, and large size
* **NEW**: Added `AdaptiveTooltip` widget for platform-specific tooltips
  * iOS: Custom iOS-style tooltip with animation and theme support
  * Android: Material Design Tooltip
  * Long press/tap to show, auto-hide after duration
* **NEW**: Added `AdaptiveCheckbox` widget (Cupertino & Material only)
  * iOS: Custom iOS-style checkbox with Cupertino design
  * Android: Material Design Checkbox
  * Support for tristate, custom colors, and dark/light mode
* **EXPERIMENTAL**: Added `IOS26NativeSearchTabBar` for iOS 26+ native search tab bar
  * App-level UITabBarController integration replacing Flutter's navigation
  * Native search tab transformation with UISearchController
  * Liquid Glass effects and native animations
  * Method channel for Flutter ↔ Native communication
  * Search query callbacks and tab selection handling
  * ⚠️ **WARNING**: This feature is highly experimental and unstable:
    - Replaces Flutter's root view controller
    - Breaks widget lifecycle and state management
    - Hot reload may not work properly
    - Navigation stack becomes invalid
    - Only recommended for prototyping and demos
  * See demo page for detailed technical explanation of architectural conflicts
* Added comprehensive demo pages for all new widgets

## [0.1.3]

* **BREAKING CHANGE**: Renamed `AdaptiveScaffold.child` parameter to `body` to match standard Scaffold API
* **NEW**: Added `AdaptiveApp` widget for automatic platform-specific app configuration
  * `AdaptiveApp()` - Constructor for normal navigation
  * `AdaptiveApp.router()` - Constructor for router-based navigation (GoRouter, etc.)
  * Direct theme parameters: `themeMode`, `materialLightTheme`, `materialDarkTheme`, `cupertinoLightTheme`, `cupertinoDarkTheme`
  * Platform-specific callbacks: `material()` and `cupertino()` for advanced configuration
  * Automatic platform detection (iOS uses CupertinoApp, Android uses MaterialApp)
  * Full support for all MaterialApp and CupertinoApp properties
* Debug banner now hidden by default (`debugShowCheckedModeBanner: false`)
* Updated all example code to use new `body` parameter

## [0.1.2]

* Fix image links in README.md to use GitHub raw URLs
* Images now display correctly on pub.dev

## [0.1.1]

* Documentation improvements
* Added comprehensive README with images for all widgets
* Added visual showcase for toolbar, tab bar, buttons, segmented controls, switches, sliders, alerts, and popup menus
* Improved code examples and usage documentation

## [0.1.0]

* Initial release with iOS 26+ support
* Features:
  * `AdaptiveScaffold` - Platform-adaptive scaffold with native iOS 26 toolbar and tab bar
  * `AdaptiveButton` - Adaptive buttons with iOS 26 Liquid Glass design
  * `AdaptiveSegmentedControl` - Native segmented controls for all platforms
  * `AdaptiveSwitch` - Platform-adaptive switches
  * `AdaptiveSlider` - Platform-adaptive sliders
  * `AdaptiveAlertDialog` - Native alert dialogs
  * `AdaptivePopupMenuButton` - Platform-adaptive popup menus
* iOS 26+ features:
  * Native UIToolbar with Liquid Glass blur effects
  * Native UITabBar with minimize behavior
  * Native UISegmentedControl
  * Native SF Symbol support
  * Haptic feedback
  * Automatic light/dark mode adaptation
* Platform support:
  * iOS 26+ with native Liquid Glass designs
  * iOS <26 (iOS 18 and below) with traditional Cupertino widgets
  * Android with Material Design 3
