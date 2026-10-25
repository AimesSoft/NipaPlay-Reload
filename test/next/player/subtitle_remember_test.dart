import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/player/next_playback.dart';
import 'package:nipaplay/next/player/ports/session_playback.dart';
import 'package:nipaplay/next/player/subtitles/controller.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media_test_support.dart';
import 'fake_driver.dart';
import 'package:path/path.dart' as ppath;

/// `remember` on playback.select_track and playback.load_subtitle: false
/// holds for the current playback only; true is written to the subtitle
/// library (and the shared subtitle list), and the next open of the same
/// video uses it. The person's choices in the interface are always kept.
/// Run over the real subtitle library, reopening the video each time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MediaFixture f;
  late SubtitleLibrary library;
  late String id, video, sidecar, elsewhere;
  final playbacks = <SessionPlayback>[];
  var n = 0;

  const srt = '1\n00:00:00,000 --> 00:00:04,000\n中文字幕\n';

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
    // A name of its own: the shared subtitle list is keyed by name and size.
    final name = 'Sintel${n++}';
    video = '${f.media.path}/$name.mkv';
    await f.file('$name.mkv');
    sidecar = ppath.join(f.media.path, '$name.zh-Hans.srt');
    await File(sidecar).writeAsString(srt);
    // A file the library cannot find next to the video.
    final other = await Directory.systemTemp.createTemp('remember-other-');
    elsewhere = ppath.join(other.path, 'mine.srt');
    await File(elsewhere).writeAsString(srt);
    id = await f.identities.ensureFile(video);
    await library.inspect(id, video);
  });
  tearDown(() async {
    for (final p in playbacks) {
      await p.close(reason: 'test');
    }
    playbacks.clear();
    await library.close();
    await f.close();
    await Directory(File(elsewhere).parent.path).delete(recursive: true);
  });

  Future<String> trackId(bool embedded) async =>
      ((await library.facts(id))['tracks'] as List)
          .cast<Map>()
          .firstWhere((t) => (t['origin'] == 'embedded') == embedded)['id']
      as String;

  /// The library's record: the track and how it came to be chosen.
  Future<Object?> libraryChoice() async =>
      ((await library.facts(id))['selection'] as Map?)?['trackId'];

  /// One playback of the video over the real library.
  Future<SessionPlayback> open() async {
    final rig = FakeHost();
    final playback = SessionPlayback(rig.host);
    playbacks.add(playback);
    library.attachPlayer(playback.subtitleTarget);
    await playback.openItem(PlayableItem(videoPath: video));
    return playback;
  }

  Future<void> reopen(SessionPlayback playback) async {
    await playback.close(reason: 'test');
    library.detachPlayer();
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Map<String, Object?> subtitlesOf(Map<String, Object?> facts) =>
      (facts['subtitles'] as Map).cast<String, Object?>();

  test('select_track with remember false holds for this playback only: the '
      'library keeps its own, and the next open has it back', () async {
    await library.select(id, await trackId(false));
    var playback = await open();
    final session = playback.session!;
    expect(session.subtitles.want, SubtitleWant.file(sidecar));

    final result = await playback.controls
        .selectTrack({'kind': 'subtitle', 'origin': 'embedded', 'index': 0});
    expect(result['remembered'], isFalse);
    expect((result['receipt'] as Map)['remembered'], isFalse);
    await settle();
    expect(session.subtitles.want, const SubtitleWant.embedded(0));
    expect(session.subtitles.state.value.selectedBy, 'agent');
    // What is on, and what the library keeps, told apart.
    final facts = subtitlesOf(await playback.controls.tracks({}));
    expect(facts['selected'], {'kind': 'embedded', 'index': 0});
    expect(facts['remembered'], {'kind': 'external', 'path': sidecar});
    expect(facts['rememberedIsSelected'], isFalse);
    expect(await libraryChoice(), await trackId(false));

    await reopen(playback);
    playback = await open();
    expect(playback.session!.subtitles.want, SubtitleWant.file(sidecar));
    expect(await libraryChoice(), await trackId(false));
  });

  test('select_track with remember true is written to the library, and the '
      'next open of the video uses it', () async {
    await library.select(id, await trackId(false));
    var playback = await open();
    final session = playback.session!;

    final result = await playback.controls
        .selectTrack({'kind': 'subtitle', 'origin': 'embedded', 'index': 0, 'remember': true});
    expect(result['remembered'], isTrue);
    await settle();
    expect(session.subtitles.want, const SubtitleWant.embedded(0));
    final facts = subtitlesOf(await playback.controls.tracks({}));
    expect(facts['remembered'], {'kind': 'embedded', 'index': 0});
    expect(facts['rememberedIsSelected'], isTrue);
    expect(await libraryChoice(), await trackId(true));
    // The echo of the library's record keeps the choice Nipa's.
    expect(session.subtitles.state.value.selectedBy, 'agent');

    await reopen(playback);
    playback = await open();
    expect(playback.session!.subtitles.want, const SubtitleWant.embedded(0));
    expect(playback.session!.subtitles.state.value.selectedBy,
        'library_selection');
  });

  test('turning subtitles off: remembered only when asked', () async {
    await library.select(id, await trackId(false));
    var playback = await open();
    final off = await playback.controls
        .selectTrack({'kind': 'subtitle', 'origin': 'embedded', 'index': -1});
    expect(off['remembered'], isFalse);
    await reopen(playback);
    playback = await open();
    expect(playback.session!.subtitles.want, SubtitleWant.file(sidecar));

    final kept = await playback.controls.selectTrack(
        {'kind': 'subtitle', 'origin': 'embedded', 'index': -1, 'remember': true});
    expect(kept['remembered'], isTrue);
    expect(await libraryChoice(), isNull);
    await reopen(playback);
    playback = await open();
    expect(playback.session!.subtitles.want, const SubtitleWant.off());
  });

  test('a track the library does not know is not reported as remembered',
      () async {
    final playback = await open();
    final before = await libraryChoice();
    // The kernel has a second embedded track; the library lists one.
    final result = await playback.controls.selectTrack(
        {'kind': 'subtitle', 'origin': 'embedded', 'index': 1, 'remember': true});
    expect(result['remembered'], isFalse);
    expect(playback.session!.subtitles.want, const SubtitleWant.embedded(1));
    expect(await libraryChoice(), before);
  });

  test('load_subtitle with remember false mounts for this playback and '
      'writes nothing', () async {
    var playback = await open();
    final before = await libraryChoice();
    final loaded = await playback.controls.loadSubtitle({'path': elsewhere});
    expect(loaded['active'], isTrue);
    expect(loaded['remembered'], isFalse);
    await settle();
    expect(playback.session!.subtitles.want, SubtitleWant.file(elsewhere));
    expect(await SubtitleService().loadExternalSubtitles(video), isEmpty);
    expect(await libraryChoice(), before);

    await reopen(playback);
    playback = await open();
    expect(playback.session!.subtitles.want, isNot(SubtitleWant.file(elsewhere)));
    expect(playback.session!.subtitles.files.map((s) => s.path),
        isNot(contains(elsewhere)));
  });

  test('load_subtitle with remember true keeps the file and the choice: the '
      'next open has it on', () async {
    var playback = await open();
    final loaded = await playback.controls
        .loadSubtitle({'path': elsewhere, 'remember': true});
    expect(loaded['remembered'], isTrue);
    await settle();
    expect(
        (await SubtitleService().loadExternalSubtitles(video))
            .map((s) => s['path']),
        [elsewhere]);
    final facts = subtitlesOf(await playback.controls.tracks({}));
    expect(facts['remembered'], {'kind': 'external', 'path': elsewhere});
    expect(facts['rememberedIsSelected'], isTrue);

    await reopen(playback);
    playback = await open();
    expect(playback.session!.subtitles.want, SubtitleWant.file(elsewhere));
  });

  test('load_subtitle with activate false and remember true keeps the file '
      'without putting it on', () async {
    final playback = await open();
    final loaded = await playback.controls.loadSubtitle(
        {'path': elsewhere, 'activate': false, 'remember': true});
    expect(loaded['active'], isFalse);
    expect(loaded['remembered'], isTrue);
    expect(
        (await SubtitleService().loadExternalSubtitles(video))
            .map((s) => s['path']),
        [elsewhere]);
    expect(playback.session!.subtitles.want, isNot(SubtitleWant.file(elsewhere)));
  });

  test('the person\'s choice in the interface is always kept', () async {
    var playback = await open();
    await playback.choose(SubtitleChoice.file('zh', sidecar));
    await settle();
    expect(await libraryChoice(), await trackId(false));
    final facts = subtitlesOf(await playback.controls.tracks({}));
    expect(facts['remembered'], {'kind': 'external', 'path': sidecar});
    await reopen(playback);
    playback = await open();
    expect(playback.session!.subtitles.want, SubtitleWant.file(sidecar));
  });

  test('remove_subtitle does not touch the library\'s record', () async {
    await library.select(id, await trackId(false));
    final playback = await open();
    await playback.controls.removeSubtitle({'path': sidecar});
    await settle();
    expect(await libraryChoice(), await trackId(false));
  });

  test('audio choices are not kept: remember true is refused', () async {
    final playback = await open();
    await expectLater(
        playback.controls.selectTrack(
            {'kind': 'audio', 'origin': 'embedded', 'index': 1, 'remember': true}),
        throwsA(isA<Exception>()));
    final plain = await playback.controls
        .selectTrack({'kind': 'audio', 'origin': 'embedded', 'index': 1});
    expect(plain['remembered'], isFalse);
  });
}
