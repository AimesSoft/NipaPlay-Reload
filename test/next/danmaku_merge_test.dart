import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/danmaku_source_merge.dart';
import 'package:nipaplay/utils/danmaku_track_timing.dart';

Map<String, dynamic> entry(String track, String platform,
        {String? id,
        String? video,
        String text = '这是一条较长的合成弹幕',
        double time = 1,
        bool aggregation = false,
        bool fold = true}) =>
    {
      'nextTrackId': track,
      'source': platform,
      'sourceId': track,
      'platformVideoId': video,
      'platformDanmakuId': id,
      'content': text,
      'time': time,
      'type': 'scroll',
      'color': 'rgb(255,255,255)',
      'aggregation': aggregation,
      'foldEnabled': fold
    };
void main() {
  test(
      'reliable origin identity folds across tracks without mutating originals',
      () {
    final original = [
      entry('related', 'bilibili', id: 'a', video: 'v', aggregation: true),
      entry('direct', 'bilibili', id: 'a', video: 'v')
    ];
    final result = foldDanmakuSources(original);
    expect(result, hasLength(1));
    expect(result.single['displayCount'], 2);
    expect(result.single['displayMembers'], hasLength(2));
    expect(original.first.containsKey('displayMembers'), isFalse);
  });
  test(
      'distinct same-platform IDs remain distinct even with identical text and time',
      () {
    expect(
        foldDanmakuSources([
          entry('one', 'bilibili', id: '1', video: 'v'),
          entry('two', 'bilibili', id: '2', video: 'v')
        ]),
        hasLength(2));
    expect(
        foldDanmakuSources([
          entry('one', 'bilibili', id: '1', video: 'v'),
          entry('one', 'bilibili', id: '2', video: 'v')
        ]),
        hasLength(2));
  });
  test(
      'unknown related overlap is only display-folded at a short exact-text window and can be disabled',
      () {
    expect(
        foldDanmakuSources([
          entry('related', 'unknown', aggregation: true),
          entry('direct', 'youku', time: 1.05)
        ]),
        hasLength(1));
    expect(
        foldDanmakuSources([
          entry('related', 'unknown', aggregation: true),
          entry('direct', 'youku', time: 1.2)
        ]),
        hasLength(2));
    expect(
        foldDanmakuSources([
          entry('related', 'unknown', aggregation: true),
          entry('direct', 'youku', fold: false)
        ]),
        hasLength(2));
    expect(
        foldDanmakuSources([
          entry('related', 'unknown', aggregation: true, text: '哈哈'),
          entry('direct', 'youku', text: '哈哈')
        ]),
        hasLength(2));
  });
  test(
      'one unknown aggregate item never removes two distinct direct sender entries',
      () {
    expect(
        foldDanmakuSources([
          entry('related', 'unknown', aggregation: true),
          entry('direct', 'bilibili', id: '1', video: 'v'),
          entry('direct', 'bilibili', id: '2', video: 'v')
        ]),
        hasLength(2));
  });
  test(
      'display folding compares aligned local times while original times remain immutable',
      () {
    final first = entry('related', 'bilibili', id: 'a', video: 'v', time: 5),
        second = entry('direct', 'bilibili', id: 'a', video: 'v', time: 7);
    expect(foldDanmakuSources([first, second]), hasLength(2));
    expect(foldDanmakuSources([first, DanmakuTrackTiming.shift(second, 2)]),
        hasLength(1));
    expect(second['time'], 7);
  });
}
