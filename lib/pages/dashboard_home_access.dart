part of 'dashboard_home_page.dart';

/// Access to the same content and operations used by all Classic home layouts.
abstract interface class DashboardHomeAccess {
  Map<String, dynamic> get homeSnapshot;
  Future<Map<String, dynamic>> refreshHome();
  Future<Map<String, dynamic>> recommendations({bool next = false});
  Future<void> setReviewSort(String sort);
  void openHomeDialog(String dialog);
  bool openSourceDetail(String provider, int animeId);
  bool openQuarterlyComment(int animeId);
}

extension _DashboardHomeAccess on _DashboardHomePageState {
  Map<String, dynamic> _snapshot() => {
        'loading': _isLoadingRecommended ||
            _isLoadingRecentContent ||
            _isLoadingTodayAnimes ||
            _isLoadingRandomRecommendations ||
            _trendingLoadingKeys.isNotEmpty ||
            _isContinueWatchingRefreshInProgress,
        'today': _todayAnimes.map((a) => a.toJson()).toList(),
        'hero': [
          for (final item in _recommendedItems)
            {
              'id': item.id,
              'title': item.title,
              'subtitle': item.subtitle,
              'source': item.source.name,
              'rating': item.rating,
              'backgroundImageUrl': item.backgroundImageUrl,
            }
        ],
        'recent': {
          'jellyfin': {
            for (final e in _recentJellyfinItemsByLibrary.entries)
              e.key: [
                for (final i in e.value)
                  {'id': i.id, 'name': i.name, 'type': i.type}
              ]
          },
          'emby': {
            for (final e in _recentEmbyItemsByLibrary.entries)
              e.key: [
                for (final i in e.value)
                  {'id': i.id, 'name': i.name, 'type': i.type}
              ]
          },
          'local': [
            for (final i in _localAnimeItems)
              {
                'animeId': i.animeId,
                'title': i.animeName,
                'addedTime': i.addedTime.toIso8601String(),
                'latestEpisode': i.latestEpisode.toJson(),
              }
          ],
          'dandanplay': [
            for (final i in _recentDandanplayGroups)
              {
                'animeId': i.animeId,
                'title': i.title,
              }
          ],
        },
        'recommendationGroupIndex': _randomRecommendationGroupIndex,
        'recommendationDate': _randomRecommendationDate,
        'recommendationGeneratedAt':
            _randomRecommendationGeneratedAt?.toIso8601String(),
        'recommendations':
            _randomRecommendations.map((i) => i.toJson()).toList(),
        'recommendationGroups':
            _randomRecommendationGroups.map((g) => g.toJson()).toList(),
        'trending': _currentTrendingResult?.toJson(),
        'trendingError': _trendingError,
        'reviewSort': _quarterlyReviewSort.name,
        'review': [
          for (final i in _sortedQuarterlyReviewItems)
            {
              'anime': i.anime.toJson(),
              'airDate': i.airDate.toIso8601String(),
              'dateLabel': i.dateLabel,
              'rating': i.rating,
              'comment': i.comment,
              'commentAt': i.commentAt,
            }
        ],
        'continueWatching':
            Provider.of<WatchHistoryProvider>(context, listen: false)
                .continueWatchingItems
                .map((i) => i.toJson())
                .toList(),
      };
}
