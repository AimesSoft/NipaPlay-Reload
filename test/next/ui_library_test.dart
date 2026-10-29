import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/library/category_editor.dart';
import 'package:nipaplay/next/ui/library/category_grid.dart';
import 'package:nipaplay/next/ui/library/fan_cover.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/icons.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

/// The 片库 page's parts on their own: a category of thousands loads only
/// the slices that are seen, a new order starts again from the top, the
/// editor takes categories away and keeps the last one, and a cover's fan
/// opens on hover.
void main() {
  Widget host(Widget child, {Size size = const Size(1000, 800)}) => MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      );

  testWidgets('a category of thousands loads the slices that are seen',
      (tester) async {
    final data = _Works(3000);
    final items = CategoryItems(data, 'all', total: 3000);
    final scroll = ScrollController();
    const on = LibraryCallbacks(
        openWork: _ignore, play: _ignore, openFolder: _ignoreFolder);
    await tester.pumpWidget(host(CustomScrollView(
      controller: scroll,
      slivers: [CategoryGrid(items: items, on: on)],
    )));
    await tester.pump(const Duration(milliseconds: 50));
    expect(data.asked.map((a) => a.offset), [0]);
    expect(find.text('作品 0'), findsOneWidget);

    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(data.asked.last.offset, 2940);
    expect(data.asked.length, lessThan(4));
    expect(find.text('作品 2999'), findsOneWidget);
    expect(items.loaded, contains(49));

    items.reorder('title');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(data.asked.last, (offset: 2940, sort: 'title'));
    expect(items.loaded, [49]);
    items.dispose();
  });

  for (final initialTotal in <int?>[0, null]) {
    testWidgets(
        'an empty category shows its first work after refresh '
        '(initial total: $initialTotal)', (tester) async {
      final data = _Works(0);
      final items = CategoryItems(data, 'all', total: initialTotal);
      const on = LibraryCallbacks(
          openWork: _ignore, play: _ignore, openFolder: _ignoreFolder);
      await tester.pumpWidget(host(CustomScrollView(
        slivers: [CategoryGrid(items: items, on: on)],
      )));
      await tester.pump(const Duration(milliseconds: 50));
      expect(items.count, 0);
      expect(find.text('作品 0'), findsNothing);

      data.count = 1;
      items.refresh();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(items.count, 1);
      expect(find.text('作品 0'), findsOneWidget);

      // Removing the last work must not prevent the next arrival either.
      data.count = 0;
      items.refresh();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(items.count, 0);
      expect(find.text('作品 0'), findsNothing);
      data.count = 1;
      items.refresh();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('作品 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      items.dispose();
    });
  }

  testWidgets('the editor takes categories away but keeps the last one',
      (tester) async {
    final removed = <String>[];
    Widget editor(List<UiCategory> categories) => host(CategoryEditor(
          categories: categories,
          onMove: (_, __) {},
          onRemove: removed.add,
          onAskNipa: () {},
        ));
    await tester.pumpWidget(editor(const [
      UiCategory(categoryId: 'a', title: '番剧', count: 1211),
      UiCategory(categoryId: 'b', title: '电影', count: 1),
    ]));
    expect(find.text('番剧'), findsOneWidget);
    final remove = find.byWidgetPredicate(
        (w) => w is NextIconButton && w.label == '移除');
    await tester.tap(remove.last);
    await tester.pump();
    expect(removed, ['b']);
    expect(find.text('电影'), findsNothing);

    await tester.pumpWidget(editor(const [
      UiCategory(categoryId: 'a', title: '番剧', count: 1211),
    ]));
    expect(remove, findsNothing);
    expect(find.text('让梨花整理'), findsOneWidget);
  });

  testWidgets('a category dragged by its grip moves where it is dropped',
      (tester) async {
    final moved = <(String, int)>[];
    await tester.pumpWidget(host(CategoryEditor(
      categories: const [
        UiCategory(categoryId: 'a', title: '番剧'),
        UiCategory(categoryId: 'b', title: '电影'),
        UiCategory(categoryId: 'c', title: '纪录片'),
      ],
      onMove: (id, index) => moved.add((id, index)),
      onRemove: (_) {},
      onAskNipa: () {},
    )));
    final grip = find.byWidgetPredicate(
        (w) => w is NextIcon && w.glyph == NextGlyph.grip);
    final mouse = await tester.startGesture(tester.getCenter(grip.first),
        kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 12; i++) {
      await mouse.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await mouse.up();
    await tester.pumpAndSettle();
    expect(moved, [('a', 2)]);
    final order = [
      for (final t in ['番剧', '电影', '纪录片']) tester.getTopLeft(find.text(t)).dy
    ];
    expect(order[1] < order[2] && order[2] < order[0], isTrue);
  });

  testWidgets('a card\'s fan opens a little on hover', (tester) async {
    await tester.pumpWidget(host(
      CategoryCard(
        title: '番剧',
        count: 1211,
        posters: const ['/nonexistent/a.jpg', '/nonexistent/b.jpg', '/c.jpg'],
        onOpen: () {},
      ),
      size: const Size(420, 260),
    ));
    List<double> angles() => [
          for (final t in tester.widgetList<Transform>(find.descendant(
              of: find.byType(FanCover), matching: find.byType(Transform))))
            t.transform.entry(0, 1),
        ];
    final still = angles();
    expect(still.where((a) => a != 0), hasLength(2));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(CategoryCard)));
    await tester.pumpAndSettle();
    final open = angles();
    for (var i = 0; i < still.length; i++) {
      expect(open[i].abs(), greaterThanOrEqualTo(still[i].abs()));
    }
    double spread(List<double> a) => a.fold(0, (s, v) => s + v.abs());
    expect(spread(open), greaterThan(spread(still) * 1.2));
    await mouse.removePointer();
  });
}

void _ignore(UiWork _) {}
void _ignoreFolder(UiFolderItem _) {}

/// [count] works, answered at once; remembers each slice asked for.
final class _Works implements NextLibraryData {
  _Works(this.count);
  int count;
  final asked = <({int offset, String? sort})>[];

  @override
  Future<UiSlice> items(String categoryId,
      {int offset = 0, int limit = 60, String? sort}) async {
    asked.add((offset: offset, sort: sort));
    final end = (offset + limit).clamp(0, count);
    return UiSlice([
      for (var i = offset; i < end; i++)
        UiWorkItem(UiWork(workId: 'w$i', title: '作品 $i'))
    ], total: count);
  }

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<UiLibraryPage> page(String sourceId) =>
      throw UnimplementedError();

  @override
  Future<List<UiLibrarySource>> sources() => throw UnimplementedError();
}
