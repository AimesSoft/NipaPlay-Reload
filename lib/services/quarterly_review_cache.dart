import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small persistent index used by the home review. Reading it never calls an API.
class QuarterlyReviewCache {
  QuarterlyReviewCache._();

  static final QuarterlyReviewCache instance = QuarterlyReviewCache._();
  static const _storageKey = 'quarterly_review_cache_v1';
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<void>? _loading;
  Future<void> _pendingWrite = Future.value();
  Timer? _expiryTimer;
  final Map<int, Map<String, dynamic>> _anime = {};
  final Map<String, Map<String, dynamic>> _collections = {};
  final Map<int, int> _metadataAttempts = {};
  final Set<int> _checkedLocal = {};
  int _year = 0;
  String _metadataProbeDay = '';
  int _metadataProbeCount = 0;
  int _metadataProbeAt = 0;
  String _collectionProbeDay = '';
  int _collectionProbeCount = 0;

  static int seasonMonth(DateTime date) => ((date.month - 1) ~/ 3) * 3 + 1;

  /// The review is shown for the last month of each season and the first
  /// seven days of the following month, including the year boundary.
  static DateTime? visibleReviewSeason(DateTime date) {
    if (date.month == 3 ||
        date.month == 6 ||
        date.month == 9 ||
        date.month == 12) {
      return DateTime(date.year, date.month - 2);
    }
    if (date.day <= 7 &&
        (date.month == 1 ||
            date.month == 4 ||
            date.month == 7 ||
            date.month == 10)) {
      return DateTime(date.year, date.month - 3);
    }
    return null;
  }

  static int daysUntilReviewCloses(DateTime season, DateTime now) =>
      DateTime.utc(season.year, season.month + 3, 8)
          .difference(DateTime.utc(now.year, now.month, now.day))
          .inDays;

  static DateTime _retainedFrom(DateTime now) =>
      visibleReviewSeason(now) ?? DateTime(now.year, seasonMonth(now));

  static int _seasonKey(DateTime date) => date.year * 4 + (date.month - 1) ~/ 3;

