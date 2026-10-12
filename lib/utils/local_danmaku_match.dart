import 'dart:io';
import 'package:path/path.dart' as p;

/// Classic's filename ranking, shared by indexing and playback.
Future<List<String>> localDanmakuCandidates(String videoPath) async {
  final dir = Directory(p.dirname(videoPath));
  if (!await dir.exists()) return [];
  final base = p.basenameWithoutExtension(videoPath).toLowerCase();
  final candidates = <({String path, String name, int score})>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path), lower = name.toLowerCase();
    final ext = p.extension(lower);
    if (ext != '.xml' && ext != '.json') continue;
    final stem = p.basenameWithoutExtension(lower);
    var score = stem == base
        ? 100
        : stem.startsWith(base)
            ? 80
            : stem.contains(base)
                ? 60
                : 0;
    if (['danmaku', 'barrage', 'comment', '弹幕'].any(lower.contains)) {
      score += 20;
    }
    if (ext == '.xml') score += 3;
    if (score > 0) {
      candidates.add((path: entity.path, name: name, score: score));
    }
  }
  candidates.sort((a, b) => a.score != b.score
      ? b.score.compareTo(a.score)
      : a.name.compareTo(b.name));
  return candidates.take(8).map((c) => c.path).toList();
}
