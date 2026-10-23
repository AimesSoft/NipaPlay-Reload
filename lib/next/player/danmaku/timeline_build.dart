import 'dart:math' as math;

import 'package:nipaplay/services/intro_skip/danmaku_intro_detector.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';

/// All functions in this file run on the timeline worker, including rules,
/// folding, density, segment detection and inspection pagination.
final class DanmakuTimeline {
  const DanmakuTimeline(this.entries, this.heat, this.segments, this.buildUs,
      this.total, this.invalidRules);
  final List<Map<String, dynamic>> entries;
  final List<double> heat;
  final List<SkipSegment> segments;
  final int buildUs, total;
  final List<String> invalidRules;

  static const empty = DanmakuTimeline([], [], [], 0, 0, []);
}

DanmakuTimeline buildTimeline(Map<String, Map<String, dynamic>> tracks,
    Map<String, Object?> settings, int durationMs,
    List<Map<String, dynamic>> chapters) {
  final watch = Stopwatch()..start();
  final literals = <String>[];
  final regexps = <RegExp>[];
  final invalid = <String>[];
  for (final rule in settings['danmaku.blockWords'] as List? ?? const []) {
    final text = rule as String;
    final slash = text.indexOf('/');
    if (slash > 0 && text.endsWith('/')) {
      try {
        regexps.add(RegExp(text.substring(slash + 1, text.length - 1)));
      } on FormatException {
        invalid.add(text);
      }
    } else {
      literals.add(text);
    }
  }
  var merged = <Map<String, dynamic>>[];
  for (final track in tracks.entries) {
    final data = track.value;
    if (data['enabled'] != true) continue;
    final binding = data['binding'] as Map<String, dynamic>;
    final startMs = data['startMs'] as int;
    final offset = binding['offset_ms'] as int? ?? 0;
    final endMs = data['endMs'] as int?;
    for (final entry in data['entries'] as List<Map<String, dynamic>>) {
      final mapped = (entry['sourceTimeMs'] as int) + startMs - offset;
      if (endMs != null && mapped >= endMs) continue;
      merged.add({
        ...entry,
        'time': mapped / 1000,
        'nextTrackId': track.key,
        'foldEnabled': binding['deduplicate'] == 1,
        'aggregation': (binding['video'] as Map)['sourceId'] == 'dandanplay',
      });
    }
  }
  merged.sort((a, b) => (a['time'] as num).compareTo(b['time'] as num));
  final total = merged.length;
  // Detection uses the unfurled input, so hiding/folding comments cannot
  // remove the underlying evidence.
  final intro = DanmakuIntroDetector.detect([
    for (final e in merged) DanmakuTextEntry.fromMap(e),
  ], durationSeconds: durationMs > 0 ? durationMs / 1000 : null);
  final segments = <SkipSegment>[
    if (intro != null) intro,
  ];
  for (var i = 0; i < chapters.length; i++) {
    final c = chapters[i];
    final title = (c['title'] ?? '').toString();
    final opening = RegExp(r'(^|\W)(op|opening|intro)(\W|$)|片头|片頭',
        caseSensitive: false).hasMatch(title);
    final ending = RegExp(r'(^|\W)(ed|ending|outro)(\W|$)|片尾',
        caseSensitive: false).hasMatch(title);
    if (!opening && !ending) continue;
    final start = (c['startMs'] as num?)?.toDouble() ?? 0;
    final end = (c['endMs'] as num?)?.toDouble() ??
        (i + 1 < chapters.length
            ? (chapters[i + 1]['startMs'] as num).toDouble()
            : durationMs.toDouble());
    if (end <= start || durationMs <= 0) continue;
    final kind = opening ? SkipSegmentKind.opening : SkipSegmentKind.ending;
    if (segments.any((s) => s.kind == kind)) continue;
    segments.add(SkipSegment(kind: kind,
        source: SkipSegmentSource.chapterHeuristic,
        startSeconds: start / 1000,
        endSeconds: math.min(end, durationMs.toDouble()) / 1000));
  }
  merged = _foldSources(merged);
  final filtered = <Map<String, dynamic>>[];
  final groups = <String, Map<String, dynamic>>{};
  for (final e in merged) {
    final type = e['type'] as String;
    final text = e['content'] as String;
    if (settings['danmaku.block${type[0].toUpperCase()}${type.substring(1)}'] == true ||
        literals.any(text.contains) || regexps.any((r) => r.hasMatch(text))) {
      continue;
    }
    if (settings['danmaku.merge'] == true) {
      final key = '$type|$text';
      final previous = groups[key];
      if (previous != null &&
          (e['time'] as num) - (previous['time'] as num) <= 10) {
        previous['mergeCount'] = (previous['mergeCount'] as int? ?? 1) + 1;
        continue;
      }
      groups[key] = e;
    }
    if (settings['danmaku.randomColor'] == true) {
      var hash = 2166136261;
      for (final code in '${e['time']}|$type|${e['id'] ?? ''}|$text'.codeUnits) {
        hash = ((hash ^ code) * 16777619) & 0x7fffffff;
      }
      const colors = ['rgb(255,114,116)', 'rgb(64,199,255)',
        'rgb(109,255,105)', 'rgb(255,223,88)', 'rgb(220,160,255)'];
      e['color'] = colors[hash % colors.length];
    }
    filtered.add(e);
  }
  final counts = List<double>.filled(100, 0);
  final offset = (settings['danmaku.manualOffset'] as num?)?.toDouble() ?? 0;
  if (durationMs > 0) {
    for (final e in filtered) {
      final at = (e['time'] as num).toDouble() - offset;
      if (at < 0 || at * 1000 > durationMs) continue;
      counts[math.min(99, (at * 100000 / durationMs).floor())]++;
    }
  }
  final maxCount = counts.fold<double>(0, math.max);
  final heat = maxCount == 0 ? <double>[]
      : [for (final c in counts) c / maxCount];
  return DanmakuTimeline(filtered, heat, segments,
      watch.elapsedMicroseconds, total, invalid);
}

