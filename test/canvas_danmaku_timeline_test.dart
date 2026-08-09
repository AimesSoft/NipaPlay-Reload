import 'package:danmaku_canvas/canvas_danmaku_renderer.dart';
import 'package:danmaku_canvas/danmaku_controller.dart';
import 'package:danmaku_canvas/danmaku_screen.dart';
import 'package:danmaku_canvas/danmaku_timeline.dart';
import 'package:danmaku_canvas/models/danmaku_content_item.dart';
import 'package:danmaku_canvas/models/danmaku_option.dart';
import 'package:danmaku_canvas/scroll_danmaku_painter.dart';
import 'package:danmaku_canvas/static_danmaku_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CanvasDanmakuTimeline', () {
    test('explicit seek revision catches a sub-two-second seek', () {
      expect(
        CanvasDanmakuTimeline.didSeek(
          previousRevision: 4,
          currentRevision: 5,
          previousTime: 20,
          currentTime: 20.5,
        ),
        isTrue,
      );
      expect(
        CanvasDanmakuTimeline.didSeek(
          previousRevision: 5,
          currentRevision: 5,
          previousTime: 20,
          currentTime: 25,
        ),
        isFalse,
      );
    });

    test('fallback seek detection remains available without a revision', () {
      expect(
        CanvasDanmakuTimeline.didSeek(
          previousRevision: -1,
          currentRevision: -1,
          previousTime: 20,
          currentTime: 22.1,
        ),
        isTrue,
      );
    });

    test('active restoration keeps and sorts more than one batch', () {
      final entries = List.generate(
        45,
        (index) => <String, dynamic>{'time': 10 - index / 10},
      );
      final active = CanvasDanmakuTimeline.activeEntries(
        entries,
        timeOf: (entry) => (entry['time'] as num).toDouble(),
        currentTime: 10,
        lookBackSeconds: 10,
      );

      expect(active, hasLength(45));
      for (var index = 1; index < active.length; index++) {
        expect(
          active[index - 1]['time'],
          lessThanOrEqualTo(active[index]['time']),
        );
      }
    });

    test('rate changes affect only subsequent incremental movement', () {
      final atOneX = CanvasDanmakuTimeline.advanceScrollX(
        currentX: 800,
        previousTick: 0,
        currentTick: 1000,
        viewWidth: 800,
        danmakuWidth: 200,
        durationSeconds: 10,
        playbackRate: 1,
      );
      final nextAtTwoX = CanvasDanmakuTimeline.advanceScrollX(
        currentX: atOneX,
        previousTick: 1000,
        currentTick: 2000,
        viewWidth: 800,
        danmakuWidth: 200,
        durationSeconds: 10,
        playbackRate: 2,
      );

      expect(atOneX, 700);
      expect(nextAtTwoX, 500);
    });

    test('fixed lifetime consumes wall time at the current rate', () {
      expect(
        CanvasDanmakuTimeline.consumeLifetime(
          remainingSeconds: 1,
          wallSeconds: 0.6,
          playbackRate: 2,
        ),
        closeTo(-0.2, 0.0001),
      );
    });

    test('lowerBound locates the first entry at or after the target', () {
      final entries = List.generate(
        10,
        (index) => <String, dynamic>{'time': index * 1.0},
      );
      double timeOf(Map<String, dynamic> entry) =>
          (entry['time'] as num).toDouble();

      // 目标落在区间内：返回第一个 >= 目标的下标
      expect(CanvasDanmakuTimeline.lowerBound(entries, 4.5, timeOf: timeOf), 5);
      // 目标恰好命中元素：返回该元素下标
      expect(CanvasDanmakuTimeline.lowerBound(entries, 4.0, timeOf: timeOf), 4);
      // 目标小于所有元素：返回 0
      expect(CanvasDanmakuTimeline.lowerBound(entries, -1, timeOf: timeOf), 0);
      // 目标大于所有元素：返回 length（空窗口）
      expect(CanvasDanmakuTimeline.lowerBound(entries, 100, timeOf: timeOf), 10);
      // 空列表返回 0
      expect(
        CanvasDanmakuTimeline.lowerBound(
          const <Map<String, dynamic>>[],
          0,
          timeOf: timeOf,
        ),
        0,
      );
    });
  });

  group('ScrollDanmakuCollision', () {
    test('rejects overlap at a seek-restored x position', () {
      expect(
        ScrollDanmakuCollision.canPlace(
          existing: const [(x: 760.0, width: 200.0)],
          candidateX: 880,
          candidateWidth: 200,
          viewWidth: 1000,
          durationSeconds: 10,
        ),
        isFalse,
      );
    });

    test('accepts a candidate that cannot catch the previous item', () {
      expect(
        ScrollDanmakuCollision.canPlace(
          existing: const [(x: 400.0, width: 300.0)],
          candidateX: 900,
          candidateWidth: 100,
          viewWidth: 1000,
          durationSeconds: 10,
        ),
        isTrue,
      );
    });
  });

  testWidgets('speed boost and release preserve the active danmaku',
      (tester) async {
    final danmaku = [
      <String, dynamic>{
        'time': 0.0,
        'content': 'rate-continuity',
        'type': 'scroll',
      },
    ];
    await tester.pumpWidget(_rendererHost(danmakuList: danmaku));
    await tester.pump();
    final original = tester.element(find.byType(DanmakuScreen));
    final originalItem = _scrollPainter(tester).scrollDanmakuItems.single;

    await tester.pumpWidget(
      _rendererHost(danmakuList: danmaku, playbackRate: 2),
    );
    await tester.pump();

    expect(tester.element(find.byType(DanmakuScreen)), same(original));
    expect(_scrollPainter(tester).scrollDanmakuItems.single, same(originalItem));

    await tester.pumpWidget(_rendererHost(danmakuList: danmaku));
    await tester.pump();

    expect(tester.element(find.byType(DanmakuScreen)), same(original));
    expect(_scrollPainter(tester).scrollDanmakuItems.single, same(originalItem));
  });

  testWidgets('renderer initializes safely while playback is paused',
      (tester) async {
    final danmaku = [
      <String, dynamic>{
        'time': 0.0,
        'content': 'paused-start',
        'type': 'scroll',
      },
    ];

    await tester.pumpWidget(
      _rendererHost(danmakuList: danmaku, isPlaying: false),
    );
    await tester.pump();

    expect(_scrollPainter(tester).scrollDanmakuItems, hasLength(1));
  });

  testWidgets('an in-place list clear removes active danmaku', (tester) async {
    final danmaku = [
      <String, dynamic>{
        'time': 0.0,
        'content': 'removed-entry',
        'type': 'scroll',
      },
    ];
    await tester.pumpWidget(_rendererHost(danmakuList: danmaku));
    await tester.pump();
    expect(_scrollPainter(tester).scrollDanmakuItems, hasLength(1));

    danmaku.clear();
    await tester.pumpWidget(
      _rendererHost(danmakuList: danmaku, danmakuListVersion: 2),
    );
    await tester.pump();

    expect(_scrollPainter(tester).scrollDanmakuItems, isEmpty);
  });

  testWidgets('showing after a hidden rate change uses a fresh controller',
      (tester) async {
    final danmaku = [
      <String, dynamic>{
        'time': 0.0,
        'content': 'visibility-rate',
        'type': 'scroll',
      },
    ];
    await tester.pumpWidget(_rendererHost(danmakuList: danmaku));
    await tester.pump();

    await tester.pumpWidget(
      _rendererHost(
        danmakuList: danmaku,
        playbackRate: 2,
        visible: false,
      ),
    );
    await tester.pump();
    expect(find.byType(DanmakuScreen), findsNothing);

    await tester.pumpWidget(
      _rendererHost(danmakuList: danmaku, playbackRate: 2),
    );
    await tester.pump();

    expect(_scrollPainter(tester).scrollDanmakuItems, hasLength(1));
  });

  testWidgets('explicit small seek restores the scrolling x position',
      (tester) async {
    final danmaku = [
      <String, dynamic>{
        'time': 0.0,
        'content': 'seek-position',
        'type': 'scroll',
      },
    ];
    await tester.pumpWidget(
      _rendererHost(danmakuList: danmaku, isPlaying: false),
    );
    await tester.pump();

    await tester.pumpWidget(
      _rendererHost(
        danmakuList: danmaku,
        currentTime: 0.5,
        seekRevision: 1,
        isPlaying: false,
      ),
    );
    await tester.pump();

    final painter = _scrollPainter(tester);
    final item = painter.scrollDanmakuItems.single;
    final viewWidth = tester.getSize(find.byType(DanmakuScreen)).width;
    final expectedX = viewWidth - 0.05 * (viewWidth + item.width);
    expect(item.xPosition, closeTo(expectedX, 0.01));
  });

  testWidgets('seek restoration drains every active candidate',
      (tester) async {
    final danmaku = List.generate(
      30,
      (index) => <String, dynamic>{
        'time': 9.0,
        'content': 'dense-$index',
        'type': 'scroll',
      },
    );
    await tester.pumpWidget(
      _rendererHost(
        danmakuList: danmaku,
        currentTime: 10,
        stacking: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(_scrollPainter(tester).scrollDanmakuItems, hasLength(30));
  });

  testWidgets('paused seek restores fixed danmaku with remaining lifetime',
      (tester) async {
    late DanmakuController controller;
    final option = DanmakuOption(duration: 10, playbackRate: 1);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 400,
          child: DanmakuScreen(
            option: option,
            createdController: (value) => controller = value,
          ),
        ),
      ),
    );
    controller.pause();
    controller.addDanmaku(
      DanmakuContentItem('fixed', type: DanmakuItemType.top),
      elapsedSeconds: 9,
    );
    await tester.pump();

    final restored = _staticPainter(tester).topDanmakuItems.single;
    expect(restored.remainingDurationSeconds, closeTo(1, 0.01));
  });

  testWidgets('addDanmaku reports whether a danmaku actually mounted',
      (tester) async {
    late DanmakuController controller;
    // area 0.0 表示单行模式：始终只有 1 条轨道，
    // 便于构造"轨道已占用 → 上屏失败"的场景。
    final option = DanmakuOption(duration: 10, playbackRate: 1, area: 0.0);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 40,
          child: DanmakuScreen(
            option: option,
            createdController: (value) => controller = value,
          ),
        ),
      ),
    );

    // 空轨道：第一条顶部弹幕成功上屏
    expect(
      controller.addDanmaku(DanmakuContentItem('first', type: DanmakuItemType.top)),
      isTrue,
    );
    await tester.pump();
    expect(_staticPainter(tester).topDanmakuItems, hasLength(1));

    // 轨道已占用：第二条被丢弃并如实返回 false，
    // 调用方据此不应把它记入"已添加"去重表，否则其后续重放会缺失。
    expect(
      controller.addDanmaku(DanmakuContentItem('second', type: DanmakuItemType.top)),
      isFalse,
    );
    await tester.pump();
    expect(_staticPainter(tester).topDanmakuItems, hasLength(1));
  });
}

Widget _rendererHost({
  required List<Map<String, dynamic>> danmakuList,
  double currentTime = 0,
  double playbackRate = 1,
  int seekRevision = 0,
  bool stacking = false,
  bool isPlaying = true,
  int danmakuListVersion = 1,
  bool visible = true,
}) {
  return MaterialApp(
    home: Center(
      child: SizedBox(
        width: 800,
        height: 400,
        child: CanvasDanmakuRenderer(
          fontSize: 16,
          opacity: 1,
          displayArea: 1,
          visible: visible,
          stacking: stacking,
          mergeDanmaku: false,
          blockTopDanmaku: false,
          blockBottomDanmaku: false,
          blockScrollDanmaku: false,
          blockWords: const [],
          danmakuList: danmakuList,
          currentTime: currentTime,
          isPlaying: isPlaying,
          playbackRate: playbackRate,
          scrollDurationSeconds: 10,
          seekRevision: seekRevision,
          danmakuListVersion: danmakuListVersion,
          timeOffsetSeconds: 0,
        ),
      ),
    ),
  );
}

ScrollDanmakuPainter _scrollPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<ScrollDanmakuPainter>()
    .single;

StaticDanmakuPainter _staticPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<StaticDanmakuPainter>()
    .single;