  static DateTime? parseAirDate(String? raw) {
    if (raw == null) return null;
    final match = RegExp(
      r'^(\d{4})\s*(?:[-/.]|年)\s*(\d{1,2})\s*(?:[-/.]|月)\s*(\d{1,2})(?:日)?',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  static DateTime? broadcastStartDate(BangumiAnime anime) {
    for (final entry in anime.metadata ?? const <String>[]) {
      final match =
          RegExp(r'^放送开始(?:日期|时间)?\s*[:：]\s*(.+)$').firstMatch(entry.trim());
      if (match == null) continue;
      final date = parseAirDate(match.group(1));
      if (date != null) return date;
    }
    return null;
  }

  static DateTime? matchingReviewDate(
      DateTime? airDate, DateTime? broadcastStart, DateTime season) {
    if (airDate != null && _seasonKey(airDate) == _seasonKey(season)) {
      return airDate;
    }
    if (broadcastStart != null &&
        _seasonKey(broadcastStart) == _seasonKey(season)) {
      return broadcastStart;
    }
    return null;
  }

  static int? subjectId(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) return null;
    final queryId = int.tryParse(uri.queryParameters['subject_id'] ?? '');
    if (queryId != null) return queryId;
    for (var i = uri.pathSegments.length - 1; i >= 0; i--) {
      final id = int.tryParse(uri.pathSegments[i]);
      if (id != null) return id;
    }
    return null;
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var needsReindex = false;
    try {
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final data = json.decode(raw) as Map<String, dynamic>;
        needsReindex = (data['schema'] as num?)?.toInt() != 2;
        _year = (data['year'] as num?)?.toInt() ?? 0;
        for (final entry in (data['anime'] as Map? ?? {}).entries) {
          final id = int.tryParse(entry.key.toString());
          if (id != null && entry.value is Map) {
            _anime[id] = Map<String, dynamic>.from(entry.value as Map);
          }
        }
        for (final entry in (data['collections'] as Map? ?? {}).entries) {
          if (entry.value is Map) {
            _collections[entry.key.toString()] =
                Map<String, dynamic>.from(entry.value as Map);
          }
        }
        for (final entry in (data['attempts'] as Map? ?? {}).entries) {
          final id = int.tryParse(entry.key.toString());
          if (id != null && entry.value is num) {
            _metadataAttempts[id] = (entry.value as num).toInt();
          }
        }
        _checkedLocal.addAll((data['checkedLocal'] as List? ?? [])
            .whereType<num>()
            .map((id) => id.toInt()));
        _metadataProbeDay = data['metadataProbeDay'] as String? ?? '';
        _metadataProbeCount =
            (data['metadataProbeCount'] as num?)?.toInt() ?? 0;
        _metadataProbeAt = (data['metadataProbeAt'] as num?)?.toInt() ?? 0;
        _collectionProbeDay = data['collectionProbeDay'] as String? ?? '';
        _collectionProbeCount =
            (data['collectionProbeCount'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {
      _anime.clear();
      _collections.clear();
      _metadataAttempts.clear();
      _checkedLocal.clear();
    }
    if (needsReindex) {
      // Upgrade existing review rows from the local detail cache without
      // issuing requests. Revisit candidates that were previously skipped.
      for (final id in _anime.keys.toList()) {
        final raw = prefs.getString('bangumi_detail_$id');
        if (raw == null) continue;
        try {
          final detail = json.decode(raw) as Map<String, dynamic>;
          _recordAnime(BangumiAnime.fromJson(
              Map<String, dynamic>.from(detail['animeDetail'] as Map)));
        } catch (_) {}
      }
      _checkedLocal.clear();
    }
    final pruned = _prune(DateTime.now());
    if (needsReindex || pruned) await _save();
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _expiryTimer = Timer(nextMidnight.difference(now), () {
      unawaited(_expireQuarter());
    });
  }

  Future<void> _expireQuarter() async {
    try {
      if (_prune(DateTime.now())) {
        await _save();
      }
    } catch (_) {
      // Retry persistence on the next daily rollover or cache access.
    } finally {
      // The visible review month also changes at midnight when no rows expire.
      revision.value++;
      _scheduleExpiry();
    }
  }

  bool _prune(DateTime now) {
    var changed = false;
    if (_year != now.year) {
      _year = now.year;
      _metadataAttempts.clear();
      _checkedLocal.clear();
      _metadataProbeDay = '';
      _metadataProbeCount = 0;
      _metadataProbeAt = 0;
      _collectionProbeDay = '';
      _collectionProbeCount = 0;
      changed = true;
    }
    final oldestSeason = _seasonKey(_retainedFrom(now));
    final before = _anime.length;
    _anime.removeWhere((_, data) {
      final airDate = parseAirDate(data['airDate'] as String?);
      final broadcastStart = parseAirDate(data['broadcastStart'] as String?);
      return ![airDate, broadcastStart].whereType<DateTime>().any(
            (date) =>
                date.year <= now.year + 1 && _seasonKey(date) >= oldestSeason,
          );
    });
    if (_anime.length != before) changed = true;
    final retainedSubjects = _anime.values
        .map((data) => subjectId(data['bangumiUrl'] as String?))
        .whereType<int>()
        .toSet();
    final collectionBefore = _collections.length;
    _collections.removeWhere((key, _) =>
        !retainedSubjects.contains(int.tryParse(key.split(':').last)));
    if (_collections.length != collectionBefore) changed = true;
    return changed;
  }

  Future<void> _save() {
    final next = _pendingWrite.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKey,
          json.encode({
            'schema': 2,
            'year': _year,
            'anime': _anime.map((id, data) => MapEntry('$id', data)),
            'collections': _collections,
            'attempts':
                _metadataAttempts.map((id, time) => MapEntry('$id', time)),
            'checkedLocal': _checkedLocal.toList(),
            'metadataProbeDay': _metadataProbeDay,
            'metadataProbeCount': _metadataProbeCount,
            'metadataProbeAt': _metadataProbeAt,
            'collectionProbeDay': _collectionProbeDay,
            'collectionProbeCount': _collectionProbeCount,
          }));
    });
    _pendingWrite = next;
    return next;
  }

  bool _recordAnime(BangumiAnime anime) {
    final airDate = parseAirDate(anime.airDate);
    final broadcastStart = broadcastStartDate(anime) ??
        parseAirDate(_anime[anime.id]?['broadcastStart'] as String?);
    final now = DateTime.now();
    if (anime.id <= 0 ||
        ![airDate, broadcastStart].whereType<DateTime>().any(
              (date) =>
                  date.year <= now.year + 1 &&
                  _seasonKey(date) >= _seasonKey(_retainedFrom(now)),
            )) {
      return false;
    }
    final data = <String, dynamic>{
      'id': anime.id,
      'name': anime.name,
      'nameCn': anime.nameCn,
      'imageUrl': anime.imageUrl,
      'airDate': anime.airDate,
      'broadcastStart': broadcastStart?.toIso8601String().split('T').first,
      'bangumiUrl': anime.bangumiUrl,
    };
    if (mapEquals(_anime[anime.id], data)) return false;
    _anime[anime.id] = data;
    return true;
  }

  Future<void> recordAnime(BangumiAnime anime) async {
    await load();
    if (!_recordAnime(anime)) return;
    await _save();
    revision.value++;
  }

  /// Imports the app's existing detail cache without refreshing expired API data.
  Future<void> adoptExistingDetails(Set<int> ids) async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    var changed = false;
    for (final id in ids) {
      if (_checkedLocal.contains(id)) continue;
      _checkedLocal.add(id);
      changed = true;
      final raw = prefs.getString('bangumi_detail_$id');
      if (raw == null) continue;
      try {
        final data = json.decode(raw) as Map<String, dynamic>;
        final anime = BangumiAnime.fromJson(
            Map<String, dynamic>.from(data['animeDetail'] as Map));
        if (_recordAnime(anime)) changed = true;
      } catch (_) {}
    }
    if (changed) {
      await _save();
      revision.value++;
    }
  }

