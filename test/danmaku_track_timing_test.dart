import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageScaffold;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next_engine.dart';
import 'package:nipaplay/utils/danmaku_track_timing.dart';
import 'package:nipaplay/widgets/danmaku_track_offset_button.dart';

void main() {
  test('existing tracks and invalid stored offsets keep their original time',
      () {
    expect(DanmakuTrackTiming.offsetOf({}), 0);
    expect(DanmakuTrackTiming.offsetOf({'timeOffset': double.infinity}), 0);
    expect(DanmakuTrackTiming.offsetOf({'timeOffset': -0.25}), -0.25);
  });
  test('editing and resetting one track preserves both source timelines', () {
    final first = {'time': 12.0, 'content': 'first'};
    final second = {'time': 12.0, 'content': 'second'};
    expect(DanmakuTrackTiming.shift(first, 2)['time'], 10);
    expect(DanmakuTrackTiming.shift(second, -3)['time'], 15);
    expect(DanmakuTrackTiming.shift(first, 4)['time'], 8);
    expect(DanmakuTrackTiming.shift(first, 0)['time'], 12);
    expect(first['time'], 12);
    expect(second['time'], 12);
  });

  test('offsets support fractional and negative timestamps and legacy t keys',
      () {
    final comment = {'t': '0.25', 'content': 'start', 'isMe': true};
    final adjusted = DanmakuTrackTiming.shift(comment, 0.5);
    expect(adjusted['time'], -0.25);
    expect(adjusted['t'], -0.25);
    expect(adjusted['isMe'], isTrue);
    expect(comment['t'], '0.25');
  });

  testWidgets('track timing combines with the global playback offset',
      (tester) async {
    final engine = NipaPlayNextEngine();
    addTearDown(engine.dispose);
    engine.configure(
      danmakuList: [
        DanmakuTrackTiming.shift({'time': 12.0, 'content': 'advanced'}, 2),
        DanmakuTrackTiming.shift({'time': 12.0, 'content': 'unmodified'}, 0),
      ],
      size: const Size(800, 450),
      fontSize: 24,
      displayArea: 1,
      scrollDurationSeconds: 10,
      allowStacking: false,
      mergeDanmaku: false,
    );
    expect(engine.layout(9), isEmpty);
    // Video time 9 plus global offset 1 shows only the individually advanced track.
    expect(engine.layout(9 + 1).map((item) => item.content.text), ['advanced']);
    expect(engine.layout(12).map((item) => item.content.text),
        containsAll(['advanced', 'unmodified']));
  });

  Future<void> openEditor(
      WidgetTester tester, ValueChanged<double> onChanged) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: DanmakuTrackOffsetButton(
        trackName: '本地弹幕',
        offset: 2,
        onChanged: onChanged,
      )),
    ));
    await tester.tap(find.byIcon(Icons.more_time));
    await tester.pumpAndSettle();
  }

  testWidgets('editor applies fractional offsets and rejects nonfinite input',
      (tester) async {
    double? result;
    await openEditor(tester, (value) => result = value);
    await tester.enterText(find.byType(TextField), 'NaN');
    await tester.tap(find.text('应用'));
    await tester.pump();
    expect(find.text('请输入有效的秒数'), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(find.byType(TextField), '-1,25');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(result, -1.25);
  });

  testWidgets('editor reset removes this track offset', (tester) async {
    double? result;
    await openEditor(tester, (value) => result = value);
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(result, 0);
  });

  testWidgets('cancel does not change the track', (tester) async {
    double? result;
    await openEditor(tester, (value) => result = value);
    await tester.enterText(find.byType(TextField), '15');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('editor also works in a menu without a Material surface',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CupertinoPageScaffold(
          child: DanmakuTrackOffsetButton(
        trackName: '本地弹幕',
        offset: 0,
        onChanged: (_) {},
      )),
    ));
    await tester.tap(find.byIcon(Icons.more_time));
    await tester.pumpAndSettle();
    expect(find.text('本地弹幕 · 调轴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
