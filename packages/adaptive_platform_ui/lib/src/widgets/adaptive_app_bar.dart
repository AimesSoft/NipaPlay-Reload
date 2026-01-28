import 'package:flutter/widgets.dart';
import 'adaptive_app_bar_action.dart';

/// Configuration for an adaptive app bar
///
/// This class holds the configuration for the app bar in [AdaptiveScaffold].
/// The actual rendering is platform-specific:
/// - iOS 26+ with useNativeToolbar: Native UIToolbar with Liquid Glass effects
/// - iOS 26+ without useNativeToolbar: CupertinoNavigationBar with custom back button
/// - iOS <26: CupertinoNavigationBar
/// - Android: Material AppBar
///
/// You can provide custom navigation bars using [cupertinoNavigationBar] or [appBar]:
/// - If [cupertinoNavigationBar] is provided and [useNativeToolbar] is false: Uses custom CupertinoNavigationBar on iOS
/// - If [appBar] is provided: Uses custom AppBar on Android
/// - Otherwise: Builds navigation bar from [title], [actions], and [leading]
class AdaptiveAppBar {
  /// Creates an adaptive app bar configuration
  const AdaptiveAppBar({
    this.title,
    this.actions,
    this.leading,
    this.useNativeToolbar = true,
    this.cupertinoNavigationBar,
    this.appBar,
  });

  /// Title for the app bar
  final String? title;

  /// Action buttons in the app bar
  /// - iOS 26+ with native toolbar: Rendered as native UIBarButtonItem in UIToolbar
  /// - iOS < 26: Rendered as buttons in CupertinoNavigationBar
  /// - Android: Rendered as IconButtons in Material AppBar
  final List<AdaptiveAppBarAction>? actions;

  /// Leading widget in the app bar (e.g., back button, menu button)
  /// If null and navigation is possible, an automatic back button will be shown
  final Widget? leading;

  /// Use native iOS 26 toolbar (iOS 26+ only)
  /// - When false (default): Uses CupertinoNavigationBar for better compatibility with routers
  /// - When true: Uses native iOS 26 UIToolbar with Liquid Glass effect
  ///
  /// Note: Setting this to true may cause compatibility issues with GoRouter and other
  /// router packages. Use with caution.
  ///
  /// If true, [cupertinoNavigationBar] will be ignored and native toolbar will be shown.
  final bool useNativeToolbar;

  /// Custom CupertinoNavigationBar for iOS
  ///
  /// When provided and [useNativeToolbar] is false, this custom navigation bar will be used
  /// instead of building one from [title], [actions], and [leading].
  ///
  /// Ignored when [useNativeToolbar] is true or on non-iOS platforms.
  final PreferredSizeWidget? cupertinoNavigationBar;

  /// Custom AppBar for Android
  ///
  /// When provided, this custom app bar will be used instead of building one
  /// from [title], [actions], and [leading].
  ///
  /// Ignored on iOS platforms.
  final PreferredSizeWidget? appBar;

  /// Creates a copy of this app bar with the given fields replaced
  AdaptiveAppBar copyWith({
    String? title,
    List<AdaptiveAppBarAction>? actions,
    Widget? leading,
    bool? useNativeToolbar,
    PreferredSizeWidget? cupertinoNavigationBar,
    PreferredSizeWidget? appBar,
  }) {
    return AdaptiveAppBar(
      title: title ?? this.title,
      actions: actions ?? this.actions,
      leading: leading ?? this.leading,
      useNativeToolbar: useNativeToolbar ?? this.useNativeToolbar,
      cupertinoNavigationBar:
          cupertinoNavigationBar ?? this.cupertinoNavigationBar,
      appBar: appBar ?? this.appBar,
    );
  }
}
