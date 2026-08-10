import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:provider/provider.dart';

class _FilledScreenAppearanceSettingsProvider
    extends AppearanceSettingsProvider {
  @override
  NipaplayWindowDisplayMode get windowDisplayMode =>
      NipaplayWindowDisplayMode.filledScreen;
}

void main() {
  testWidgets('embedded window provides a Material ancestor', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: NipaplayWindowScaffold(
          embedded: true,
          child: InkWell(
            onTap: () {},
            child: const Text('Tap target'),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Tap target'), findsOneWidget);
  });

  testWidgets('filled-screen window can respect supplied maximum size',
      (tester) async {
    final appearance = _FilledScreenAppearanceSettingsProvider();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppearanceSettingsProvider>.value(
        value: appearance,
        child: const MaterialApp(
          home: NipaplayWindowScaffold(
            respectMaxSizeInFilledScreen: true,
            maxWidth: 600,
            maxHeightFactor: 0.5,
            child: SizedBox.expand(
              key: Key('window-content'),
              child: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final contentSize = tester.getSize(find.byKey(const Key('window-content')));
    expect(contentSize.width, closeTo(580, 0.1));
    expect(contentSize.height, closeTo(366, 0.1));
  });
}
