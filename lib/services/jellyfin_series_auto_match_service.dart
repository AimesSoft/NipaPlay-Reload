import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/services/jellyfin_dandanplay_matcher.dart';
import 'package:nipaplay/services/jellyfin_episode_mapping_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef JellyfinAutoMatchEnabledLoader = Future<bool> Function();
typedef JellyfinMappingLoader = Future<Map<String, dynamic>?> Function(
  String seriesId,
);
typedef JellyfinSeasonLoader = Future<List<JellyfinSeasonInfo>> Function(
  String seriesId,
);
typedef JellyfinEpisodeLoader = Future<List<JellyfinEpisodeInfo>> Function(
  String seriesId,
  String seasonId,
);
typedef JellyfinVideoInfoLoader = Future<Map<String, dynamic>> Function(
  JellyfinEpisodeInfo episode,
);
typedef JellyfinExactMatcher = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> videoInfo,
);
typedef JellyfinSeriesMappingWriter = Future<int> Function(
  JellyfinMediaItem series,
  int animeId,
  String animeTitle,
);
typedef JellyfinEpisodeMappingWriter = Future<void> Function(
  JellyfinEpisodeInfo episode,
  int episodeId,
  int mappingId,
);

class JellyfinSeriesAutoMatchResult {
  const JellyfinSeriesAutoMatchResult({
    required this.animeId,
    required this.animeTitle,
    required this.episodeId,
  });

  final int animeId;
  final String animeTitle;
  final int? episodeId;
}

/// Optionally identifies an unmapped Jellyfin Series from one episode hash.
///
/// The service does not create watch-history entries. It only persists the
/// Series and representative Episode mappings used by the existing mapping
/// and playback layers.
class JellyfinSeriesAutoMatchService {
  JellyfinSeriesAutoMatchService({
    JellyfinAutoMatchEnabledLoader? isEnabled,
    JellyfinMappingLoader? loadMapping,
    JellyfinSeasonLoader? loadSeasons,
    JellyfinEpisodeLoader? loadEpisodes,
    JellyfinVideoInfoLoader? loadVideoInfo,
    JellyfinExactMatcher? matchExactly,
    JellyfinSeriesMappingWriter? writeSeriesMapping,
    JellyfinEpisodeMappingWriter? writeEpisodeMapping,
    DateTime Function()? clock,
  })  : _isEnabled = isEnabled ?? _defaultIsEnabled,
        _loadMapping = loadMapping ?? _defaultLoadMapping,
        _loadSeasons = loadSeasons ??
            ((seriesId) => JellyfinService.instance.getSeriesSeasons(seriesId)),
        _loadEpisodes = loadEpisodes ??
            ((seriesId, seasonId) =>
                JellyfinService.instance.getSeasonEpisodes(seriesId, seasonId)),
        _loadVideoInfo = loadVideoInfo ??
            JellyfinDandanplayMatcher.instance.calculateVideoHash,
        _matchExactly = matchExactly ??
            JellyfinDandanplayMatcher.instance.matchVideoInfoExactly,
        _writeSeriesMapping = writeSeriesMapping ?? _defaultWriteSeriesMapping,
        _writeEpisodeMapping =
            writeEpisodeMapping ?? _defaultWriteEpisodeMapping,
        _clock = clock ?? DateTime.now;

  static final JellyfinSeriesAutoMatchService instance =
      JellyfinSeriesAutoMatchService();

  static const Duration _failureCooldown = Duration(minutes: 30);
  static const int _maxConcurrentMatches = 2;

  final JellyfinAutoMatchEnabledLoader _isEnabled;
  final JellyfinMappingLoader _loadMapping;
  final JellyfinSeasonLoader _loadSeasons;
  final JellyfinEpisodeLoader _loadEpisodes;
  final JellyfinVideoInfoLoader _loadVideoInfo;
  final JellyfinExactMatcher _matchExactly;
  final JellyfinSeriesMappingWriter _writeSeriesMapping;
  final JellyfinEpisodeMappingWriter _writeEpisodeMapping;
  final DateTime Function() _clock;

  final Map<String, Future<JellyfinSeriesAutoMatchResult?>> _inFlight = {};
  final Map<String, DateTime> _lastFailedAt = {};
  int _activeMatches = 0;
  final List<Completer<void>> _waiters = [];

  Future<void> matchSeriesBatchIfEnabled(
    Iterable<JellyfinMediaItem> seriesItems,
  ) async {
    await Future.wait(seriesItems.map(matchSeriesIfEnabled), eagerError: false);
  }

  Future<JellyfinSeriesAutoMatchResult?> matchSeriesIfEnabled(
    JellyfinMediaItem series,
  ) async {
    try {
      return await _matchSeriesIfEnabled(series);
    } catch (error) {
      debugPrint('[JellyfinAutoMatch] ${series.name} setup failed: $error');
      return null;
    }
  }

