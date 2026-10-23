import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/player/classic/classic_backed_playback.dart';
import 'package:nipaplay/next/player/next_playback.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_test_support.dart';
import 'player_test_support.dart';

/// Classic's state with a file open: the kernel has the file's embedded track
/// on (as Classic's own opening leaves it).
class _OpenState extends ClassicPlayerState {
  _OpenState(this.path) {
    subtitleManager.setCurrentVideoPath(path);
  }
  final String path;
  @override
  String? get currentVideoPath => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MediaFixture f;
  late SubtitleLibrary library;
  late String id, path, srt;
  late _OpenState state;
  late SubtitleTarget target;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    f = MediaFixture();
    await f.open();
    library = SubtitleLibrary(f.service, f.root,
        probe: (_) async => {
              'subtitles': [
                {
                  'index': 0,
                  'streamIndex': 2,
                  'language': 'ger',
                  'title': 'German',
                  'format': 'subrip'
                }
              ]
            });
    id = await f.file('Sintel.mkv');
    path = '${f.media.path}/Sintel.mkv';
    srt = '${f.media.path}/Sintel.zh-Hans.srt';
    await File(srt)
        .writeAsString('1\n00:00:00,000 --> 00:00:04,000\n中文字幕\n');
    id = await f.identities.ensureFile(path);
    await library.inspect(id, path);
    state = _OpenState(path);
    target = ClassicBackedPlayback(state).subtitleTarget;
  });
  tearDown(() async {
    await library.close();
    await f.close();
  });

  Future<String> trackId(bool embedded) async =>
      ((await library.facts(id))['tracks'] as List)
          .cast<Map>()
          .firstWhere((t) => (t['origin'] == 'embedded') == embedded)['id']
      as String;

  test('a chosen external text subtitle turns the embedded track off',
      () async {
    await library.select(id, await trackId(false));
    expect(state.player.activeSubtitleTracks, [0]);
    await library.loadForPlayback(target, path);
    expect(state.activeExternalSubtitlePaths.map((p) => p.split('/').last),
        ['Sintel.zh-Hans.srt']);
    expect(state.player.activeSubtitleTracks, isEmpty);
  });

  test('a chosen embedded track takes the external subtitle off', () async {
    await library.select(id, await trackId(false));
    await library.loadForPlayback(target, path);
    expect(state.activeExternalSubtitlePaths, hasLength(1));
    await library.select(id, await trackId(true));
    await library.loadForPlayback(target, path);
    expect(state.activeExternalSubtitlePaths, isEmpty);
    expect(state.player.activeSubtitleTracks, [0]);
  });

  test('changing the choice while playing keeps only the chosen one',
      () async {
    library.attachPlayer(target);
    await library.select(id, await trackId(false));
    expect(state.activeExternalSubtitlePaths, hasLength(1));
    expect(state.player.activeSubtitleTracks, isEmpty);
    await library.select(id, await trackId(true));
    expect(state.activeExternalSubtitlePaths, isEmpty);
    expect(state.player.activeSubtitleTracks, [0]);
    await library.select(id, await trackId(false));
    expect(state.activeExternalSubtitlePaths, hasLength(1));
    expect(state.player.activeSubtitleTracks, isEmpty);
  });
}
