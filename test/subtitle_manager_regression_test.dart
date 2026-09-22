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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
