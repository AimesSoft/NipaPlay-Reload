import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/subtitles/companions_io.dart';
import 'package:nipaplay/next/subtitles/detection.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import '../security/memory_vault.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pure Dart and Flutter fallback match the same names and episode scores', () async {
    final temporary = await Directory.systemTemp.createTemp('x58-match-');
    try {
      final cases = [
        ['Show S01E01', 'Show S01E01.chs'],
        ['Show S01E01', 'Show S01E02.chs'],
        ['Show S01E01', 'Show S02E01.chs'],
        ['Show 01', 'Other 01'],
        ['作品 01', '作品 01.简中'],
        ['Show 01', '[字幕组] Show 01.eng'],
      ];
      final input = await File('${temporary.path}/cases.json').writeAsString(jsonEncode(cases));
      final config = jsonDecode(await File('.dart_tool/package_config.json').readAsString()) as Map;
      final flutter = (config['packages'] as List).singleWhere((p) => p['name'] == 'flutter') as Map;
      final sdk = Directory.fromUri(Uri.parse(flutter['rootUri'] as String)).parent.parent;
      final process = await Process.run('${sdk.path}/bin/cache/dart-sdk/bin/dart',
          ['--packages=.dart_tool/package_config.json',
           'test/next/fixtures/subtitle_match_probe.dart', input.path]);
      expect(process.exitCode, 0, reason: '${process.stderr}');
      final result = jsonDecode(process.stdout as String) as List;
      expect(result.map((r) => r['matches']), [true, false, false, false, true, true]);
      for (final (i, names) in cases.indexed) {
        expect(result[i]['matches'], subtitleMatchesVideo(names[0], names[1]));
        expect(result[i]['score'], computeLocalSubtitleMatchScore(
            videoName: names[0], subtitleName: names[1], extension: '.ass',
            videoNumbers: ['01'], episodeNumber: '01'));
      }
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test('headless companions retain canonical bitmap pairs and reject wrong episodes', () async {
    final f = MediaFixture();
    await f.open();
    final ui = UiDataService(f.service, f.engine, StateCapability([]), StateSources(), f.root, MemoryVault());
    try {
      final id = await f.file('Show S01E01.mkv');
      final base = '${f.media.path}/Show S01E01';
      await File('$base.chs.srt').writeAsString('subtitle');
      await File('$base.eng.vtt').writeAsString('WEBVTT');
      await File('$base.bitmap.IDX').writeAsString('VobSub index');
      await File('$base.bitmap.SUB').writeAsBytes([0, 0, 1, 0xba, 1]);
      await File('$base.text.sub').writeAsString('{1}{25}text');
      await File('$base.orphan.idx').writeAsString('index');
      await File('${f.media.path}/Show S01E02.chs.srt').writeAsString('other');
      await File('${f.media.path}/Other S01E01.srt').writeAsString('other');
      final tracks = await subtitleCompanions(ui, id, '$base.mkv');
      final paths = tracks.map((t) => t['path']).toSet();
      expect(paths, {'$base.chs.srt', '$base.eng.vtt', '$base.bitmap.IDX', '$base.text.sub'});
      final candidates = await subtitleCandidates('$base.mkv');
      expect(candidates.map((c) => c.path).toSet(), paths);
      expect(await File('$base.bitmap.SUB').readAsBytes(), [0, 0, 1, 0xba, 1]);
    } finally {
      await ui.close();
      await f.close();
    }
  });
}
