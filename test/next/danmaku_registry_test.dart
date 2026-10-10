import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/danmaku_track_registry.dart';

void main() {
  test('Classic, local and online registration share one platform/video track',
      () {
    final tracks = <String, Map<String, dynamic>>{};
    final enabled = <String, bool>{};
    registerDanmakuSourceTrack(
        tracks,
        enabled,
        'remote',
        {'platform': 'bilibili', 'platformVideoId': '101', 'origin': 'binding'},
        true);
    registerDanmakuSourceTrack(
        tracks,
        enabled,
        'local',
        {
          'platform': 'bilibili',
          'platformVideoId': '101',
          'origin': 'local_file'
        },
        false);
    expect(tracks.keys, ['local']);
    expect(enabled, {'local': false});
    registerDanmakuSourceTrack(
        tracks,
        enabled,
        'other',
        {'platform': 'youku', 'platformVideoId': '101', 'origin': 'binding'},
        true);
    expect(tracks, hasLength(2));
    registerDanmakuSourceTrack(
        tracks,
        enabled,
        'refreshed',
        {'platform': 'bilibili', 'platformVideoId': '101', 'origin': 'binding'},
        true);
    expect(tracks.keys, ['other', 'refreshed']);
  });
  test('dandanplay has one slot across episode changes and old Next tracks',
      () {
    final tracks = <String, Map<String, dynamic>>{
      'next:old': {'source': 'dandanplay', 'platformVideoId': '7101'}
    };
    final enabled = {'next:old': true};
    registerDanmakuSourceTrack(tracks, enabled, 'dandanplay',
        {'platform': 'dandanplay', 'platformVideoId': '7102'}, true);
    expect(tracks.keys, ['dandanplay']);
    expect(enabled.keys, ['dandanplay']);
  });
  test(
      'unknown platforms and missing video IDs do not establish identity equivalence',
      () {
    final tracks = <String, Map<String, dynamic>>{};
    final enabled = <String, bool>{};
    for (final id in ['first', 'second']) {
      registerDanmakuSourceTrack(tracks, enabled, id,
          {'platform': 'unknown', 'platformVideoId': '101'}, true);
    }
    for (final id in ['third', 'fourth']) {
      registerDanmakuSourceTrack(tracks, enabled, id,
          {'platform': 'bilibili', 'platformVideoId': null}, true);
    }
    expect(tracks, hasLength(4));
  });
}
