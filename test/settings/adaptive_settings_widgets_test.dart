import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';

void main() {
  testWidgets('phone settings page provides a Material ancestor',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveSettingsScope(
          style: AdaptiveSettingsStyle.phone,
          child: AdaptiveSettingsPage(
            children: [
              Chip(label: Text('Selected library')),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Selected library'), findsOneWidget);
  });
}