  Future<JellyfinSeriesAutoMatchResult?> _matchSeriesIfEnabled(
    JellyfinMediaItem series,
  ) async {
    if (kIsWeb || series.type?.toLowerCase() != 'series') return null;
    if (!await _isEnabled()) return null;

    final existing = await _loadMapping(series.id);
    final existingAnimeId = _positiveInt(existing?['dandanplay_anime_id']);
    if (existingAnimeId != null) {
      return JellyfinSeriesAutoMatchResult(
        animeId: existingAnimeId,
        animeTitle:
            existing?['dandanplay_anime_title']?.toString() ?? series.name,
        episodeId: null,
      );
    }

    final lastFailure = _lastFailedAt[series.id];
    if (lastFailure != null &&
        _clock().difference(lastFailure) < _failureCooldown) {
      return null;
    }

    final running = _inFlight[series.id];
    if (running != null) return running;

    final task = _withPermit(() => _matchSeries(series));
    _inFlight[series.id] = task;
    try {
      final result = await task;
      if (result == null) {
        _lastFailedAt[series.id] = _clock();
      } else {
        _lastFailedAt.remove(series.id);
      }
      return result;
    } finally {
      _inFlight.remove(series.id);
    }
  }

  Future<JellyfinSeriesAutoMatchResult?> _matchSeries(
    JellyfinMediaItem series,
  ) async {
    try {
      final episode = await _loadRepresentativeEpisode(series.id);
      if (episode == null) return null;

      final videoInfo = await _loadVideoInfo(episode);
      if (!_hasUsableVideoInfo(videoInfo)) return null;

      final matchResult = await _matchExactly(videoInfo);
      final match = _firstMatch(matchResult);
      final animeId = _positiveInt(match?['animeId']);
      final episodeId = _positiveInt(match?['episodeId']);
      if (animeId == null || episodeId == null) return null;

      final animeTitle = match?['animeTitle']?.toString().trim();
      final resolvedTitle =
          animeTitle?.isNotEmpty == true ? animeTitle! : series.name;
      final mappingId = await _writeSeriesMapping(
        series,
        animeId,
        resolvedTitle,
      );
      if (mappingId <= 0) return null;

      await _writeEpisodeMapping(episode, episodeId, mappingId);
      debugPrint(
        '[JellyfinAutoMatch] ${series.name} -> $resolvedTitle ($animeId)',
      );
      return JellyfinSeriesAutoMatchResult(
        animeId: animeId,
        animeTitle: resolvedTitle,
        episodeId: episodeId,
      );
    } catch (error) {
      debugPrint('[JellyfinAutoMatch] ${series.name} failed: $error');
      return null;
    }
  }

  Future<JellyfinEpisodeInfo?> _loadRepresentativeEpisode(
    String seriesId,
  ) async {
    final seasons = await _loadSeasons(seriesId);
    for (final season in seasons) {
      final episodes = await _loadEpisodes(seriesId, season.id);
      for (final episode in episodes) {
        final index = episode.indexNumber;
        if (index != null && index > 0) return episode;
      }
    }
    return null;
  }

  Future<T> _withPermit<T>(Future<T> Function() action) async {
    if (_activeMatches >= _maxConcurrentMatches) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _activeMatches++;
    try {
      return await action();
    } finally {
      _activeMatches--;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }

  static bool _hasUsableVideoInfo(Map<String, dynamic> videoInfo) {
    final hash = videoInfo['hash']?.toString().trim() ?? '';
    final fileName = videoInfo['fileName']?.toString().trim() ?? '';
    final fileSize = _positiveInt(videoInfo['fileSize']);
    return hash.isNotEmpty && fileName.isNotEmpty && fileSize != null;
  }

  static Map<String, dynamic>? _firstMatch(Map<String, dynamic> matchResult) {
    if (matchResult['isMatched'] != true) return null;
    final matches = matchResult['matches'];
    if (matches is! List || matches.isEmpty || matches.first is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(matches.first as Map);
  }

  static int? _positiveInt(dynamic value) {
    final parsed = switch (value) {
      int value => value,
      double value => value.toInt(),
      String value => int.tryParse(value),
      _ => null,
    };
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static Future<bool> _defaultIsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(SettingsKeys.autoMatchJellyfinSeries) ?? false;
  }

  static Future<Map<String, dynamic>?> _defaultLoadMapping(String seriesId) {
    return JellyfinEpisodeMappingService.instance.getAnimeMapping(
      jellyfinSeriesId: seriesId,
    );
  }

  static Future<int> _defaultWriteSeriesMapping(
    JellyfinMediaItem series,
    int animeId,
    String animeTitle,
  ) {
    return JellyfinEpisodeMappingService.instance.createOrUpdateAnimeMapping(
      jellyfinSeriesId: series.id,
      jellyfinSeriesName: series.name,
      dandanplayAnimeId: animeId,
      dandanplayAnimeTitle: animeTitle,
    );
  }

  static Future<void> _defaultWriteEpisodeMapping(
    JellyfinEpisodeInfo episode,
    int episodeId,
    int mappingId,
  ) {
    return JellyfinEpisodeMappingService.instance.recordEpisodeMapping(
      jellyfinEpisodeId: episode.id,
      jellyfinIndexNumber: episode.indexNumber!,
      dandanplayEpisodeId: episodeId,
      mappingId: mappingId,
      confirmed: true,
    );
  }
}
