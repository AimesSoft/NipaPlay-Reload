import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/subtitle_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// MDK's stop is asynchronous. Track changes during it can leave its subtitle
// decoder waiting on an empty packet queue, so the next prepare never finishes.
class _StoppingMdk extends Fake implements MdkPlayerAdapter {
  final calls = <String>[];
  bool stopping = false;
  bool poisoned = false;
  List<int> _tracks = [1];

  @override
  bool get supportsExternalSubtitles => true;
  @override
  List<int> get activeSubtitleTracks => _tracks;
  @override
  set activeSubtitleTracks(List<int> value) {
    calls.add('tracks:$value');
    if (stopping) poisoned = true;
    _tracks = value;
  }

  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(duration: 60000);
  @override
  void setMedia(String path, PlayerMediaType type) {
    calls.add('media:$path');
    if (stopping) poisoned = true;
  }

  @override
  void setProperty(String key, String value) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('repeated close, idle and reopen never change absent external media',
      () {
    final native = _StoppingMdk();
    final manager = SubtitleManager(player: Player.withDelegate(native));
    addTearDown(manager.dispose);

    for (var i = 0; i < 30; i++) {
      native.stopping = false;
      manager.clearExternalSubtitle(notifyListenersToo: false); // close
      native.stopping = true;
      manager.clearExternalSubtitle(notifyListenersToo: false); // idle
      manager.clearExternalSubtitle(notifyListenersToo: false); // reopen
      expect(native.poisoned, isFalse, reason: 'reopen $i must prepare');
    }
    expect(native.calls, isEmpty);
    expect(native.activeSubtitleTracks, [1]);
  });

  test('clearing an app-rendered SRT leaves the native selection unchanged',
      () async {
    final dir = await Directory.systemTemp.createTemp('mdk-reopen-srt-');
    addTearDown(() => dir.delete(recursive: true));
    final srt = File('${dir.path}/track.srt');
    await srt.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHello\n');
    final native = _StoppingMdk();
    final manager = SubtitleManager(player: Player.withDelegate(native));
    addTearDown(manager.dispose);
    manager.setExternalSubtitle(srt.path);
    await manager.preloadSubtitleFile(srt.path);
    expect(manager.getCurrentExternalSubtitleTextAt(500), 'Hello');
    final selectedTracks = List<int>.of(native.activeSubtitleTracks);
    native.calls.clear();

    native.stopping = true;
    manager.setExternalSubtitle('');
    expect(manager.currentExternalSubtitlePath, isNull);
    expect(manager.getAllActiveExternalSubtitlePaths(), isEmpty);
    expect(manager.getCurrentExternalSubtitleTextAt(500), '');
    expect(native.calls, isEmpty);
    expect(native.activeSubtitleTracks, selectedTracks);
    expect(native.poisoned, isFalse);
  });

  test('native external subtitles are unloaded once before stopping', () async {
    final dir = await Directory.systemTemp.createTemp('mdk-reopen-sup-');
    addTearDown(() => dir.delete(recursive: true));
    // Bitmap subtitles take the native path without encoding conversion.
    final sup = await File('${dir.path}/track.sup').writeAsBytes([0]);
    final native = _StoppingMdk();
    final manager = SubtitleManager(player: Player.withDelegate(native));
    addTearDown(manager.dispose);
    manager.setExternalSubtitle(sup.path);
    expect(native.calls, contains('media:${sup.path}'));
    native.calls.clear();

    manager.clearExternalSubtitle(notifyListenersToo: false);
    expect(native.calls.where((e) => e == 'media:'), hasLength(1));
    native.stopping = true;
    manager.clearExternalSubtitle(notifyListenersToo: false);
    manager.clearExternalSubtitle(notifyListenersToo: false);
    // Cancelled visibility/track retries must not reactivate the old subtitle.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(native.calls.where((e) => e == 'media:'), hasLength(1));
    expect(native.poisoned, isFalse);
  });

  test('clearing a mixed stack still unloads its native external subtitle',
      () async {
    final dir = await Directory.systemTemp.createTemp('mdk-reopen-mixed-');
    addTearDown(() => dir.delete(recursive: true));
    final sup = await File('${dir.path}/track.sup').writeAsBytes([0]);
    final srt = File('${dir.path}/track.srt');
    await srt.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHello\n');
    final native = _StoppingMdk();
    final manager = SubtitleManager(player: Player.withDelegate(native));
    addTearDown(manager.dispose);
    manager.setExternalSubtitle(sup.path);
    manager.setExternalSubtitle(srt.path, preserveStack: true);
    await manager.preloadSubtitleFile(srt.path);
    expect(manager.currentExternalSubtitlePath, srt.path);
    native.calls.clear();

    manager.setExternalSubtitle('');
    expect(native.calls.where((e) => e == 'media:'), hasLength(1));
    native.stopping = true;
    manager.clearExternalSubtitle(notifyListenersToo: false);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(native.poisoned, isFalse);
    expect(manager.getAllActiveExternalSubtitlePaths(), isEmpty);
  });
}