  Future<List<QuarterlyReviewCachedItem>> itemsFor(
      Set<int> ids, DateTime now, String? username) async {
    await load();
    if (_prune(now)) await _save();
    final season =
        visibleReviewSeason(now) ?? DateTime(now.year, seasonMonth(now));
    final items = <QuarterlyReviewCachedItem>[];
    for (final id in ids) {
      final data = _anime[id];
      if (data == null) continue;
      final airDate = parseAirDate(data['airDate'] as String?);
      final broadcastStart = parseAirDate(data['broadcastStart'] as String?);
      final date = matchingReviewDate(airDate, broadcastStart, season);
      if (date == null) continue;
      final sid = subjectId(data['bangumiUrl'] as String?);
      final collection = username == null || sid == null
          ? null
          : _collections['$username:$sid'];
      items.add(QuarterlyReviewCachedItem(
        anime: BangumiAnime(
          id: id,
          name: data['name'] as String? ?? '',
          nameCn: data['nameCn'] as String? ?? '',
          imageUrl: data['imageUrl'] as String? ?? '',
          airDate: data['airDate'] as String?,
          metadata: broadcastStart == null
              ? null
              : ['放送开始: ${data['broadcastStart']}'],
          bangumiUrl: data['bangumiUrl'] as String?,
        ),
        airDate: date,
        dateLabel: date == airDate ? '开播' : '放送开始',
        rating: (collection?['rating'] as num?)?.toInt(),
        comment: collection?['comment'] as String?,
        commentAt: (collection?['updatedAt'] as num?)?.toInt(),
      ));
    }
    return items;
  }

