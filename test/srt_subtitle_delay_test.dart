import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/subtitle_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PlayerDelegate extends Fake implements AbstractPlayer {
  @override
  bool get supportsExternalSubtitles => false;

  @override
  List<int> get activeSubtitleTracks => [];

  @override
  String getPlayerKernelName() => 'Media Kit';
}

/// 设置项 `srt_subtitle_delay`：叠层给出的外挂 SRT/VTT 那一行按这个偏移
/// 计算（再加这条字幕自己的偏移）；ASS/SSA 不受它影响。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late SubtitleManager manager;
  late String srt;
  late String vtt;

  const cues = '1\n00:00:01,000 --> 00:00:03,000\nFirst\n\n'
      '2\n00:00:05,000 --> 00:00:07,000\nSecond\n';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    directory = await Directory.systemTemp.createTemp('srt-delay-');
    srt = '${directory.path}/track.srt';
    vtt = '${directory.path}/track.vtt';
    await File(srt).writeAsString(cues);
    await File(vtt).writeAsString('WEBVTT\n');
    manager = SubtitleManager(player: Player.withDelegate(_PlayerDelegate()));
    manager.setExternalSubtitle(srt);
    await manager.preloadSubtitleFile(srt);
  });

  tearDown(() async {
    manager.dispose();
    await directory.delete(recursive: true);
  });

  test('without a delay the overlay gives the line at the playback time', () {
    expect(manager.overlayDelayMs(srt), 0);
    expect(manager.overlayTextAt(srt, 1500), 'First');
    expect(manager.overlayTextAt(srt, 4000), '');
    expect(manager.overlayTextAt(srt, 5500), 'Second');
  });

  test('a positive SRT delay shows each line later', () {
    manager.srtDelaySeconds = 2.0;
    expect(manager.overlayDelayMs(srt), 2000);
    // First is 1-3 s in the file, so 3-5 s on screen.
    expect(manager.overlayTextAt(srt, 1500), '');
    expect(manager.overlayTextAt(srt, 3500), 'First');
    expect(manager.overlayTextAt(srt, 5500), '');
    expect(manager.overlayTextAt(srt, 7500), 'Second');
  });

  test('a negative SRT delay shows each line earlier', () {
    manager.srtDelaySeconds = -1.0;
    expect(manager.overlayTextAt(srt, 500), 'First');
    expect(manager.overlayTextAt(srt, 1500), 'First');
    expect(manager.overlayTextAt(srt, 4500), 'Second');
    expect(manager.overlayTextAt(srt, 6500), '');
  });

  test('the shared delay adds to the file\'s own, for SRT and VTT alike', () {
    manager.srtDelaySeconds = 2.0;
    manager.setPathDelaySeconds(srt, 0.5);
    expect(manager.overlayDelayMs(srt), 2500);
    expect(manager.overlayTextAt(srt, 3400), '');
    expect(manager.overlayTextAt(srt, 3600), 'First');
    // The VTT has no delay of its own: only the shared one.
    expect(manager.overlayDelayMs(vtt), 2000);
  });

  test('ASS keeps only its own delay', () async {
    final ass = '${directory.path}/track.ass';
    manager.srtDelaySeconds = 2.0;
    expect(manager.overlayDelayMs(ass), 0);
    manager.setPathDelaySeconds(ass, 0.5);
    expect(manager.overlayDelayMs(ass), 500);
  });
}
