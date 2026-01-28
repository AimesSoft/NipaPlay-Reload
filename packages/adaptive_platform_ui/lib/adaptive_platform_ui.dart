/// A Flutter package that provides adaptive platform-specific widgets
///
/// This package automatically renders native-looking widgets based on the platform:
/// - iOS 26+: Modern iOS 26 native designs with latest visual styles
/// - iOS <26 (iOS 18 and below): Traditional Cupertino widgets
/// - Android: Material Design widgets
///
/// ## Features
///
/// - Automatic platform detection
/// - iOS version-specific widget rendering
/// - Native iOS 26 designs following Apple's Human Interface Guidelines
/// - Seamless fallback to appropriate widgets for older iOS versions
/// - Material Design for Android
///
/// ## Usage
///
/// ```dart
/// import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
///
/// AdaptiveButton(
///   onPressed: () {
///     print('Button pressed');
///   },
///   child: Text('Click Me'),
/// )
/// ```
library;

// Platform utilities
export 'src/platform/platform_info.dart';

// Styles
export 'src/style/sf_symbol.dart';

// Widgets
export 'src/widgets/adaptive_app.dart';
export 'src/widgets/adaptive_app_bar.dart';
export 'src/widgets/adaptive_bottom_navigation_bar.dart';
export 'src/widgets/adaptive_button.dart';
export 'src/widgets/adaptive_switch.dart';
export 'src/widgets/adaptive_checkbox.dart';
export 'src/widgets/adaptive_radio.dart';
export 'src/widgets/adaptive_card.dart';
export 'src/widgets/adaptive_badge.dart';
export 'src/widgets/adaptive_tooltip.dart';
export 'src/widgets/adaptive_slider.dart';
export 'src/widgets/adaptive_segmented_control.dart';
export 'src/widgets/adaptive_alert_dialog.dart';
export 'src/widgets/adaptive_popup_menu_button.dart';
export 'src/widgets/adaptive_context_menu.dart';
export 'src/widgets/adaptive_scaffold.dart';
export 'src/widgets/adaptive_app_bar_action.dart';
export 'src/widgets/adaptive_snackbar.dart';
export 'src/widgets/adaptive_date_picker.dart';
export 'src/widgets/adaptive_time_picker.dart';
export 'src/widgets/adaptive_list_tile.dart';
export 'src/widgets/adaptive_text_field.dart';
export 'src/widgets/adaptive_text_form_field.dart';
export 'src/widgets/adaptive_tab_view.dart';
export 'src/widgets/adaptive_floating_action_button.dart';
export 'src/widgets/adaptive_form_section.dart';
export 'src/widgets/adaptive_expansion_tile.dart';
export 'src/widgets/adaptive_blur_view.dart';

// iOS 26 specific widgets (for advanced usage)
export 'src/widgets/ios26/ios26_button.dart';
export 'src/widgets/ios26/ios26_switch.dart';
export 'src/widgets/ios26/ios26_slider.dart';
export 'src/widgets/ios26/ios26_segmented_control.dart';
export 'src/widgets/ios26/ios26_alert_dialog.dart';
export 'src/widgets/ios26/ios26_native_search_tab_bar.dart';
export 'src/widgets/ios26/ios26_native_tab_bar.dart';
export 'src/widgets/ios26/ios26_scaffold_legacy.dart';
