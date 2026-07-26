import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';

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
}
