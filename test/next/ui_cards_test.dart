import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/cards/card_views.dart';
import 'package:nipaplay/next/ui/widgets/icons.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

/// A choices card answers once: picking an option says its label in the
/// conversation, the card settles on it and the other options step back.
/// A task's row names what it is busy with.
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

  testWidgets(
      'a download with no work yet: its own name, and the download mark '
      'where the art would be', (tester) async {
    Widget row(UiTask task) => MaterialApp(
        home: Material(
            child: SizedBox(
                width: 460,
                child: TaskRow(task: task, callbacks: const CardCallbacks()))));
    Finder mark() => find.byWidgetPredicate(
        (w) => w is NextIcon && w.glyph == NextGlyph.torrent);

    await tester.pumpWidget(row(const UiTask(
        taskId: 't1',
        type: 'download',
        title: '下载 [LoliHouse] Sousou no Frieren - 05 [WebRip 1080p]',
        action: '下载',
        state: UiTaskState.running,
        progress: 0.47)));
    expect(find.text('下载 [LoliHouse] Sousou no Frieren - 05 [WebRip 1080p]'),
        findsOneWidget);
    expect(mark(), findsOneWidget);
    expect(find.textContaining('47%', findRichText: true), findsOneWidget);

    // Placed: the work's art.
    await tester.pumpWidget(row(const UiTask(
        taskId: 't1',
        type: 'download',
        title: '下载《葬送的芙莉莲》',
        workTitle: '葬送的芙莉莲',
        action: '下载',
        state: UiTaskState.running,
        artwork: UiArtwork(backdrop: '/art/frieren.jpg'))));
    expect(mark(), findsNothing);

    // Other tasks keep the plain placeholder.
    await tester.pumpWidget(row(const UiTask(
        taskId: 't2',
        type: 'media.scan',
        title: '整理片库',
        state: UiTaskState.running)));
    expect(mark(), findsNothing);
  });
}