/// Classic's cross-source folding rules, with tuple keys instead of a JSON
/// encoder and without cloning maps already owned by this worker.
List<Map<String, dynamic>> _foldSources(List<Map<String, dynamic>> input) {
  final result = <Map<String, dynamic>>[];
  final identities = <(Object?, Object?, Object?), Map<String, dynamic>>{};
  final groups = <(String, Object?, Object?), List<Map<String, dynamic>>>{};
  for (final item in input) {
    final track = item['nextTrackId'] ?? item['sourceId'] ?? item['source'];
    final reliable = item['platformVideoId'] != null &&
        item['platformDanmakuId'] != null && item['source'] != 'unknown';
    final key = reliable ? (item['source'], item['platformVideoId'], item['platformDanmakuId']) : null;
    bool hasTrack(Map<String, dynamic> candidate) =>
        (candidate['displayMembers'] as List<Map<String, dynamic>>)
            .any((m) => m['trackId'] == track);
    Map<String, dynamic>? duplicate;
    if (key != null) {
      final candidate = identities[key];
      if (candidate != null && candidate['nextTrackId'] != item['nextTrackId'] &&
          candidate['foldEnabled'] == true && item['foldEnabled'] == true &&
          !hasTrack(candidate) &&
          ((candidate['time'] as num) - (item['time'] as num)).abs() <= .1) {
        duplicate = candidate;
      }
    }
    final text = item['content'] as String;
    final textKey = (text, item['type'], item['color']);
    final candidates = groups[textKey] ??= [];
    if (duplicate == null && text.runes.length >= 8 && item['foldEnabled'] == true) {
      for (final candidate in candidates.reversed) {
        if ((item['time'] as num) - (candidate['time'] as num) > .1) break;
        final candidateTrack = candidate['nextTrackId'] ?? candidate['sourceId'] ?? candidate['source'];
        final unknown = candidate['aggregation'] == true && candidate['source'] == 'unknown' ||
            item['aggregation'] == true && item['source'] == 'unknown';
        if (candidateTrack != track && !hasTrack(candidate) &&
            candidate['foldEnabled'] == true && unknown) {
          duplicate = candidate;
          break;
        }
      }
    }
    if (duplicate != null) {
      final members = duplicate['displayMembers'] as List<Map<String, dynamic>>;
      members.add({'trackId': track, 'source': item['source'], 'id': item['platformDanmakuId']});
      duplicate['displayCount'] = members.length;
    } else {
      item['displayMembers'] = <Map<String, dynamic>>[
        {'trackId': track, 'source': item['source'], 'id': item['platformDanmakuId']}];
      item['displayCount'] = 1;
      result.add(item);
      candidates.add(item);
      if (key != null) identities[key] = item;
    }
  }
  return result;
}

Map<String, dynamic> pageTimeline(DanmakuTimeline timeline,
    Map<String, dynamic> input, int version, String? sessionId, double offset) {
  final position = input['positionMs'] as int? ?? 0;
  final window = input['windowMs'] as int? ?? 5000;
  final start = input['startMs'] as int? ?? position - window;
  final end = input['endMs'] as int? ?? position + window;
  final cursor = input['cursor'] as int? ?? 0;
  final limit = input['limit'] as int? ?? 100;
  final rows = <Map<String, dynamic>>[];
  var total = 0;
  for (var i = 0; i < timeline.entries.length; i++) {
    final e = timeline.entries[i];
    final at = ((e['time'] as num) * 1000 - offset * 1000).round();
    if (at < start || at > end) continue;
    if (total >= cursor && rows.length < limit) {
      rows.add({'id': '$version:$i', 'mappedTimeMs': at,
        'text': e['content'], 'trackId': e['nextTrackId'],
        'provenance': e['originSource'], 'platform': e['source'],
        'sourceId': e['sourceId'], 'foldMembers': e['displayMembers'],
        'sourceTimeMs': e['sourceTimeMs'], 'mergeCount': e['mergeCount'] ?? 1});
    }
    total++;
  }
  return {'sessionId': sessionId, 'listVersion': version,
    'view': 'display_timeline', 'positionMs': position, 'items': rows,
    'nextCursor': cursor + rows.length < total ? cursor + rows.length : null,
    'total': total};
}
