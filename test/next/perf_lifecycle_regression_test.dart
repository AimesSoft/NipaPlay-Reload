import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

// Supplied by flutter_test.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/mesh/catalogue_updates.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/system/foreground.dart';
import 'package:nipaplay/next/ui/dev/idle_measurement.dart';
import 'package:nipaplay/next/ui/widgets/elapsed_text.dart';
import 'package:nipaplay/next/ui/widgets/visible_updates.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'perf_push_test.dart' show writeCatalogueInWorker;

class _Probe extends StatefulWidget {
  const _Probe(this.stream, this.read, this.clock);
  final Stream<void> stream;
  final Future<void> Function() read;
  final String Function() clock;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with VisibleUpdates<_Probe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    watchUpdates(widget.stream, widget.read);
  }

  @override
  Widget build(BuildContext context) =>
      ElapsedText(text: widget.clock, style: const TextStyle());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a real worker commits before its port notification is observed',
      () async {
    sqfliteFfiInit();
    final root =
        await Directory.systemTemp.createTemp('perf-worker-regression-');
    final db = await openNextDatabase(root, factory: databaseFactoryFfi);
    final port = ReceivePort();
    final received = port.first;
    try {
      await writeCatalogueInWorker(root.path, port.sendPort);
      await received.timeout(const Duration(seconds: 5));
      expect(
          await db.query('media_entities',
              where: 'id=?', whereArgs: ['worker-work']),
          hasLength(1));
    } finally {
      port.close();
      await db.close();
      await root.delete(recursive: true);
    }
  });

  testWidgets('clock and data subscriptions survive repeated hiding and resume',
      (tester) async {
    final stream = StreamController<void>.broadcast();
    var reads = 0, clocks = 0;
    final probe = _Probe(stream.stream, () async {
      reads++;
    }, () {
      clocks++;
      return '0:01';
    });
    Widget page(bool visible) => Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(enabled: visible, child: probe));
    await tester.pumpWidget(page(true));
    expect(reads, 1);
    for (var n = 0; n < 2; n++) {
      await tester.pumpWidget(page(false));
      final hidden = clocks;
      expect(stream.hasListener, false);
      await tester.pump(const Duration(seconds: 60));
      expect(clocks, hidden);
      await tester.pumpWidget(page(true));
      final live = clocks;
      await tester.pump(const Duration(seconds: 1));
      expect(clocks, greaterThan(live));
    }
    expect(reads, 3);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    expect(stream.hasListener, false);
    final behind = clocks;
    await tester.pump(const Duration(seconds: 60));
    expect(clocks, behind);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(reads, 4);
    final liveAgain = clocks;
    await tester.pump(const Duration(seconds: 1));
    expect(clocks, greaterThan(liveAgain));
    await tester.pumpWidget(const SizedBox());
    await stream.close();
  });

  testWidgets('idle filters stale timings and computes percentiles off isolate',
      (tester) async {
    final result = await tester.runAsync(() async {
      final pending = measureNextIdle(const Duration(milliseconds: 50));
      final now = Timeline.now;
      FrameTiming frame(int at, int build, int raster) => FrameTiming(
          vsyncStart: at,
          buildStart: at,
          buildFinish: at + build,
          rasterStart: at + build,
          rasterFinish: at + build + raster,
          rasterFinishWallTime: at + build + raster);
      tester.binding.platformDispatcher.onReportTimings!([
        frame(now - 1000000, 9000, 9000),
        frame(now, 1000, 2000),
        frame(now + 1, 3000, 4000)
      ]);
      return await pending.timeout(const Duration(seconds: 5));
    });
    expect(result!['frames'], 2);
    expect(result['build'], {'p50': 1.0, 'p95': 3.0, 'max': 3.0});
    expect(result['raster'], {'p50': 2.0, 'p95': 4.0, 'max': 4.0});
    expect(result['periodicRefreshes'], 0);
  });

  test('negotiated push survives a network error and stop/start has no timer',
      () {
    fakeAsync((clock) {
      NextForeground.setActive(true);
      var calls = 0;
      final updates = CatalogueUpdates((_) async {
        calls++;
      });
      updates.start();
      updates.peer('modern', push: true);
      updates.failed('modern');
      clock.elapse(const Duration(minutes: 2));
      expect(calls, 0);
      expect(clock.periodicTimerCount, 0);
      updates.stop();
      clock.flushMicrotasks();
      updates.start();
      updates.changed(peers: {'modern'});
      clock.flushMicrotasks();
      expect(calls, 1);
      expect(clock.periodicTimerCount, 0);
      updates.close();
      clock.flushMicrotasks();
    });
  });
}
