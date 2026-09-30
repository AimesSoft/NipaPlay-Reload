import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/player_overlay_surface.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_progress_bar.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class _VideoState extends Fake implements VideoPlayerState {
  @override
  Duration get duration => const Duration(minutes: 2);
  @override
  Duration get position => const Duration(seconds: 30);
  @override
  double get progress => 0.25;
  @override
  double get bufferedProgress => 0.5;
  @override
  bool get isTimelinePreviewAvailable => false;
}

String _formatTime(Duration time) =>
    '${(time.inSeconds ~/ 60).toString().padLeft(2, '0')}:'
    '${(time.inSeconds % 60).toString().padLeft(2, '0')}';

Future<Rect> _mountBar(WidgetTester tester, {double textScale = 1}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          child: VideoProgressBar(
            videoState: _VideoState(),
            hoverTime: null,
            isDragging: false,
            onPositionUpdate: (_) {},
            onDraggingStateChange: (_) {},
            formatDuration: _formatTime,
          ),
        ),
      ),
    ),
  ));
  return tester.getRect(find.byType(VideoProgressBar));
}

void main() {
  for (final textScale in [1.0, 2.0]) {
    for (final fromAbove in [true, false]) {
      testWidgets(
          'hover remains visible entering from ${fromAbove ? 'above' : 'below'} at text scale $textScale',
          (tester) async {
        final rect = await _mountBar(tester, textScale: textScale);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
            location: Offset(
                rect.center.dx, fromAbove ? rect.top - 20 : rect.bottom + 20));
        await tester.pump();
        final inside =
            Offset(rect.center.dx, fromAbove ? rect.top + 1 : rect.bottom - 1);
        await mouse.moveTo(inside);
        await mouse.moveTo(inside + const Offset(0.1, 0));
        await tester.pump();
        expect(find.text('01:00'), findsOneWidget);
        expect(tester.getBottomRight(find.byType(PlayerOverlaySurface)).dy,
            closeTo(rect.top - 8, 0.01));
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.text('01:00'), findsOneWidget);
        }
        await mouse.moveTo(Offset(rect.right + 20, rect.center.dy));
        await tester.pump();
        expect(find.byType(PlayerOverlaySurface), findsNothing);
        await mouse.removePointer();
      });
    }
  }

  testWidgets('moving along the timeline updates the existing tooltip',
      (tester) async {
    final rect = await _mountBar(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: rect.topLeft - const Offset(20, 20));
    await mouse.moveTo(rect.center);
    await mouse.moveTo(rect.center + const Offset(0.1, 0));
    await tester.pump();
    final originalTooltip = tester.element(find.byType(PlayerOverlaySurface));
    await mouse.moveTo(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pump();
    expect(find.text('01:30'), findsOneWidget);
    expect(tester.element(find.byType(PlayerOverlaySurface)),
        same(originalTooltip));
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
