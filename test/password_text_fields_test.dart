import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';

void main() {
  tearDown(PlatformInfo.clearPlatformOverride);

  void expectPassword(WidgetTester tester) {
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.keyboardType, TextInputType.visiblePassword);
    expect(editable.autocorrect, isFalse);
    expect(editable.enableSuggestions, isFalse);
    expect(editable.smartDashesType, SmartDashesType.disabled);
    expect(editable.smartQuotesType, SmartQuotesType.disabled);
    const password = TextEditingValue(text: '  Abc中文🔑—“123  ');
    var formatted = password;
    for (final formatter in editable.inputFormatters ?? []) {
      formatted = formatter.formatEditUpdate(TextEditingValue.empty, formatted);
    }
    expect(formatted, password);
  }

  for (final platform in [PlatformOverride.android, PlatformOverride.ios]) {
    for (final revealed in [false, true]) {
      for (final formField in [false, true]) {
        testWidgets('$platform form=$formField revealed=$revealed password',
            (tester) async {
          PlatformInfo.setPlatformOverride(platform);
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: formField
                  ? AdaptiveTextFormField(
                      controller: controller,
                      obscureText: !revealed,
                      keyboardType:
                          revealed ? TextInputType.visiblePassword : null,
                    )
                  : AdaptiveTextField(
                      controller: controller,
                      obscureText: !revealed,
                      keyboardType:
                          revealed ? TextInputType.visiblePassword : null,
                    ),
            ),
          ));
          expectPassword(tester);
          const password = '  Abc中文🔑—“123  ';
          await tester.enterText(find.byType(EditableText), password);
          expect(controller.text, password);
        });
      }
    }

    testWidgets('$platform normal input keeps text keyboard and correction',
        (tester) async {
      PlatformInfo.setPlatformOverride(platform);
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AdaptiveTextField())));
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.keyboardType, TextInputType.text);
      expect(editable.autocorrect, isTrue);
      expect(editable.enableSuggestions, isTrue);
    });

    testWidgets('$platform password input alert uses password keyboard',
        (tester) async {
      PlatformInfo.setPlatformOverride(platform);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AdaptiveAlertDialog.inputShow(
                context: context,
                title: 'Password',
                input: const AdaptiveAlertDialogInput(
                  placeholder: 'Password',
                  obscureText: true,
                ),
                actions: [AlertAction(title: 'Cancel', onPressed: () {})],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expectPassword(tester);
    });
  }

  for (final surface in AppDisplaySurface.values) {
    testWidgets('media password keyboard on $surface', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppDisplaySurfaceScope(
            surface: surface,
            child: AdaptiveMediaTextField(
              controller: controller,
              obscureText: true,
            ),
          ),
        ),
      ));
      expectPassword(tester);
    });
  }

  for (final revealed in [false, true]) {
    testWidgets('glass password keyboard revealed=$revealed', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GlassTextField(
            obscureText: !revealed,
            keyboardType: revealed ? TextInputType.visiblePassword : null,
            useOwnLayer: true,
            quality: GlassQuality.standard,
          ),
        ),
      ));
      expectPassword(tester);
    });
  }
}
