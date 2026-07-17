import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';

void main() {
  setUp(() {
    PlatformInfo.setPlatformOverride(PlatformOverride.android);
    PlatformInfo.setPreferCupertinoControls(true);
  });

  tearDown(() {
    PlatformInfo.setPreferCupertinoControls(false);
    PlatformInfo.clearPlatformOverride();
  });

  testWidgets(
      'liquid glass input dialog closes the root route after its caller unmounts',
      (tester) async {
    final nestedNavigatorKey = GlobalKey<NavigatorState>();
    String? dialogResult;
    var primaryActionCount = 0;
    var callerVisible = true;

    await tester.pumpWidget(
      CupertinoApp(
        home: AppDisplaySurfaceScope(
          surface: AppDisplaySurface.phone,
          child: Navigator(
            key: nestedNavigatorKey,
            onGenerateRoute: (_) => CupertinoPageRoute<void>(
              builder: (_) => const CupertinoPageScaffold(
                child: Center(child: Text('Nested home')),
              ),
            ),
          ),
        ),
      ),
    );

    nestedNavigatorKey.currentState!.push(
      CupertinoPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (context, setState) => CupertinoPageScaffold(
            child: Center(
              child: callerVisible
                  ? Builder(
                      builder: (callerContext) => CupertinoButton(
                        onPressed: () async {
                          final result = AdaptiveAlertDialog.inputShow(
                            context: callerContext,
                            title: 'Connect to Jellyfin Server',
                            actions: [
                              AlertAction(
                                title: 'Cancel',
                                style: AlertActionStyle.cancel,
                                onPressed: () {},
                              ),
                              AlertAction(
                                title: 'Next',
                                style: AlertActionStyle.primary,
                                onPressed: () => primaryActionCount++,
                              ),
                            ],
                            input: const AdaptiveAlertDialogInput(
                              placeholder: 'Server URL',
                              initialValue: '192.168.3.49:8096',
                            ),
                          );
                          setState(() => callerVisible = false);
                          dialogResult = await result;
                        },
                        child: const Text('Open input'),
                      ),
                    )
                  : const Text('Caller removed'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open input'));
    await tester.pumpAndSettle();

    expect(find.text('Caller removed'), findsOneWidget);
    expect(find.byType(GlassDialog), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(dialogResult, '192.168.3.49:8096');
    expect(primaryActionCount, 1);
    expect(find.byType(GlassDialog), findsNothing);
    expect(find.text('Caller removed'), findsOneWidget);
    expect(nestedNavigatorKey.currentState!.canPop(), isTrue);
  });
}
