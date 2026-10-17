import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/cards/card_views.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

/// A choices card answers once: picking an option says its label in the
/// conversation, the card settles on it and the other options step back.
void main() {
  testWidgets('a choice is said once and the card settles on it',
      (tester) async {
    final said = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: CardStack(
          cards: const [
            UiChoicesCard([
              UiChoice('BD 合集', detail: '1080p · 8 GB', recommended: true),
              UiChoice('先来一集'),
            ], question: '要哪个版本？'),
          ],
          callbacks: CardCallbacks(onChoose: said.add),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('要哪个版本？'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
    await tester.tap(find.text('先来一集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BD 合集'));
    await tester.pumpAndSettle();
    expect(said, ['先来一集']);
  });
}
