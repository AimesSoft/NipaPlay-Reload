import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/widgets/danmaku_track_offset_button.dart';
import 'package:nipaplay/widgets/desktop_transient_overlay_scope.dart';

void main() {
  for (final reset in [true, false]) {
    testWidgets(
        'popup barrier is removed before first ${reset ? "reset" : "field"} click',
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: SizedBox.expand()),
      ));
      late OverlayEntry barrier;
      late OverlayEntry menu;
      var closeCount = 0;
      double? result;
      void close() {
        closeCount++;
        barrier.remove();
        menu.remove();
      }

      barrier = OverlayEntry(
          builder: (_) => Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: close,
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ));
      menu = OverlayEntry(
          builder: (_) => Positioned(
                top: 10,
                right: 10,
                child: DesktopTransientOverlayScope(
                  close: close,
                  child: DanmakuTrackOffsetButton(
                    trackName: 'popup track',
                    offset: 2,
                    onChanged: (value) => result = value,
                  ),
                ),
              ));
      navigator.currentState!.overlay!.insertAll([barrier, menu]);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_time));
      await tester.pumpAndSettle();
      expect(closeCount, 1);
      expect(find.byType(DesktopTransientOverlayScope), findsNothing);
      if (reset) {
        await tester.tap(find.text('重置'));
        await tester.pumpAndSettle();
        expect(result, 0);
      } else {
        await tester.tap(find.byType(TextField));
        await tester.pump();
        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.focusNode.hasFocus, isTrue);
        await tester.enterText(find.byType(TextField), '-3');
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        expect(result, -3);
      }
      expect(closeCount, 1);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      barrier.dispose();
      menu.dispose();
    });
  }
}
