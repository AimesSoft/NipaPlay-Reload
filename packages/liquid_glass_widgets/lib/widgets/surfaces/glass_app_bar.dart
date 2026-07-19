import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../src/renderer/liquid_glass_renderer.dart';
import '../../types/glass_quality.dart';
import '../shared/glass_isolation_scope.dart';
import 'glass_large_title.dart' show GlassLargeTitleController;

/// A navigation bar layout widget following Apple's iOS 26 design patterns.
///
/// [GlassAppBar] renders a solid or transparent bar with leading widget,
/// centered title, and trailing actions. Glass effects belong on the
/// individual interactive elements (buttons, pills) — not the bar surface
/// itself. This matches iOS 26's navigation bar where the bar is a simple
/// layout container and glass is reserved for buttons.
///
/// ## Large-title collapse (iOS 26 pattern)
///
/// Pair with [GlassLargeTitle] and [GlassLargeTitleController] to get
/// automatic cross-fade between the large title (in the scroll view) and the
/// inline bar title — with zero boilerplate:
///
/// ```dart
/// final _titleController = GlassLargeTitleController();
///
/// GlassScaffold(
///   appBar: GlassAppBar(
///     title: Text('Chats'),
///     largeTitleController: _titleController,   // ← fades in as user scrolls
///   ),
///   body: CustomScrollView(
///     controller: _titleController.scrollController,
///     slivers: [
///       GlassLargeTitle(text: 'Chats', controller: _titleController),
///       // ... content slivers
///     ],
///   ),
/// )
/// ```
///
/// ## Transparent (default — iOS 26 style)
///
/// ```dart
/// GlassAppBar(
///   title: Text('Messages'),
///   leading: GlassButton(
///     icon: Icon(CupertinoIcons.back),
///     onTap: () => Navigator.pop(context),
///   ),
/// )
/// ```
///
/// ## Solid background (WhatsApp / Player style)
///
/// ```dart
/// GlassAppBar(
///   backgroundColor: Color(0xFF2C2C2E),
///   title: Text('Now Playing'),
///   leading: GlassButton(
///     icon: Icon(CupertinoIcons.back),
///     onTap: () => Navigator.pop(context),
///   ),
/// )
/// ```
///
/// ## Custom button settings (all buttons inherit)
///
/// ```dart
/// GlassAppBar(
///   buttonSettings: LiquidGlassSettings(
///     glassColor: Color(0x33FFFFFF),
///     thickness: 20,
///   ),
///   leading: GlassButton(...),   // inherits buttonSettings
///   actions: [GlassButton(...)], // inherits buttonSettings
/// )
/// ```
///
/// This widget implements [ObstructingPreferredSizeWidget] for use in both
/// [Scaffold.appBar] and [CupertinoPageScaffold.navigationBar].
class GlassAppBar extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  /// Creates a glass app bar.
  ///
  /// The bar itself is a simple layout container with a [backgroundColor].
  /// Glass effects are rendered by individual child widgets (e.g. [GlassButton])
  /// inside the bar — not by the bar surface.
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = true,
    this.backgroundColor = Colors.transparent,
    this.preferredSize = const Size.fromHeight(44.0),
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
    this.buttonSettings,
    this.largeTitleController,
  });

  // ===========================================================================
  // Properties
  // ===========================================================================

  /// The primary content of the app bar, typically a [Text] widget.
  final Widget? title;

  /// A widget to display before the title, typically a back button.
  final Widget? leading;

  /// A list of widgets to display after the title.
  final List<Widget>? actions;

  /// Whether the [title] should be centered.
  final bool centerTitle;

  /// The background color of the app bar.
  ///
  /// Defaults to [Colors.transparent] to match iOS 26's transparent
  /// navigation bar pattern. Use an opaque colour for solid bars
  /// (e.g. WhatsApp conversation, music player).
  final Color backgroundColor;

  /// The preferred height of the app bar.
  @override
  final Size preferredSize;

  /// Whether this app bar fully obstructs the content behind it.
  ///
  /// Returns `true` only when [backgroundColor] is fully opaque (alpha = 1.0).
  /// With the default transparent background, this returns `false`, which
  /// tells [CupertinoPageScaffold] to extend the body behind the bar —
  /// matching the iOS 26 transparent navigation bar pattern.
  @override
  bool shouldFullyObstruct(BuildContext context) => backgroundColor.a >= 1.0;

  /// Padding around the app bar content.
  final EdgeInsetsGeometry padding;

  /// Default glass settings for buttons inside this app bar.
  ///
  /// When provided, all [GlassButton] descendants that don't specify their
  /// own `settings` will inherit these. This avoids repeating the same
  /// settings on every button in the bar.
  ///
  /// Individual buttons can still override this with their own `settings`.
  ///
  /// ```dart
  /// GlassAppBar(
  ///   buttonSettings: LiquidGlassSettings(
  ///     glassColor: Color(0x33FFFFFF),
  ///     thickness: 20,
  ///   ),
  ///   leading: GlassButton(...),   // uses buttonSettings
  ///   actions: [
  ///     GlassButton(
  ///       settings: myCustomSettings, // overrides buttonSettings
  ///       ...
  ///     ),
  ///   ],
  /// )
  /// ```
  final LiquidGlassSettings? buttonSettings;

  /// Optional controller that drives the inline title opacity.
  ///
  /// When provided, the [title] widget is automatically wrapped in a
  /// [ListenableBuilder] that fades it **in** as [GlassLargeTitle]
  /// (the large title in the scroll view) fades **out**.
  ///
  /// This replicates iOS 26's `UINavigationBar.prefersLargeTitles` collapse
  /// behaviour with zero boilerplate. See [GlassLargeTitle] and
  /// [GlassLargeTitleController] for full usage.
  final GlassLargeTitleController? largeTitleController;

  @override
  Widget build(BuildContext context) {
    Widget content = ColoredBox(
      color: backgroundColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: padding,
          child: SizedBox(
            height: preferredSize.height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Leading widget
                if (leading != null) leading!,

                // Flexible title — optionally driven by collapse controller
                Expanded(
                  child: _buildTitle(),
                ),

                // Trailing actions
                if (actions != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: actions!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // Wrap with default button settings if provided.
    if (buttonSettings != null) {
      content = DefaultButtonSettings(
        settings: buttonSettings!,
        child: content,
      );
    }

    // Isolate the app bar so that when used in a regular Flutter Scaffold,
    // its glass buttons don't join the page-level blend group (which sits
    // behind the scrolling body), ensuring correct Z-order painting.
    // Premium is the default hint — individual buttons can still override
    // with quality: GlassQuality.standard, and GlassAdaptiveScope will
    // cap to the device ceiling regardless.
    return GlassIsolationScope(
      isolated: true,
      defaultQuality: GlassQuality.premium,
      child: content,
    );
  }

  /// Builds the title widget, optionally driven by [largeTitleController].
  ///
  /// Without a controller, returns the title as-is (same as before).
  /// With a controller, wraps in [ListenableBuilder] so only the title
  /// Opacity rebuilds on scroll — not the entire bar.
  Widget _buildTitle() {
    final titleWidget = centerTitle
        ? Center(child: title ?? const SizedBox.shrink())
        : Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: title ?? const SizedBox.shrink(),
            ),
          );

    if (largeTitleController == null) return titleWidget;

    return ListenableBuilder(
      listenable: largeTitleController!,
      builder: (context, _) {
        final progress = largeTitleController!.collapseProgress;
        // iOS 26 bar title behaviour: invisible during the first half of the
        // collapse, then fades in with ease-out over the second half.
        // This matches UIKit's two-phase crossfade where the bar title only
        // appears once the large title is mostly gone.
        final barProgress = ((progress - 0.5) / 0.5).clamp(0.0, 1.0);
        final barOpacity = Curves.easeOut.transform(barProgress);
        return Opacity(
          opacity: barOpacity,
          child: titleWidget,
        );
      },
    );
  }
}

/// An [InheritedWidget] that provides default [LiquidGlassSettings] for
/// descendant glass buttons.
///
/// Used by [GlassAppBar] to pass `buttonSettings` down the tree. Buttons
/// that don't specify their own `settings` can inherit these defaults.
///
/// To read the nearest ancestor's settings:
/// ```dart
/// final settings = DefaultButtonSettings.of(context);
/// ```
class DefaultButtonSettings extends InheritedWidget {
  /// Creates a default button settings scope.
  const DefaultButtonSettings({
    super.key,
    required this.settings,
    required super.child,
  });

  /// The default glass settings for descendant buttons.
  final LiquidGlassSettings settings;

  /// Returns the settings from the nearest [DefaultButtonSettings] ancestor,
  /// or `null` if none exists.
  static LiquidGlassSettings? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DefaultButtonSettings>()
        ?.settings;
  }

  @override
  bool updateShouldNotify(DefaultButtonSettings oldWidget) =>
      settings != oldWidget.settings;
}
