import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/menu_button.dart';

void main() {
  testWidgets('player keys cannot activate caption controls after focus loss',
      (tester) async {
    final activations = <String>[];
    final playerFocus = FocusNode(debugLabel: 'player');
    addTearDown(playerFocus.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          WindowControlButtons(
            isMaximized: false,
            onMinimize: () => activations.add('minimize'),
            onMaximizeRestore: () => activations.add('maximize'),
            onClose: () => activations.add('close'),
          ),
          Focus(focusNode: playerFocus, child: const Text('player')),
        ]),
      ),
    ));

    for (final direction in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ]) {
      // Exercise both startup with no selected child and a restored empty
      // scope, as happens when returning to the window during playback.
      playerFocus.requestFocus();
      await tester.pump();
      playerFocus.unfocus(disposition: UnfocusDisposition.scope);
      await tester.pump();
      await tester.sendKeyEvent(direction);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }

    expect(activations, isEmpty);
    for (final icon in [
      Icons.remove_rounded,
      Icons.crop_square_rounded,
      Icons.close_rounded,
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pump();
    }
    expect(activations, ['minimize', 'maximize', 'close']);
  });
}
