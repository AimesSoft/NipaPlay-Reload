import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final surface in [
    AppDisplaySurface.phone,
    AppDisplaySurface.desktopTablet,
  ]) {
    for (final confirmed in [false, true]) {
      testWidgets(
          '$surface confirmation returns $confirmed without popping caller',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        final nestedNavigator = GlobalKey<NavigatorState>();
        bool? result;
        var completed = false;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(
                  create: (_) => AppearanceSettingsProvider()),
              ChangeNotifierProvider(create: (_) => BottomBarProvider()),
            ],
            child: MaterialApp(
              home: AppDisplaySurfaceScope(
                surface: surface,
                child: Navigator(
                  key: nestedNavigator,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('Home')),
                  ),
                ),
              ),
            ),
          ),
        );
        nestedNavigator.currentState!.push(MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await BlurDialog.show<bool>(
                  context: context,
                  title: '确认恢复',
                  content: '是否继续？',
                  actionsBuilder: (dialogContext) => [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('确认'),
                    ),
                  ],
                );
                completed = true;
              },
              child: const Text('Open confirmation'),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open confirmation'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(confirmed ? '确认' : '取消'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(completed, isTrue);
        expect(result, confirmed);
        expect(find.text('确认恢复'), findsNothing);
        expect(find.text('Open confirmation'), findsOneWidget);
        expect(nestedNavigator.currentState!.canPop(), isTrue);
      });
    }
  }
}
