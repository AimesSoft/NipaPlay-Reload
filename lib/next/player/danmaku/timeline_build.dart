import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'package:nipaplay/constants/danmaku_color_presets.dart';
import 'package:nipaplay/services/danmaku_density_analyzer.dart';
import 'package:nipaplay/services/intro_skip/danmaku_intro_detector.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/services/timeline_danmaku_service.dart';

/// All functions in this file run on the timeline worker, including rules,
/// folding, density, segment detection and inspection pagination.
///
/// The list itself stays on the worker: one isolate group shares a heap, so
/// a worker that allocates tens of thousands of maps and a main isolate that
/// then holds a copy of them make every collection stop the main isolate for
/// longer. The main isolate gets [view]: counts, heat, segments, and asks for
/// windows and pages when it needs them.
final class DanmakuTimeline {
  const DanmakuTimeline(this.entries, this.heat, this.segments, this.buildUs,
      this.total, this.invalidRules,
      {this.spoilerCandidates = const [], this.spoilerHash = '', int? count})
      : _count = count;
  final List<Map<String, dynamic>> entries;
  final int? _count;

  /// What is shown (after the rules), whether or not [entries] is here.
  int get count => _count ?? entries.length;

  DanmakuTimeline view() => DanmakuTimeline(const [], heat, segments, buildUs,
      total, invalidRules,
      spoilerCandidates: spoilerCandidates, spoilerHash: spoilerHash,
      count: entries.length);

  final List<double> heat;
  final List<SkipSegment> segments;
  final int buildUs, total;
  final List<String> invalidRules;

  /// What spoiler analysis would be asked about (Classic: the first 1200
  /// distinct normalised texts of the merged list) and its digest.
  final List<String> spoilerCandidates;
  final String spoilerHash;

  static const empty = DanmakuTimeline([], [], [], 0, 0, []);
}

