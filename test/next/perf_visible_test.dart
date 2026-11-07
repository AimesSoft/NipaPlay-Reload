import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/dev/idle_measurement.dart';
import 'package:nipaplay/next/ui/widgets/elapsed_text.dart';
import 'package:nipaplay/next/ui/widgets/visible_updates.dart';

class _Page extends StatefulWidget {
  const _Page(this.changes, this.read);
  final Stream<void> changes;
  final Future<void> Function() read;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with VisibleUpdates<_Page> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    watchUpdates(widget.changes, widget.read);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  test('duration percentiles retain zero-frame evidence', () {
    expect(frameDurations([]), {'p50': null, 'p95': null, 'max': null});
    expect(frameDurations([1000, 5000, 2000, 3000]),
        {'p50': 2.0, 'p95': 5.0, 'max': 5.0});
  });

  testWidgets('visible subscriptions stop offstage and reconcile once',
      (tester) async {
    final changes = StreamController<void>.broadcast();
    var reads = 0;
    final page = _Page(changes.stream, () async {
      reads++;
    });
    await tester.pumpWidget(TickerMode(enabled: true, child: page));
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 60));
    expect(reads, 1);
    changes.add(null);
    await tester.pump();
    expect(reads, 2);
    await tester.pumpWidget(TickerMode(enabled: false, child: page));
    expect(changes.hasListener, false);
    changes.add(null);
    await tester.pump(const Duration(seconds: 60));
    expect(reads, 2);
    await tester.pumpWidget(TickerMode(enabled: true, child: page));
    expect(reads, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(changes.hasListener, false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, 4);
    await tester.pumpWidget(const SizedBox());
    await changes.close();
  });

  testWidgets('only a visible running clock has a second timer',
      (tester) async {
    var builds = 0;
    Widget clock(bool running, bool visible) => Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
            enabled: visible,
            child: ElapsedText(
                running: running,
                text: () {
                  builds++;
                  return '0:01';
                },
                style: const TextStyle())));
    await tester.pumpWidget(clock(false, true));
    final settled = builds;
    await tester.pump(const Duration(seconds: 60));
    expect(builds, settled);
    await tester.pumpWidget(clock(true, true));
    final live = builds;
    await tester.pump(const Duration(seconds: 1));
    expect(builds, greaterThan(live));
    await tester.pumpWidget(clock(true, false));
    final hidden = builds;
    await tester.pump(const Duration(seconds: 60));
    expect(builds, hidden);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('idle measures delivered timings without requesting frames',
      (tester) async {
    final data = await tester.runAsync(() async {
      final result = measureNextIdle(const Duration(milliseconds: 50));
      final now = Timeline.now;
      tester.binding.platformDispatcher.onReportTimings!([
        FrameTiming(
            vsyncStart: now,
            buildStart: now,
            buildFinish: now + 1000,
            rasterStart: now + 1000,
            rasterFinish: now + 3000,
            rasterFinishWallTime: now + 3000)
      ]);
      return await result.timeout(const Duration(seconds: 5));
    });
    expect(data!['periodicRefreshes'], 0);
    expect(data['frames'], 1);
  });
}
