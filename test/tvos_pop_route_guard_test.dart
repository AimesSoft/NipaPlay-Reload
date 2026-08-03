import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tvos_pop_route_guard.dart';

void main() {
  testWidgets('consumes tvOS popRoute at the application root', (tester) async {
    var rootPopCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: NipaplayTvOSPopRouteGuard(
          enabled: true,
          onRootPopRoute: () {
            rootPopCount += 1;
            return true;
          },
          child: const Scaffold(body: Text('root')),
        ),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(rootPopCount, 1);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('lets the navigator pop a nested route first', (tester) async {
    var rootPopCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: NipaplayTvOSPopRouteGuard(
          enabled: true,
          onRootPopRoute: () {
            rootPopCount += 1;
            return true;
          },
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('nested')),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('nested'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('nested'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(rootPopCount, 0);
  });

  testWidgets('does not intercept popRoute when disabled', (tester) async {
    var rootPopCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: NipaplayTvOSPopRouteGuard(
          enabled: false,
          onRootPopRoute: () {
            rootPopCount += 1;
            return true;
          },
          child: const Scaffold(body: Text('root')),
        ),
      ),
    );

    expect(await tester.binding.handlePopRoute(), isFalse);
    await tester.pumpAndSettle();

    expect(rootPopCount, 0);
  });
}
