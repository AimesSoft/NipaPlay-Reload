import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/player/classic/danmaku_port.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflinePlayer extends Fake implements AbstractPlayer {
  @override
  void dispose() {}
  @override
  List<String> getDecoders(PlayerMediaType type) => ['FFmpeg'];
  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {}
  @override
  void setProperty(String key, String value) {}
}

class _Video extends VideoPlayerState {
  _Video() : super.forSettings(Player.withDelegate(_OfflinePlayer()));
  @override
  String get currentVideoPath => '/fixture/video.mkv';
  @override
  int get playbackGeneration => 3;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('player updates fold local tracks and preserve their source times', () {
    final video = _Video();
    addTearDown(video.dispose);
    final port = VideoDanmakuPort(video);
    final originals = [
      for (final time in [5.0, 7.0])
        <String, dynamic>{
          'time': time,
          'content': '相同来源的合成弹幕',
          'type': 'scroll',
          'color': 'rgb(255,255,255)',
          'source': 'bilibili',
          'platformVideoId': '101',
          'platformDanmakuId': 'entry'
        }
    ];
    for (var i = 0; i < originals.length; i++) {
      video.danmakuTracks['local-$i'] = {
        'danmakuList': [originals[i]],
        'platform': 'bilibili',
        'platformVideoId': '101',
        'origin': 'local_file'
      };
      video.danmakuTrackEnabled['local-$i'] = true;
    }
    final target = port.target!;
    port.updateTrack(target, 'local-0', {'displayFold': true});
    port.updateTrack(
        target, 'local-1', {'displayFold': true, 'offsetMs': 2000});
    expect(video.danmakuList, hasLength(1));
    expect(video.danmakuList.single['time'], 5);
    expect(video.danmakuList.single['displayCount'], 2);
    port.updateTrack(target, 'local-1', {'displayFold': false});
    expect(video.danmakuList, hasLength(2));
    port.updateTrack(target, 'local-1', {'offsetMs': -1000});
    expect(video.danmakuList.map((e) => e['time']), [5, 8]);
    port.updateTrack(target, 'local-1', {'enabled': false, 'offsetMs': 0});
    expect(video.danmakuList, hasLength(1));
    expect(video.danmakuTrackEnabled['local-1'], isFalse);
    expect(originals.map((e) => e['time']), [5, 7]);
    expect(originals.every((e) => !e.containsKey('displayCount')), isTrue);
    expect(
        port.updateTrack(const DanmakuPlaybackTarget('/fixture/other.mkv', 3),
            'local-0', {'enabled': false}),
        isFalse);
    expect(
        port.updateTrack(const DanmakuPlaybackTarget('/fixture/video.mkv', 2),
            'local-0', {'enabled': false}),
        isFalse);
    expect(video.danmakuTrackEnabled['local-0'], isTrue);
  });

  test('timeline offset failure does not partially apply other properties', () {
    final video = _Video();
    addTearDown(video.dispose);
    video.danmakuTracks['timeline'] = {'deduplicate': true};
    final port = VideoDanmakuPort(video);
    expect(
        () => port.updateTrack(
            port.target!, 'timeline', {'displayFold': false, 'offsetMs': 1000}),
        throwsA(isA<Failure>()));
    expect(video.danmakuTracks['timeline']!['deduplicate'], isTrue);
  });
}
