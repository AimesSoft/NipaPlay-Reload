import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';

/// Platform-specific configuration for MaterialApp
class MaterialAppData {
  const MaterialAppData({
    this.color,
    this.highContrastTheme,
    this.highContrastDarkTheme,
    this.debugShowMaterialGrid = false,
    this.showPerformanceOverlay = false,
    this.checkerboardRasterCacheImages = false,
    this.checkerboardOffscreenLayers = false,
    this.showSemanticsDebugger = false,
    this.debugShowCheckedModeBanner = false,
    this.shortcuts,
    this.actions,
    this.restorationScopeId,
    this.scrollBehavior,
  });

  final Color? color;
  final ThemeData? highContrastTheme;
  final ThemeData? highContrastDarkTheme;
  final bool debugShowMaterialGrid;
  final bool showPerformanceOverlay;
  final bool checkerboardRasterCacheImages;
  final bool checkerboardOffscreenLayers;
  final bool showSemanticsDebugger;
  final bool debugShowCheckedModeBanner;
  final Map<ShortcutActivator, Intent>? shortcuts;
  final Map<Type, Action<Intent>>? actions;
  final String? restorationScopeId;
  final ScrollBehavior? scrollBehavior;
}

/// Platform-specific configuration for CupertinoApp
class CupertinoAppData {
  const CupertinoAppData({
    this.color,
    this.showPerformanceOverlay = false,
    this.checkerboardRasterCacheImages = false,
    this.checkerboardOffscreenLayers = false,
    this.showSemanticsDebugger = false,
    this.debugShowCheckedModeBanner = false,
    this.shortcuts,
    this.actions,
    this.restorationScopeId,
    this.scrollBehavior,
  });

  final Color? color;
  final bool showPerformanceOverlay;
  final bool checkerboardRasterCacheImages;
  final bool checkerboardOffscreenLayers;
  final bool showSemanticsDebugger;
  final bool debugShowCheckedModeBanner;
  final Map<ShortcutActivator, Intent>? shortcuts;
  final Map<Type, Action<Intent>>? actions;
  final String? restorationScopeId;
  final ScrollBehavior? scrollBehavior;
}

/// Platform detection for configuration callbacks
enum PlatformTarget {
  android,
  ios,
  ios26Plus,
  ios18OrLower,
  web,
  desktop,
  other,
}

/// An adaptive app that uses MaterialApp for Android and CupertinoApp for iOS
class AdaptiveApp extends StatelessWidget {
  /// Creates an AdaptiveApp with navigation
  const AdaptiveApp({
    super.key,
    this.navigatorKey,
    this.home,
    this.routes = const <String, WidgetBuilder>{},
    this.initialRoute,
    this.onGenerateRoute,
    this.onGenerateInitialRoutes,
    this.onUnknownRoute,
    this.navigatorObservers = const <NavigatorObserver>[],
    this.builder,
    this.title = '',
    this.onGenerateTitle,
    this.themeMode,
    this.materialLightTheme,
    this.materialDarkTheme,
    this.cupertinoLightTheme,
    this.cupertinoDarkTheme,
    this.locale,
    this.localizationsDelegates,
    this.localeListResolutionCallback,
    this.localeResolutionCallback,
    this.supportedLocales = const <Locale>[Locale('en', 'US')],
    this.material,
    this.cupertino,
  }) : routerConfig = null,
       routeInformationProvider = null,
       routeInformationParser = null,
       routerDelegate = null,
       backButtonDispatcher = null;

  /// Creates an AdaptiveApp with router support
  const AdaptiveApp.router({
    super.key,
    this.routerConfig,
    this.routeInformationProvider,
    this.routeInformationParser,
    this.routerDelegate,
    this.backButtonDispatcher,
    this.builder,
    this.title = '',
    this.onGenerateTitle,
    this.themeMode,
    this.materialLightTheme,
    this.materialDarkTheme,
    this.cupertinoLightTheme,
    this.cupertinoDarkTheme,
    this.locale,
    this.localizationsDelegates,
    this.localeListResolutionCallback,
    this.localeResolutionCallback,
    this.supportedLocales = const <Locale>[Locale('en', 'US')],
    this.material,
    this.cupertino,
  }) : navigatorKey = null,
       home = null,
       routes = const <String, WidgetBuilder>{},
       initialRoute = null,
       onGenerateRoute = null,
       onGenerateInitialRoutes = null,
       onUnknownRoute = null,
       navigatorObservers = const <NavigatorObserver>[];

  // Navigation properties
  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget? home;
  final Map<String, WidgetBuilder> routes;
  final String? initialRoute;
  final RouteFactory? onGenerateRoute;
  final InitialRouteListFactory? onGenerateInitialRoutes;
  final RouteFactory? onUnknownRoute;
  final List<NavigatorObserver> navigatorObservers;

  // Router properties
  final RouterConfig<Object>? routerConfig;
  final RouteInformationProvider? routeInformationProvider;
  final RouteInformationParser<Object>? routeInformationParser;
  final RouterDelegate<Object>? routerDelegate;

