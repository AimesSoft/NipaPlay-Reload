import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/player/danmaku/controller.dart';
import 'package:nipaplay/next/player/danmaku/native_sink.dart';
import 'package:nipaplay/next/player/danmaku/session_port.dart';
import 'package:nipaplay/next/player/perf/budget.dart';
import 'package:shared_preferences/shared_preferences.dart';

DanmakuEntry entry(int time, String text, {int mode = 1}) => DanmakuEntry(
  sourceId: 'test', videoId: '12', platform: 'bilibili',
  sourceTimeMs: time, text: text, mode: mode, colorRgb: 0xFFFFFF);

Map<String, dynamic> binding(String id, {int offset = 0}) => {
  'id': id, 'enabled': 1, 'deduplicate': 1, 'offset_ms': offset,
  'revision': 1, 'cache_revision': 1, 'cache_key': id,
  'video': {'sourceId': 'test', 'videoId': '12', 'title': 'episode 12'}};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('worker applies media timing, fold, rules and stable background pagination', () async {
    final c = SessionDanmakuController();
    addTearDown(c.dispose);
    c.bind('session-12');
    c.inputs(duration: 1440000);
    c.install('track', binding('track', offset: 1000), [
      entry(10000, 'hello'), entry(11000, 'block literal'),
      entry(12000, 'bad123'), entry(13000, 'top', mode: 5)], startMs: 2000);
    await c.writeSetting('danmaku.blockWords', ['literal', 'numbers/bad\\d+/', 'invalid/[/']);
    await c.writeSetting('danmaku.blockTop', true);
    await c.settled;
    expect(c.timeline.entries.map((e) => e['content']), ['hello']);
    expect(c.timeline.invalidRules, ['invalid/[/']);
    await c.writeSetting('danmaku.manualOffset', 0.5);
    await c.settled;
    final page = await c.entries({'startMs': 0, 'endMs': 20000}, 0);
    expect(page['total'], 1);
    expect((page['items'] as List).single['mappedTimeMs'], 10500);
    expect((page['items'] as List).single['sourceTimeMs'], 10000);
    await expectLater(c.entries({'expectedListVersion': c.version - 1}, 0),
        throwsA(isA<Failure>()));
  });

  test('late danmaku, duration and chapter changes recompute segment facts', () async {
    final c = SessionDanmakuController();
    addTearDown(c.dispose);
    c.bind('late');
    c.inputs(duration: 1440000);
    await c.settled;
    expect(c.timeline.segments, isEmpty);
    // A deferred source completes after the session's original ready event.
    final gateway = Completer<List<DanmakuEntry>>();
    final installed = gateway.future.then((rows) => c.install('late', binding('late'), rows));
    gateway.complete([entry(50000, '空降 02:12'), entry(55000, '跳伞 02:12'),
      entry(132000, '空降成功')]);
    await installed;
    await c.settled;
    expect(c.timeline.segments.single.end.inMilliseconds, 132000);
    c.inputs(duration: 120000);
    await c.settled;
    expect(c.timeline.segments.single.end.inMilliseconds, 119500);
    c.remove('late');
    c.inputs(duration: 1440000, chapterFacts: [
      {'title': 'OP', 'startMs': 30000, 'endMs': 120000},
      {'title': 'ED', 'startMs': 1350000, 'endMs': 1440000}]);
    await c.settled;
    expect(c.timeline.segments.map((s) => s.kind.name), ['opening', 'ending']);
    c.inputs(duration: 1440000, chapterFacts: []);
    await c.settled;
    expect(c.timeline.segments, isEmpty);
  });

  test('port rejects stale generations and keeps track updates and native delivery fenced', () async {
    final c = SessionDanmakuController();
    addTearDown(c.dispose);
    c.bind('first');
    var current = const DanmakuPlaybackTarget('/12.mkv', 1, durationMs: 1440000);
    final p = SessionDanmakuPort(c, () => current);
    final sink = _Native();
    c.attachNative(sink);
    expect(p.install(current, binding('a'), [entry(10000, 'native')]), true);
    await c.settled;
    expect(sink.entries.single['content'], 'native');
    await c.writeSetting('danmaku.opacity', 0.5);
    expect(sink.settings['danmaku.opacity'], 0.5);
    expect(p.loaded('a')?['cacheKey'], 'a');
    p.updateTrack(current, 'a', {'enabled': false});
    await c.settled;
    expect(c.timeline.entries, isEmpty);
    final old = current;
    current = const DanmakuPlaybackTarget('/12.mkv', 2);
    c.bind('second');
    expect(p.install(old, binding('stale'), [entry(0, 'wrong session')]), false);
    expect(p.registry, isEmpty);
    await c.settled;
    c.fence();
    final calls = sink.calls;
    await c.writeSetting('danmaku.opacity', 0.8);
    await c.rebuild();
    expect(sink.calls, calls);
  });

  test('30,000 comments build off-isolate with bounded UI dispatch', () async {
    final c = SessionDanmakuController();
    addTearDown(c.dispose);
    c.bind('budget');
    c.inputs(duration: 1440000);
    // Warm worker creation separately from the measured data construction.
    await c.settled;
    final rows = [for (var i = 0; i < 30000; i++)
      entry(i * 40, '第 $i 条弹幕')];
    var heartbeat = 0;
    final pulse = Timer.periodic(const Duration(milliseconds: 1), (_) => heartbeat++);
    PlayerPerf.reset();
    c.install('bulk', binding('bulk'), rows);
    await c.settled;
    pulse.cancel();
    expect(c.timeline.entries.length, 30000);
    expect(heartbeat, greaterThan(5));
    final perf = PlayerPerf.read();
    // ignore: avoid_print
    print('DANMAKU_BUDGET buildUs=${c.timeline.buildUs} heartbeats=$heartbeat perf=$perf');
    expect(c.timeline.buildUs, lessThan(450000)); // 3x loaded CI allowance.
    final spans = perf['spans'] as Map;
    for (final span in spans.values.cast<Map>()) {
      expect(span['p99Us'], lessThan(6000));
    }
    final page = await c.entries({'startMs': 0, 'endMs': 1440000, 'limit': 20}, 0);
    expect(page['total'], 30000);
    expect((page['items'] as List).length, 20);
    expect(page['nextCursor'], 20);
  });
}

class _Native implements SessionNativeDanmakuSink {
  int calls = 0;
  List<Map<String, dynamic>> entries = [];
  Map<String, Object?> settings = {};
  @override
  Future<void> replaceDanmaku(List<Map<String, dynamic>> timeline) async {
    calls++;
    entries = timeline;
  }
  @override
  Future<void> configureDanmaku(Map<String, Object?> configuration) async {
    calls++;
    settings = configuration;
  }
}