  Future<void> recordCollection(
      int subjectId, String username, Map<String, dynamic>? data) async {
    await load();
    if (username.isEmpty ||
        !_anime.values.any((anime) =>
            QuarterlyReviewCache.subjectId(anime['bangumiUrl'] as String?) ==
            subjectId)) {
      return;
    }
    final rawRating = data?['rating'];
    final score = rawRating is Map ? rawRating['score'] : rawRating;
    final rate = score is num ? score : data?['rate'];
    final comment =
        data?['comment'] is String ? (data!['comment'] as String).trim() : '';
    final rawUpdated = data?['updated_at'] ?? data?['updatedAt'];
    final numericTime = rawUpdated is num
        ? rawUpdated.toInt()
        : int.tryParse(rawUpdated?.toString() ?? '');
    final updatedAt = numericTime != null
        ? (numericTime < 100000000000 ? numericTime * 1000 : numericTime)
        : DateTime.tryParse(rawUpdated?.toString() ?? '')
            ?.millisecondsSinceEpoch;
    _collections['$username:$subjectId'] = {
      'rating': rate is num && rate > 0 ? rate.toInt() : null,
      'comment': comment.isEmpty ? null : comment,
      'updatedAt': updatedAt,
      'checkedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _save();
    revision.value++;
  }

  Future<void> recordCollectionPatch(int subjectId, String username,
      {int? rating, String? comment}) async {
    await load();
    if (username.isEmpty) return;
    final key = '$username:$subjectId';
    if (!_collections.containsKey(key) &&
        !_anime.values.any((anime) =>
            QuarterlyReviewCache.subjectId(anime['bangumiUrl'] as String?) ==
            subjectId)) {
      return;
    }
    final current = Map<String, dynamic>.from(_collections[key] ?? {});
    if (rating != null) {
      current['rating'] = rating;
    }
    if (comment != null) {
      current['comment'] = comment.trim().isEmpty ? null : comment.trim();
    }
    current['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    current['checkedAt'] = DateTime.now().millisecondsSinceEpoch;
    _collections[key] = current;
    await _save();
    revision.value++;
  }

  Future<int?> reserveMetadataProbe(Set<int> ids, DateTime now) async {
    await load();
    final day = '${now.year}-${now.month}-${now.day}';
    if (_metadataProbeDay != day) {
      _metadataProbeDay = day;
      _metadataProbeCount = 0;
    }
    if (_metadataProbeCount >= 2 ||
        now.millisecondsSinceEpoch - _metadataProbeAt <
            const Duration(hours: 4).inMilliseconds) {
      return null;
    }
    final candidates = ids
        .where((id) =>
            id > 0 &&
            (_anime[id]?['broadcastStart'] == null) &&
            now.millisecondsSinceEpoch - (_metadataAttempts[id] ?? 0) >
                const Duration(days: 30).inMilliseconds)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (candidates.isEmpty) return null;
    final id = candidates.first;
    _metadataProbeCount++;
    _metadataProbeAt = now.millisecondsSinceEpoch;
    _metadataAttempts[id] = now.millisecondsSinceEpoch;
    await _save();
    return id;
  }

  Future<int?> reserveCollectionProbe(
      Set<int> ids, String username, DateTime now) async {
    await load();
    if (username.isEmpty) return null;
    final day = '${now.year}-${now.month}-${now.day}';
    if (_collectionProbeDay != day) {
      _collectionProbeDay = day;
      _collectionProbeCount = 0;
    }
    if (_collectionProbeCount >= 1) return null;
    final targetSeason =
        visibleReviewSeason(now) ?? DateTime(now.year, seasonMonth(now));
    for (final id in ids) {
      final data = _anime[id];
      if (data == null) continue;
      final date = matchingReviewDate(
        parseAirDate(data['airDate'] as String?),
        parseAirDate(data['broadcastStart'] as String?),
        targetSeason,
      );
      if (date == null) {
        continue;
      }
      final sid = subjectId(data['bangumiUrl'] as String?);
      if (sid == null) continue;
      final checked =
          (_collections['$username:$sid']?['checkedAt'] as num?)?.toInt();
      if (checked != null &&
          now.millisecondsSinceEpoch - checked <
              const Duration(days: 14).inMilliseconds) {
        continue;
      }
      _collectionProbeCount++;
      await _save();
      return sid;
    }
    return null;
  }
}

class QuarterlyReviewCachedItem {
  const QuarterlyReviewCachedItem(
      {required this.anime,
      required this.airDate,
      required this.dateLabel,
      this.rating,
      this.comment,
      this.commentAt});

  final BangumiAnime anime;
  final DateTime airDate;
  final String dateLabel;
  final int? rating;
  final String? comment;
  final int? commentAt;
}