  /// A delegate that decides how to respond to the Android back button
  ///
  /// Only used when [routerDelegate] is provided (router mode).
  /// See [BackButtonDispatcher] for more details.
  final BackButtonDispatcher? backButtonDispatcher;

  // Common properties

  /// A builder that wraps the navigator or router
  ///
  /// Used to insert widgets above the navigator but below the routes.
  /// This is useful for adding overlays, notifications, or other widgets
  /// that should appear on all pages.
  ///
  /// Example:
  /// ```dart
  /// builder: (context, child) {
  ///   return MediaQuery(
  ///     data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
  ///     child: child!,
  ///   );
  /// }
  /// ```
  final TransitionBuilder? builder;

  final String title;
  final GenerateAppTitle? onGenerateTitle;

  // Theme properties
  final ThemeMode? themeMode;
  final ThemeData? materialLightTheme;
  final ThemeData? materialDarkTheme;

  /// The light theme for iOS (CupertinoApp)
  ///
  /// This theme is used when [themeMode] is [ThemeMode.light] or when
  /// the system is in light mode and [themeMode] is [ThemeMode.system].
  ///
  /// Defaults to [CupertinoThemeData] with [Brightness.light].
  final CupertinoThemeData? cupertinoLightTheme;

  /// The dark theme for iOS (CupertinoApp)
  ///
  /// This theme is used when [themeMode] is [ThemeMode.dark] or when
  /// the system is in dark mode and [themeMode] is [ThemeMode.system].
  ///
  /// Defaults to [CupertinoThemeData] with [Brightness.dark].
  final CupertinoThemeData? cupertinoDarkTheme;

  // Localization properties
  final Locale? locale;
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;
  final LocaleListResolutionCallback? localeListResolutionCallback;
  final LocaleResolutionCallback? localeResolutionCallback;
  final Iterable<Locale> supportedLocales;

  // Platform-specific configuration callbacks
  final MaterialAppData Function(BuildContext, PlatformTarget)? material;

  /// Platform-specific configuration callback for iOS (CupertinoApp)
  ///
  /// This callback is called when building the CupertinoApp and allows
  /// you to provide platform-specific configuration options.
  ///
  /// Example:
  /// ```dart
  /// cupertino: (context, platform) {
  ///   return CupertinoAppData(
  ///     color: CupertinoColors.systemBlue,
  ///     showPerformanceOverlay: true,
  ///   );
  /// }
  /// ```
  final CupertinoAppData Function(BuildContext, PlatformTarget)? cupertino;

  @override
  Widget build(BuildContext context) {
    final platform = _detectPlatform();
    final isRouter =
        routerConfig != null ||
        routerDelegate != null ||
        routeInformationParser != null;

    if (PlatformInfo.isIOS) {
      return _buildCupertinoApp(context, platform, isRouter);
    }

    return _buildMaterialApp(context, platform, isRouter);
  }

  Widget _buildCupertinoApp(
    BuildContext context,
    PlatformTarget platform,
    bool isRouter,
  ) {
    final config =
        cupertino?.call(context, platform) ?? const CupertinoAppData();

    // We need to wrap CupertinoApp in a builder to get system brightness
    // CupertinoApp doesn't have themeMode like MaterialApp, so we manually
    // detect brightness and apply the appropriate theme
    return Builder(
      builder: (context) {
        // Get system brightness to determine which theme to use
        final brightness = MediaQuery.platformBrightnessOf(context);
        final isDark =
            themeMode == ThemeMode.dark ||
            (themeMode != ThemeMode.light && brightness == Brightness.dark);

        // Use dark theme if dark mode, otherwise light theme
        final effectiveLightTheme =
            cupertinoLightTheme ??
            const CupertinoThemeData(brightness: Brightness.light);
        final effectiveDarkTheme =
            cupertinoDarkTheme ??
            const CupertinoThemeData(brightness: Brightness.dark);

        final theme = isDark ? effectiveDarkTheme : effectiveLightTheme;

        if (isRouter) {
          return CupertinoApp.router(
            key: key,
            routerConfig: routerConfig,
            routeInformationProvider: routeInformationProvider,
            routeInformationParser: routeInformationParser,
            routerDelegate: routerDelegate,
            backButtonDispatcher: backButtonDispatcher,
            builder: builder,
            title: title,
            onGenerateTitle: onGenerateTitle,
            color: config.color,
            theme: theme,
            locale: locale,
            localizationsDelegates: localizationsDelegates,
            localeListResolutionCallback: localeListResolutionCallback,
            localeResolutionCallback: localeResolutionCallback,
            supportedLocales: supportedLocales,
            showPerformanceOverlay: config.showPerformanceOverlay,
            checkerboardRasterCacheImages: config.checkerboardRasterCacheImages,
            checkerboardOffscreenLayers: config.checkerboardOffscreenLayers,
            showSemanticsDebugger: config.showSemanticsDebugger,
            debugShowCheckedModeBanner: config.debugShowCheckedModeBanner,
            shortcuts: config.shortcuts,
            actions: config.actions,
            restorationScopeId: config.restorationScopeId,
            scrollBehavior: config.scrollBehavior,
          );
        }

        return CupertinoApp(
          key: key,
          navigatorKey: navigatorKey,
          home: home,
          routes: routes,
          initialRoute: initialRoute,
          onGenerateRoute: onGenerateRoute,
          onGenerateInitialRoutes: onGenerateInitialRoutes,
          onUnknownRoute: onUnknownRoute,
          navigatorObservers: navigatorObservers,
          builder: builder,
          title: title,
          onGenerateTitle: onGenerateTitle,
          color: config.color,
          theme: theme,
          locale: locale,
          localizationsDelegates: localizationsDelegates,
          localeListResolutionCallback: localeListResolutionCallback,
          localeResolutionCallback: localeResolutionCallback,
          supportedLocales: supportedLocales,
          showPerformanceOverlay: config.showPerformanceOverlay,
          checkerboardRasterCacheImages: config.checkerboardRasterCacheImages,
          checkerboardOffscreenLayers: config.checkerboardOffscreenLayers,
          showSemanticsDebugger: config.showSemanticsDebugger,
          debugShowCheckedModeBanner: config.debugShowCheckedModeBanner,
          shortcuts: config.shortcuts,
          actions: config.actions,
          restorationScopeId: config.restorationScopeId,
          scrollBehavior: config.scrollBehavior,
        );
      },
    );
  }

