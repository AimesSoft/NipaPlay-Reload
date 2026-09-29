import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_episode_rail.dart';

void main() {
  Future<void> showRail(WidgetTester tester, {int? target}) async {
    tester.view.physicalSize = const Size(1280, 260);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      home: ImmersiveEpisodeRail(
        episodeCount: 30,
        targetEpisodeIndex: target,
        onSelectEpisodes: null,
        itemBuilder: (_, index) => ColoredBox(
          key: ValueKey('episode-$index'),
          color: Colors.blue,
          child: Text('第 $index 集'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('positions the playback target slightly left of centre',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showRail(tester, target: 8);
    expect(tester.getCenter(find.byKey(const ValueKey('episode-8'))).dx,
        closeTo(1280 * 0.42, 1));

    // The history/primary action may resolve after the first layout.
    await showRail(tester, target: 12);
    expect(tester.getCenter(find.byKey(const ValueKey('episode-12'))).dx,
        closeTo(1280 * 0.42, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('accumulates rapid wheel events and respects manual browsing',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showRail(tester, target: 8);
    final controller =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    final before = controller.offset;
    final position = tester.getCenter(find.byType(ListView));
    for (var i = 0; i < 3; i++) {
      await tester.sendEventToBinding(PointerScrollEvent(
        position: position,
        scrollDelta: const Offset(0, 40),
      ));
    }
    await tester.pumpAndSettle();
    expect(controller.offset - before, closeTo(360, 1));
    final browsedOffset = controller.offset;
    await showRail(tester, target: 20);
    expect(controller.offset, closeTo(browsedOffset, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps first and last targets inside the scroll range',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showRail(tester, target: 0);
    final controller =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(controller.offset, 0);
    await showRail(tester, target: 29);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byKey(const ValueKey('episode-29')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal wheel gestures are consumed only once',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showRail(tester, target: 8);
    final controller =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    final before = controller.offset;
    await tester.sendEventToBinding(PointerScrollEvent(
      position: tester.getCenter(find.byType(ListView)),
      scrollDelta: const Offset(40, 0),
    ));
    await tester.pumpAndSettle();
    expect(controller.offset - before, closeTo(40, 1));
    expect(tester.takeException(), isNull);
  });
}
