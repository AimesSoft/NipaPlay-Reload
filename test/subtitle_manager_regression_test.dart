import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/subtitle_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnusedPlayerDelegate extends Fake implements AbstractPlayer {
  @override
  bool get supportsExternalSubtitles => false;

  @override
  List<int> get activeSubtitleTracks => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('subtitle index is replaced when a cached file changes', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory =
        await Directory.systemTemp.createTemp('subtitle-index-refresh-');
    final file = File('${directory.path}/track.srt');
    final manager =
        SubtitleManager(player: Player.withDelegate(_UnusedPlayerDelegate()));
    await file.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nFirst\n');
    manager.setExternalSubtitle(file.path);
    await manager.preloadSubtitleFile(file.path);
    expect(manager.getCurrentExternalSubtitleTextAt(500), 'First');
    await file
        .writeAsString('1\n00:00:00,000 --> 00:00:01,000\nReplacement text\n');
    await manager.preloadSubtitleFile(file.path);
    expect(manager.getCurrentExternalSubtitleTextAt(500), 'Replacement text');
    expect(manager.getCurrentExternalSubtitleTextAt(1000), 'Replacement text');
    expect(manager.getCurrentExternalSubtitleTextAt(1001), '');
    manager.dispose();
    await directory.delete(recursive: true);
  });

  test('preserves a saved remote subtitle with the current SHA-1 cache name',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final cacheDir = await Directory.systemTemp.createTemp('subtitle_mapping_');
    final cacheName =
        '${sha1.convert(utf8.encode('webdav:connection:episode.srt'))}.srt';
    final subtitle = File('${cacheDir.path}/$cacheName');
    await subtitle.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHello\n');

    final manager = SubtitleManager(
      player: Player.withDelegate(_UnusedPlayerDelegate()),
    );
    try {
      await manager.saveVideoSubtitleMapping(
          'webdav://connection/episode.mkv', subtitle.path);

      expect(
        await manager.getVideoSubtitlePath('webdav://connection/episode.mkv'),
        subtitle.path,
      );
      final prefs = await SharedPreferences.getInstance();
      final mappings = json.decode(prefs.getString('video_subtitle_map')!);
      expect(mappings['webdav://connection/episode.mkv'], subtitle.path);
    } finally {
      manager.dispose();
      await cacheDir.delete(recursive: true);
    }
  });

  test('retains stacked subtitles when the primary subtitle reloads', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final subtitleDir =
        await Directory.systemTemp.createTemp('subtitle_stack_');
    final primary = File('${subtitleDir.path}/primary.srt');
    final secondary = File('${subtitleDir.path}/secondary.srt');
    const content = '1\n00:00:00,000 --> 00:00:01,000\nHello\n';
    await primary.writeAsString(content);
    await secondary.writeAsString(content);

    final manager = SubtitleManager(
      player: Player.withDelegate(_UnusedPlayerDelegate()),
    );
    try {
      manager.setExternalSubtitle(primary.path);
      await manager.addExternalSubtitleToStack(secondary.path);

      manager.setExternalSubtitle(primary.path, preserveStack: true);
      await Future.wait(<Future<void>>[
        manager.preloadSubtitleFile(primary.path),
        manager.preloadSubtitleFile(secondary.path),
      ]);

      expect(manager.getAllActiveExternalSubtitlePaths(),
          <String>[primary.path, secondary.path]);
    } finally {
      manager.dispose();
      await subtitleDir.delete(recursive: true);
    }
  });
  test('episode reset clears the stack and pending stack additions', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final dir = await Directory.systemTemp.createTemp('subtitle_reset_');
    final subtitle = File('${dir.path}/episode1.srt');
    await subtitle.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHello\n');
    final manager =
        SubtitleManager(player: Player.withDelegate(_UnusedPlayerDelegate()));
    try {
      manager.setCurrentVideoPath('${dir.path}/episode1.mkv');
      manager.setExternalSubtitle(subtitle.path);
      await manager.preloadSubtitleFile(subtitle.path);
      manager.clearExternalSubtitle(notifyListenersToo: false);
      manager.setCurrentVideoPath('${dir.path}/episode2.mkv');
      expect(manager.getAllActiveExternalSubtitlePaths(), isEmpty);
      expect(manager.shouldRenderCurrentExternalSubtitleInApp(), isFalse);
      final pending = manager.addExternalSubtitleToStack(subtitle.path);
      manager.clearExternalSubtitle(notifyListenersToo: false);
      await pending;
      expect(manager.getAllActiveExternalSubtitlePaths(), isEmpty);
    } finally {
      manager.dispose();
      await dir.delete(recursive: true);
    }
  });
}
