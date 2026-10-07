import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_debug_log_viewer_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bangumi_collection_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

void main() {
  testWidgets(
      '5000 log rows do not rebuild on scrolling or selection-only edits',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final logs = DebugLogService();
    logs.clearLogs();
    for (var i = 0; i < 5000; i++) {
      logs.addLog('test log $i');
    }
    await tester
        .pumpWidget(const CupertinoApp(home: CupertinoDebugLogViewerSheet()));
    await tester.pumpAndSettle();
    final scroll =
        tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    final beforeScroll = tester.widget<SliverList>(find.byType(SliverList));
    scroll.controller!.jumpTo(500);
    await tester.pump();
    expect(
        identical(
            beforeScroll, tester.widget<SliverList>(find.byType(SliverList))),
        isTrue);
    scroll.controller!.jumpTo(0);
    await tester.pump();
    final search = tester.widget<CupertinoSearchTextField>(
        find.byType(CupertinoSearchTextField));
    search.controller!.text = 'test';
    await tester.pump();
    final beforeSelection = tester.widget<SliverList>(find.byType(SliverList));
    search.controller!.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(
        identical(beforeSelection,
            tester.widget<SliverList>(find.byType(SliverList))),
        isTrue);
    await tester.pumpWidget(const SizedBox());
    logs.clearLogs();
  });

  test('title opacity changes do not notify the entire sheet', () {
    final controller = CupertinoBottomSheetPageController(rootTitle: 'Logs');
    var sheetNotifications = 0;
    var titleNotifications = 0;
    controller.addListener(() => sheetNotifications++);
    controller.titleOpacityListenable.addListener(() => titleNotifications++);
    controller.setTitleOpacity(.5);
    controller.setTitleOpacity(0);
    controller.setTitleOpacity(-100);
    expect(sheetNotifications, 0);
    expect(titleNotifications, 2);
    expect(controller.titleOpacity, 0);
    controller.dispose();
  });

  testWidgets(
      'comment edits preserve composing and do not rebuild form sections',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(CupertinoApp(
        home: CupertinoBangumiCollectionSheet(
      animeTitle: 'Title',
      initialRating: 8,
      initialCollectionType: 3,
      initialComment: '',
      initialEpisodeStatus: 1,
      totalEpisodes: 12,
      isSubmitting: false,
      onSubmit: (_) async => true,
      onCancel: () {},
    )));
    final comment = find.byWidgetPredicate(
        (widget) => widget is CupertinoTextField && widget.minLines == 3);
    await tester.ensureVisible(comment);
    await tester.tap(comment);
    await tester.pump();
    final before = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .firstWhere((field) => field.minLines != 3);
    const composing = TextEditingValue(
        text: 'pinyin',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 0, end: 6));
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    final controller = tester.widget<CupertinoTextField>(comment).controller!;
    expect(controller.value, composing);
    expect(find.text('6/200'), findsOneWidget);
    final after = tester
        .widgetList<CupertinoTextField>(find.byType(CupertinoTextField))
        .firstWhere((field) => field.minLines != 3);
    expect(identical(before, after), isTrue);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '拼音', selection: TextSelection.collapsed(offset: 2)));
    await tester.pump();
    expect(find.text('2/200'), findsOneWidget);
    expect(controller.value.composing, TextRange.empty);
  });
}
