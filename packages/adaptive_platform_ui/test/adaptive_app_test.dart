import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

void main() {
  group('AdaptiveApp', () {
    testWidgets('creates app with home page', (WidgetTester tester) async {
      await tester.pumpWidget(
        AdaptiveApp(home: const Scaffold(body: Text('Home Page'))),
      );

      expect(find.text('Home Page'), findsOneWidget);
    });

    testWidgets('creates app with title', (WidgetTester tester) async {
      await tester.pumpWidget(
        AdaptiveApp(
          title: 'Test App',
          home: const Scaffold(body: Text('Content')),
        ),
      );

      expect(find.text('Content'), findsOneWidget);
      // Title is not directly visible in the widget tree but should be set
    });

    testWidgets('creates app with routes', (WidgetTester tester) async {
      await tester.pumpWidget(
        AdaptiveApp(
          initialRoute: '/',
          routes: {
            '/': (context) => const Scaffold(body: Text('Home')),
            '/second': (context) => const Scaffold(body: Text('Second')),
          },
        ),
      );

      expect(find.text('Home'), findsOneWidget);

      // Navigate to second route
      final context = tester.element(find.text('Home'));
      Navigator.of(context).pushNamed('/second');
      await tester.pumpAndSettle();

      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('respects initialRoute', (WidgetTester tester) async {
      await tester.pumpWidget(
        AdaptiveApp(
          initialRoute: '/second',
          routes: {
            '/': (context) => const Scaffold(body: Text('Home')),
            '/second': (context) => const Scaffold(body: Text('Second')),
          },
        ),
      );

      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('calls onGenerateRoute for unknown routes', (
      WidgetTester tester,
    ) async {
      bool onGenerateRouteCalled = false;

      await tester.pumpWidget(
        AdaptiveApp(
          home: const Scaffold(body: Text('Home')),
          onGenerateRoute: (settings) {
            onGenerateRouteCalled = true;
            if (settings.name == '/custom') {
              return MaterialPageRoute(
                builder: (context) => const Scaffold(body: Text('Custom')),
              );
            }
            return null;
          },
        ),
      );

      final context = tester.element(find.text('Home'));
      Navigator.of(context).pushNamed('/custom');
      await tester.pumpAndSettle();

      expect(onGenerateRouteCalled, isTrue);
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('calls onUnknownRoute for invalid routes', (
      WidgetTester tester,
    ) async {
      bool onUnknownRouteCalled = false;

      await tester.pumpWidget(
        AdaptiveApp(
          home: const Scaffold(body: Text('Home')),
          onUnknownRoute: (settings) {
            onUnknownRouteCalled = true;
            return MaterialPageRoute(
              builder: (context) => const Scaffold(body: Text('Not Found')),
            );
          },
          onGenerateRoute: (settings) =>
              null, // Return null to trigger onUnknownRoute
        ),
      );

      final context = tester.element(find.text('Home'));
      Navigator.of(context).pushNamed('/invalid');
      await tester.pumpAndSettle();

      expect(onUnknownRouteCalled, isTrue);
      expect(find.text('Not Found'), findsOneWidget);
    });

    testWidgets('uses builder to wrap content', (WidgetTester tester) async {
      await tester.pumpWidget(
        AdaptiveApp(
          builder: (context, child) {
            return Column(
              children: [
                const Text('Builder Wrapper'),
                Expanded(child: child!),
              ],
            );
          },
          home: const Scaffold(body: Text('Content')),
        ),
      );

      expect(find.text('Content'), findsOneWidget);
      expect(find.text('Builder Wrapper'), findsOneWidget);
    });

    testWidgets('respects navigatorKey', (WidgetTester tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        AdaptiveApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Home')),
        ),
      );

      expect(navigatorKey.currentState, isNotNull);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('supports navigator observers', (WidgetTester tester) async {
      final observer = NavigatorObserver();

      await tester.pumpWidget(
        AdaptiveApp(
          navigatorObservers: [observer],
          home: const Scaffold(body: Text('Home')),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('uses onGenerateTitle callback', (WidgetTester tester) async {
      String? generatedTitle;

      await tester.pumpWidget(
        AdaptiveApp(
          onGenerateTitle: (context) {
            generatedTitle = 'Generated Title';
            return generatedTitle!;
          },
          home: const Scaffold(body: Text('Home')),
        ),
      );

      await tester.pumpAndSettle();
      expect(generatedTitle, 'Generated Title');
    });

    testWidgets('respects supportedLocales', (WidgetTester tester) async {
      await tester.pumpWidget(
        const AdaptiveApp(
          supportedLocales: [Locale('en', 'US'), Locale('tr', 'TR')],
          home: Scaffold(body: Text('Multi-locale App')),
        ),
      );

      expect(find.text('Multi-locale App'), findsOneWidget);
    });

    testWidgets('applies material theme on Android', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        AdaptiveApp(
          materialLightTheme: ThemeData(
            primaryColor: Colors.red,
            brightness: Brightness.light,
          ),
          home: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              return Scaffold(body: Text('Primary: ${theme.primaryColor}'));
            },
          ),
        ),
      );

      expect(find.textContaining('Primary:'), findsOneWidget);
    });

    testWidgets('applies dark theme when themeMode is dark', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        AdaptiveApp(
          themeMode: ThemeMode.dark,
          materialDarkTheme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              return Scaffold(body: Text('Brightness: ${theme.brightness}'));
            },
          ),
        ),
      );

      expect(find.text('Brightness: Brightness.dark'), findsOneWidget);
    });

    testWidgets('material callback receives correct parameters', (
      WidgetTester tester,
    ) async {
      PlatformTarget? receivedPlatform;

      await tester.pumpWidget(
        AdaptiveApp(
          material: (context, platform) {
            receivedPlatform = platform;
            return const MaterialAppData(debugShowCheckedModeBanner: false);
          },
          home: const Scaffold(body: Text('Test')),
        ),
      );

      expect(receivedPlatform, isNotNull);
      expect(find.text('Test'), findsOneWidget);
    });
  });

  group('AdaptiveApp.router', () {
    testWidgets('creates router app', (WidgetTester tester) async {
      final routerConfig = RouterConfig<Object>(
        routeInformationProvider: PlatformRouteInformationProvider(
          initialRouteInformation: RouteInformation(uri: Uri(path: '/')),
        ),
        routeInformationParser: _TestRouteInformationParser(),
        routerDelegate: _TestRouterDelegate(),
      );

      await tester.pumpWidget(AdaptiveApp.router(routerConfig: routerConfig));

      expect(find.text('Router Home'), findsOneWidget);
    });

    testWidgets('router app uses builder', (WidgetTester tester) async {
      final routerConfig = RouterConfig<Object>(
        routeInformationProvider: PlatformRouteInformationProvider(
          initialRouteInformation: RouteInformation(uri: Uri(path: '/')),
        ),
        routeInformationParser: _TestRouteInformationParser(),
        routerDelegate: _TestRouterDelegate(),
      );

      await tester.pumpWidget(
        AdaptiveApp.router(
          routerConfig: routerConfig,
          builder: (context, child) {
            return Column(
              children: [
                const Text('Router Wrapper'),
                Expanded(child: child!),
              ],
            );
          },
        ),
      );

      expect(find.text('Router Home'), findsOneWidget);
      expect(find.text('Router Wrapper'), findsOneWidget);
    });

    testWidgets('router app respects title', (WidgetTester tester) async {
      final routerConfig = RouterConfig<Object>(
        routeInformationProvider: PlatformRouteInformationProvider(
          initialRouteInformation: RouteInformation(uri: Uri(path: '/')),
        ),
        routeInformationParser: _TestRouteInformationParser(),
        routerDelegate: _TestRouterDelegate(),
      );

      await tester.pumpWidget(
        AdaptiveApp.router(routerConfig: routerConfig, title: 'Router App'),
      );

      expect(find.text('Router Home'), findsOneWidget);
    });
  });

  group('MaterialAppData', () {
    test('creates MaterialAppData with default values', () {
      const data = MaterialAppData();

      expect(data.color, isNull);
      expect(data.debugShowMaterialGrid, false);
      expect(data.showPerformanceOverlay, false);
      expect(data.checkerboardRasterCacheImages, false);
      expect(data.checkerboardOffscreenLayers, false);
      expect(data.showSemanticsDebugger, false);
      expect(data.debugShowCheckedModeBanner, false);
    });

    test('creates MaterialAppData with custom values', () {
      const data = MaterialAppData(
        color: Colors.red,
        debugShowMaterialGrid: true,
        showPerformanceOverlay: true,
        debugShowCheckedModeBanner: true,
      );

      expect(data.color, Colors.red);
      expect(data.debugShowMaterialGrid, true);
      expect(data.showPerformanceOverlay, true);
      expect(data.debugShowCheckedModeBanner, true);
    });
  });

  group('CupertinoAppData', () {
    test('creates CupertinoAppData with default values', () {
      const data = CupertinoAppData();

      expect(data.color, isNull);
      expect(data.showPerformanceOverlay, false);
      expect(data.checkerboardRasterCacheImages, false);
      expect(data.checkerboardOffscreenLayers, false);
      expect(data.showSemanticsDebugger, false);
      expect(data.debugShowCheckedModeBanner, false);
    });

    test('creates CupertinoAppData with custom values', () {
      const data = CupertinoAppData(
        color: CupertinoColors.systemBlue,
        showPerformanceOverlay: true,
        debugShowCheckedModeBanner: true,
      );

      expect(data.color, CupertinoColors.systemBlue);
      expect(data.showPerformanceOverlay, true);
      expect(data.debugShowCheckedModeBanner, true);
    });
  });

  group('PlatformTarget', () {
    test('has all expected enum values', () {
      expect(PlatformTarget.values, contains(PlatformTarget.android));
      expect(PlatformTarget.values, contains(PlatformTarget.ios));
      expect(PlatformTarget.values, contains(PlatformTarget.ios26Plus));
      expect(PlatformTarget.values, contains(PlatformTarget.ios18OrLower));
      expect(PlatformTarget.values, contains(PlatformTarget.web));
      expect(PlatformTarget.values, contains(PlatformTarget.desktop));
      expect(PlatformTarget.values, contains(PlatformTarget.other));
    });
  });
}

// Test router implementation
class _TestRouteInformationParser extends RouteInformationParser<String> {
  @override
  Future<String> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    return routeInformation.uri.path;
  }

  @override
  RouteInformation restoreRouteInformation(String configuration) {
    return RouteInformation(uri: Uri.parse(configuration));
  }
}

class _TestRouterDelegate extends RouterDelegate<String>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<String> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  String _currentPath = '/';

  @override
  String get currentConfiguration => _currentPath;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      pages: const [MaterialPage(child: Scaffold(body: Text('Router Home')))],
      onDidRemovePage: (page) {},
    );
  }

  @override
  Future<void> setNewRoutePath(String configuration) async {
    _currentPath = configuration;
    notifyListeners();
  }
}