  Widget _buildMaterialApp(
    BuildContext context,
    PlatformTarget platform,
    bool isRouter,
  ) {
    final config = material?.call(context, platform) ?? const MaterialAppData();

    if (isRouter) {
      return MaterialApp.router(
        key: key,
        routerConfig: routerConfig,
        routeInformationProvider: routeInformationProvider,
        routeInformationParser: routeInformationParser,
        routerDelegate: routerDelegate,
        backButtonDispatcher: backButtonDispatcher,
        builder: builder,
        title: title,
        onGenerateTitle: onGenerateTitle,
        color: config.color,
        theme: materialLightTheme,
        darkTheme: materialDarkTheme,
        themeMode: themeMode ?? ThemeMode.system,
        locale: locale,
        localizationsDelegates: localizationsDelegates,
        localeListResolutionCallback: localeListResolutionCallback,
        localeResolutionCallback: localeResolutionCallback,
        supportedLocales: supportedLocales,
        debugShowMaterialGrid: config.debugShowMaterialGrid,
        showPerformanceOverlay: config.showPerformanceOverlay,
        checkerboardRasterCacheImages: config.checkerboardRasterCacheImages,
        checkerboardOffscreenLayers: config.checkerboardOffscreenLayers,
        showSemanticsDebugger: config.showSemanticsDebugger,
        debugShowCheckedModeBanner: config.debugShowCheckedModeBanner,
        shortcuts: config.shortcuts,
        actions: config.actions,
        restorationScopeId: config.restorationScopeId,
        scrollBehavior: config.scrollBehavior,
        highContrastTheme: config.highContrastTheme,
        highContrastDarkTheme: config.highContrastDarkTheme,
      );
    }

    return MaterialApp(
      key: key,
      navigatorKey: navigatorKey,
      home: home,
      routes: routes,
      initialRoute: initialRoute,
      onGenerateRoute: onGenerateRoute,
      onGenerateInitialRoutes: onGenerateInitialRoutes,
      onUnknownRoute: onUnknownRoute,
      navigatorObservers: navigatorObservers,
      builder: builder,
      title: title,
      onGenerateTitle: onGenerateTitle,
      color: config.color,
      theme: materialLightTheme,
      darkTheme: materialDarkTheme,
      themeMode: themeMode ?? ThemeMode.system,
      locale: locale,
      localizationsDelegates: localizationsDelegates,
      localeListResolutionCallback: localeListResolutionCallback,
      localeResolutionCallback: localeResolutionCallback,
      supportedLocales: supportedLocales,
      debugShowMaterialGrid: config.debugShowMaterialGrid,
      showPerformanceOverlay: config.showPerformanceOverlay,
      checkerboardRasterCacheImages: config.checkerboardRasterCacheImages,
      checkerboardOffscreenLayers: config.checkerboardOffscreenLayers,
      showSemanticsDebugger: config.showSemanticsDebugger,
      debugShowCheckedModeBanner: config.debugShowCheckedModeBanner,
      shortcuts: config.shortcuts,
      actions: config.actions,
      restorationScopeId: config.restorationScopeId,
      scrollBehavior: config.scrollBehavior,
      highContrastTheme: config.highContrastTheme,
      highContrastDarkTheme: config.highContrastDarkTheme,
    );
  }

  PlatformTarget _detectPlatform() {
    if (PlatformInfo.isIOS26OrHigher()) {
      return PlatformTarget.ios26Plus;
    } else if (PlatformInfo.isIOS18OrLower()) {
      return PlatformTarget.ios18OrLower;
    } else if (PlatformInfo.isIOS) {
      return PlatformTarget.ios;
    } else if (PlatformInfo.isAndroid) {
      return PlatformTarget.android;
    } else if (PlatformInfo.isWeb) {
      return PlatformTarget.web;
    } else if (PlatformInfo.isMacOS) {
      return PlatformTarget.desktop;
    }
    return PlatformTarget.other;
  }
}
