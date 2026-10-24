import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import 'package:nipaplay/utils/subtitle_language_utils.dart';

const subtitleFormats = {...supportedSubtitleExtensions, '.vtt'};
String subtitleLanguage(String value) {
  if (RegExp(r'portuguese|(?:^|[^a-z])(?:por|pt)(?:$|[^a-z])',
          caseSensitive: false)
      .hasMatch(value)) {
    return 'pt';
  }
  return switch (getSubtitleLanguageName(value)) {
    '简体中文' => 'zh-Hans',
    '繁体中文' => 'zh-Hant',
    '中文' => 'zh',
    '英文' => 'en',
    '日语' => 'ja',
    '韩语' => 'ko',
    '法语' => 'fr',
    '德语' => 'de',
    '西班牙语' => 'es',
    '意大利语' => 'it',
    '俄语' => 'ru',
    '印尼语' => 'id',
    _ => RegExp(r'^[a-z]{2,3}(?:-[A-Za-z]+)?$').hasMatch(value) ? value : 'und',
  };
}

/// Shared Classic matcher, canonical VobSub pairs and deterministic score order.
Future<List<({String path, int score})>> subtitleCandidates(
    String video) async {
  final name = p.basenameWithoutExtension(video);
  final numbers = RegExp(r'\d+').allMatches(name).map((m) => m[0]!).toList();
  final candidates = <String, int>{};
  final siblings = await File(video).parent.list().toList();
  for (final entry in siblings) {
    if (entry is! File ||
        !subtitleFormats.contains(p.extension(entry.path).toLowerCase()) ||
        !isVobSubPairComplete(entry.path)) {
      continue;
    }
    final title = p.basenameWithoutExtension(entry.path);
    if (!subtitleMatchesVideo(name, title)) continue;
    final path = canonicalSubtitlePath(entry.path);
    candidates[path] = computeLocalSubtitleMatchScore(
        videoName: name,
        subtitleName: p.basenameWithoutExtension(path),
        extension: p.extension(path),
        videoNumbers: numbers,
        episodeNumber: pickLikelyEpisodeNumber(numbers));
  }
  // A language-only Subs folder belongs to the sole video beside it.
  final videos = siblings.whereType<File>().where((f) => {
        '.mkv',
        '.mp4',
        '.avi',
        '.mov',
        '.m4v',
        '.webm',
        '.ts'
      }.contains(p.extension(f.path).toLowerCase()));
  if (videos.length == 1) {
    for (final folder in siblings.whereType<Directory>().where((d) =>
        {'subs', 'subtitles'}.contains(p.basename(d.path).toLowerCase()))) {
      await for (final entry in folder.list()) {
        if (entry is! File ||
            !subtitleFormats.contains(p.extension(entry.path).toLowerCase()) ||
            !isVobSubPairComplete(entry.path)) {
          continue;
        }
        if (subtitleLanguage(p.basenameWithoutExtension(entry.path)) == 'und' &&
            !subtitleMatchesVideo(
                name, p.basenameWithoutExtension(entry.path))) {
          continue;
        }
        candidates[canonicalSubtitlePath(entry.path)] = 100;
      }
    }
  }
  return candidates.entries.map((e) => (path: e.key, score: e.value)).toList()
    ..sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score == 0 ? a.path.compareTo(b.path) : score;
    });
}