DanmakuTimeline buildTimeline(Map<String, Map<String, dynamic>> tracks,
    Map<String, Object?> settings, int durationMs,
    List<Map<String, dynamic>> chapters,
    {Set<String> spoilerTexts = const {},
    List<Map<String, dynamic>> externalSegments = const []}) {
  final watch = Stopwatch()..start();
  // Classic's rule format (video_player_state_subtitles.dart `_isRegexRule`):
  // `name/expression/`; anything else is a literal. Each rule is compiled
  // once here, not once per comment.
  final literals = <String>[];
  final regexps = <RegExp>[];
  final invalid = <String>[];
  for (final rule in settings['danmaku.blockWords'] as List? ?? const []) {
    final text = rule as String;
    final parts = text.split('/');
    if (parts.length >= 3 && parts.first.isNotEmpty && parts.last.isEmpty) {
      try {
        regexps.add(RegExp(text.substring(text.indexOf('/') + 1, text.length - 1)));
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
      // The maps are the worker's own: set what this build derives in place
      // instead of copying every comment (tens of thousands of maps per build
      // is what made collections long).
      entry['time'] = mapped / 1000;
      entry['nextTrackId'] = track.key;
      entry['foldEnabled'] = binding['deduplicate'] == 1;
      entry['aggregation'] = (binding['video'] as Map)['sourceId'] == 'dandanplay';
      merged.add(entry);
    }
  }
  if (settings['danmaku.timelineEnabled'] == true && durationMs > 0) {
    final timeline = TimelineDanmakuService.generateTimelineDanmaku(
        Duration(milliseconds: durationMs));
    for (final comment in timeline['comments'] as List) {
      final entry = Map<String, dynamic>.from(comment as Map);
      merged.add({
        ...entry,
        'sourceTimeMs': ((entry['time'] as num) * 1000).round(),
        'nextTrackId': 'timeline',
        'foldEnabled': false,
        'aggregation': false,
        'source': 'timeline',
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
  // One slot per kind, filled by rank (Classic's `mergeSkipSegmentSlot`):
  // a signal is taken unless the slot holds a more trusted one. Signals from
  // outside (media server, manual) come first; their rank decides.
  final slots = <SkipSegmentKind, SkipSegment>{};
  void offer(SkipSegment? candidate) {
    if (candidate == null) return;
    final merged = mergeSkipSegmentSlot(slots[candidate.kind], candidate);
    if (merged.accepted) slots[candidate.kind] = merged.segment;
  }
  for (final raw in externalSegments) {
    offer(SkipSegment(
        kind: SkipSegmentKind.values.byName(raw['kind'] as String),
        source: SkipSegmentSource.values.byName(raw['source'] as String),
        startSeconds: (raw['startSeconds'] as num).toDouble(),
        endSeconds: (raw['endSeconds'] as num).toDouble(),
        evidenceCount: raw['evidenceCount'] as int? ?? 0));
  }
  offer(intro);
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
    // The first chapter of a kind is the one that counts.
    if (slots[kind]?.source == SkipSegmentSource.chapterHeuristic) continue;
    offer(SkipSegment(kind: kind,
        source: SkipSegmentSource.chapterHeuristic,
        startSeconds: start / 1000,
        endSeconds: math.min(end, durationMs.toDouble()) / 1000));
  }
  final segments = slots.values.toList();
  merged = _foldSources(merged);
  final candidates = <String>[];
  final seen = <String>{};
  for (final e in merged) {
    final normalized = normalizeSpoilerText(e['content'] as String);
    if (normalized.isNotEmpty && seen.add(normalized)) {
      candidates.add(normalized);
      if (candidates.length >= 1200) break;
    }
  }
  final filtered = <Map<String, dynamic>>[];
  for (final e in merged) {
    final type = e['type'] as String;
    final text = e['content'] as String;
    if (settings['danmaku.block${type[0].toUpperCase()}${type.substring(1)}'] == true ||
        (spoilerTexts.isNotEmpty && spoilerTexts.contains(normalizeSpoilerText(text))) ||
        literals.any(text.contains) || regexps.any((r) => r.hasMatch(text))) {
      continue;
    }
    // Same-comment merging (the count and the larger type) belongs to the
    // renderers, as in Classic; they get the setting, not a folded list.
    filtered.add(settings['danmaku.randomColor'] == true ? _randomColor(e) : e);
  }
  // Classic: 120 segments over whole seconds, peak-normalised, counted on
  // the displayed list without the manual offset.
  final points = DanmakuDensityAnalyzer.analyzeDensity(
      danmakuList: filtered, videoDurationSeconds: durationMs ~/ 1000,
      segmentCount: 120);
  final peak = points.fold<int>(0, (a, p) => math.max(a, p.count));
  final heat = peak == 0 ? <double>[] : [for (final p in points) p.count / peak];
  return DanmakuTimeline(filtered, heat, segments,
      watch.elapsedMicroseconds, total, invalid,
      spoilerCandidates: candidates,
      spoilerHash: sha1.convert(utf8.encode(candidates.join('\u0000'))).toString());
}

/// Classic's `_normalizeSpoilerMatchText`.
String normalizeSpoilerText(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? '' : trimmed.replaceAll(RegExp(r'\s+'), ' ');
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
        'sourceTimeMs': e['sourceTimeMs']});
    }
    total++;
  }
  return {'sessionId': sessionId, 'listVersion': version,
    'view': 'display_timeline', 'positionMs': position, 'items': rows,
    'nextCursor': cursor + rows.length < total ? cursor + rows.length : null,
    'total': total};
}


/// Classic's `_resolveRandomizedDanmakuColor`: the same palette and the same
/// stable hash, so a comment keeps its colour across the two layers.
Map<String, dynamic> _randomColor(Map<String, dynamic> item) {
  final palette = DanmakuColorPresets.randomColorfulDanmakuColors;
  final time = (item['time'] ?? item['t']) as num? ?? 0;
  final safe = time.isNaN || time.isInfinite ? 0.0 : (time < 0 ? 0.0 : time.toDouble());
  final timeText = safe.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  final content = (item['content'] ?? item['c'] ?? '').toString();
  final type = (item['type'] ?? item['y'] ?? '').toString();
  final id = (item['id'] ?? item['cid'] ?? item['p'] ?? '').toString();
  var hash = 2166136261;
  for (final code in '$timeText|$type|$id|$content'.codeUnits) {
    hash ^= code;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  final color = DanmakuColorPresets.toRgbString(palette[(hash & 0x7fffffff) % palette.length]);
  if ((item['color'] ?? item['r'])?.toString() == color) return item;
  return {...item, 'color': color, 'r': color};
}


/// The comments shown between [from] and [to] seconds (as the renderers that
/// lay out for themselves take them).
List<Map<String, dynamic>> windowOf(
    DanmakuTimeline timeline, double from, double to) {
  int bound(double seconds) {
    var lo = 0, hi = timeline.entries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if ((timeline.entries[mid]['time'] as num) < seconds) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
  return timeline.entries.sublist(bound(from), bound(to));
}
