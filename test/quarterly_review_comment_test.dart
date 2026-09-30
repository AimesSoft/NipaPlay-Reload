import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/quarterly_review_comment.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('review comment fits a narrow card in $brightness',
        (tester) async {
      final updatedAt = DateTime(2026, 9, 29, 20, 5).millisecondsSinceEpoch;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Center(
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: SizedBox(
              width: 188,
              height: 110,
              child: QuarterlyReviewComment(
                comment: '这一季最喜欢的番剧。' * 12,
                updatedAt: updatedAt,
                onEdit: () {},
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('我的短评'), findsOneWidget);
      expect(find.text('2026/09/29 20:05'), findsOneWidget);
      final panel = tester.widget<Container>(find
          .descendant(
              of: find.byType(QuarterlyReviewComment),
              matching: find.byType(Container))
          .first);
      final decoration = panel.decoration! as BoxDecoration;
      expect(decoration.color, AppAccentColors.current.withValues(alpha: 0.08));
      expect(decoration.border, isNotNull);
    });
  }

  testWidgets('review comment omits an unavailable update time',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SizedBox(
          width: 188,
          height: 110,
          child: QuarterlyReviewComment(comment: '值得回味'),
        ),
      ),
    ));
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('值得回味'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two-line comments keep their width without a scrollbar gutter',
      (tester) async {
    for (final length in [16, 23, 28]) {
      final comment = '评' * length;
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 188,
            height: 100,
            child: QuarterlyReviewComment(
              comment: comment,
              updatedAt: DateTime(2026, 9, 29).millisecondsSinceEpoch,
              onEdit: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      final scrollView = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      expect(scrollbar.thumbVisibility, isFalse, reason: '$length characters');
      expect(scrollbar.controller!.position.maxScrollExtent, 0);
      expect(scrollView.padding, EdgeInsets.zero);
      final textRect = tester.getRect(find.text(comment));
      final viewportRect = tester.getRect(find.byType(SingleChildScrollView));
      expect(textRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
      expect(tester.takeException(), isNull);
    }
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets(
        'minimum comment height fits two complete lines at scale $scale',
        (tester) async {
      const comment = '这是第一行短评\n第二行比较长的短评';
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Builder(builder: (context) {
              // Increase width along with the font so the text remains two lines.
              final width = 188.0 * scale;
              return SizedBox(
                width: width,
                height: QuarterlyReviewComment.minimumHeight(context,
                    width: width,
                    comment: comment,
                    hasTimestamp: true,
                    editable: true),
                child: QuarterlyReviewComment(
                  comment: comment,
                  updatedAt: DateTime(2026, 9, 29).millisecondsSinceEpoch,
                  onEdit: () {},
                ),
              );
            }),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      expect(scrollbar.thumbVisibility, isFalse);
      expect(scrollbar.controller!.position.maxScrollExtent, 0);
      final textRect = tester.getRect(find.text(comment));
      final viewportRect = tester.getRect(find.byType(SingleChildScrollView));
      expect(textRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('edit and long-comment scrolling do not open the anime card',
      (tester) async {
    var edits = 0;
    var detailOpens = 0;
    final comment = '${'长短评内容，需要完整展示。\n' * 30}最后一句';
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: GestureDetector(
          onTap: () => detailOpens++,
          child: SizedBox(
            width: 188,
            height: 110,
            child: QuarterlyReviewComment(
              comment: comment,
              updatedAt: DateTime(2026, 9, 29, 20, 5).millisecondsSinceEpoch,
              onEdit: () => edits++,
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(detailOpens, 0);

    final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
    final scrollView = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    final controller = scrollbar.controller!;
    expect(scrollView.controller, same(controller));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(tester.widget<Text>(find.text(comment)).maxLines, isNull);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(detailOpens, 0);

    // The scrollbar thumb can be dragged all the way to the last line.
    controller.jumpTo(0);
    await tester.pump();
    final bounds = tester.getRect(find.byType(RawScrollbar));
    await tester.dragFrom(
      Offset(bounds.right - 1.5, bounds.top + 9),
      Offset(0, bounds.height * 2),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));
    expect(find.text('2026/09/29 20:05'), findsOneWidget);
    expect(detailOpens, 0);
    expect(tester.takeException(), isNull);

    // Editing the text resets the scroll position without losing the panel.
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: GestureDetector(
          onTap: () => detailOpens++,
          child: SizedBox(
            width: 188,
            height: 110,
            child: QuarterlyReviewComment(
              comment: '修改后的短评',
              onEdit: () => edits++,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(find.text('修改后的短评'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
