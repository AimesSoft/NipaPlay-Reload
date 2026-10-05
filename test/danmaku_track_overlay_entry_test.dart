import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/widgets/danmaku_track_offset_button.dart';
import 'package:nipaplay/widgets/desktop_transient_overlay_scope.dart';

void main() {
  for (final reset in [true, false]) {
    testWidgets(
        'ordinary menu entry closes before first ${reset ? "reset" : "input"} click',
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(),
      ));
      late OverlayEntry entry;
      var closeCount = 0;
      double? result;
      void close() {
        closeCount++;
        entry.remove();
      }

      // Mirrors VideoSettingsMenu's ordinary OverlayEntry structure: the
      // barrier and pane share one entry, and the owner scope wraps the pane.
      entry = OverlayEntry(
          builder: (_) => Positioned.fill(
                  child: Stack(
                children: [
                  Positioned.fill(
                      child: GestureDetector(
                    onTap: close,
                    child: const ColoredBox(color: Colors.transparent),
                  )),
                  Positioned(
                      top: 10,
                      right: 10,
                      child: DesktopTransientOverlayScope(
                        close: close,
                        child: DanmakuTrackOffsetButton(
                          trackName: 'ordinary track',
                          offset: 2,
                          onChanged: (value) => result = value,
                        ),
                      )),
                ],
              )));
      navigator.currentState!.overlay!.insert(entry);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_time));
      await tester.pumpAndSettle();
      expect(closeCount, 1);
      expect(find.byType(DesktopTransientOverlayScope), findsNothing);
      if (reset) {
        await tester.tap(find.text('重置'));
      } else {
        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '-3');
        await tester.tap(find.text('应用'));
      }
      await tester.pumpAndSettle();
      expect(result, reset ? 0 : -3);
      expect(closeCount, 1);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      entry.dispose();
    });
  }
}
