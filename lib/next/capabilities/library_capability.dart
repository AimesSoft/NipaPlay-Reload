import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:path/path.dart' as p;

import 'media_models.dart';
import '../state/query.dart';

List<StateView> classicLibraryStateViews({
  required Iterable<WatchHistoryItem> Function() history,
  required BangumiAnime? Function(int animeId) seriesDetail,
}) =>
    [
      StateView(
          name: 'library.classic_series',
          description:
              'Classic identified series, using Dandanplay anime IDs. Same recorded-library scope as media.library.search; latest watch time first.',
          fields: classicSeriesStateSchema,
          relations: {
            'episodes': const StateRelation(
                'library.classic_episodes', 'animeId', 'animeId')
          },
          read: (offset, limit) async {
            final groups = _libraryGroups(history());
            final summaries = [
              for (final files in groups.values)
                _summary(files, seriesDetail(files.first.animeId!))
            ]..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
            return [
              for (final row in summaries.skip(offset).take(limit))
                {
                  ...row.toJson(),
                  'searchText': [
                    row.title,
                    row.originalTitle ?? '',
                    for (final item in groups[row.animeId]!) item.animeName
                  ].join('\n')
                }
            ];
          }),
      StateView(
          name: 'library.classic_episodes',
          description:
              'Classic recorded episodes and files, including unidentified episodes. Dandanplay IDs retain their Classic meaning; progress comes from current history memory.',
          fields: ObjectSchema({
            'animeId':
                const IntegerSchema(description: 'Dandanplay series ID.'),
            ...episodeEntrySchema.properties
          }),
          read: (offset, limit) async {
            final rows = <JsonMap>[];
            for (final group in _libraryGroups(history()).entries) {
              final episodes = <Object, List<WatchHistoryItem>>{};
              for (final item in group.value) {
                episodes
                    .putIfAbsent(item.episodeId ?? item, () => [])
                    .add(item);
              }
              for (final files in episodes.values) {
                final row = {
                  'animeId': group.key,
                  ..._episodeEntry(files).toJson()
                };
                if (files.first.episodeTitle == null ||
                    files.first.episodeTitle!.isEmpty) {
                  final location = Uri.parse(files.first.filePath);
                  row['title'] = p.basename(location.hasScheme
                      ? location.path
                      : files.first.filePath);
                }
                rows.add(row);
              }
            }
            rows.sort((a, b) {
              final series =
                  (a['animeId'] as int).compareTo(b['animeId'] as int);
              if (series != 0) return series;
              final aId = a['episodeId'] as int?, bId = b['episodeId'] as int?;
              return aId == null
                  ? bId == null
                      ? (a['title'] as String).compareTo(b['title'] as String)
                      : 1
                  : bId == null
                      ? -1
                      : aId.compareTo(bId);
            });
            return rows.skip(offset).take(limit).toList();
          }),
    ];

final class LibraryCapability implements Capability {
  LibraryCapability({
    required Iterable<WatchHistoryItem> Function() history,
    required BangumiAnime? Function(int animeId) seriesDetail,
  }) : actions = [
          LibrarySearchAction._(history, seriesDetail),
          LibrarySeriesAction._(history, seriesDetail),
        ];

  @override
  final List<Action> actions;
}

final class LibrarySearchAction
    extends Action<LibrarySearchInput, LibrarySearchOutput> {
  const LibrarySearchAction._(this._history, this._seriesDetail);

  final Iterable<WatchHistoryItem> Function() _history;
  final BangumiAnime? Function(int animeId) _seriesDetail;

  static const _spec = ActionSpec(
    id: 'media.library.search',
    title: 'Search the media library',
    description: 'Find identified series in the local, WebDAV and SMB library. '
        'The optional query matches titles and recorded names without regard '
        'to case. Results are ordered by last watch time; total counts all '
        'matches before the limit is applied.',
    effect: Effect.read,
    input: librarySearchInputSchema,
    output: librarySearchOutputSchema,
  );

  @override
  ActionSpec get spec => _spec;

  @override
  LibrarySearchInput decodeInput(JsonMap json) => LibrarySearchInput(
        query: json['query'] as String?,
        limit: (json['limit'] as num?)?.toInt() ?? 50,
      );

  @override
  Future<Outcome<LibrarySearchOutput>> run(
    LibrarySearchInput input,
    Invocation invocation,
  ) async {
    final query = input.query?.toLowerCase();
    final series = <SeriesSummary>[];
    for (final files in _libraryGroups(_history()).values) {
      final summary = _summary(files, _seriesDetail(files.first.animeId!));
      if (query == null ||
          summary.title.toLowerCase().contains(query) ||
          (summary.originalTitle?.toLowerCase().contains(query) ?? false) ||
          files.any((file) => file.animeName.toLowerCase().contains(query))) {
        series.add(summary);
      }
    }
    series.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    return Completed(LibrarySearchOutput(
      series: series.take(input.limit).toList(),
      total: series.length,
    ));
  }
}

final class LibrarySeriesAction
    extends Action<LibrarySeriesInput, LibrarySeriesOutput> {
  const LibrarySeriesAction._(this._history, this._seriesDetail);

  final Iterable<WatchHistoryItem> Function() _history;
  final BangumiAnime? Function(int animeId) _seriesDetail;

  static const _spec = ActionSpec(
    id: 'media.library.series',
    title: 'Get a library series',
    description: 'Get a series summary and all its library episodes and files. '
        'Episodes are ordered by ID, with unidentified episodes last; files '
        'are ordered by last watch time and include playback progress. '
        'Returns not_found when the series is absent from the library.',
    effect: Effect.read,
    input: librarySeriesInputSchema,
    output: librarySeriesOutputSchema,
  );

  @override
  ActionSpec get spec => _spec;

  @override
  LibrarySeriesInput decodeInput(JsonMap json) =>
      LibrarySeriesInput(animeId: (json['animeId'] as num).toInt());

  @override
  Future<Outcome<LibrarySeriesOutput>> run(
    LibrarySeriesInput input,
    Invocation invocation,
  ) async {
    final files = _libraryGroups(_history())[input.animeId];
    if (files == null) {
      throw Failure(FailureCode.notFound,
          'Series ${input.animeId} was not found in the media library.');
    }
    final byEpisode = <Object, List<WatchHistoryItem>>{};
    for (final file in files) {
      byEpisode.putIfAbsent(file.episodeId ?? file, () => []).add(file);
    }
    final episodes = [
      for (final episodeFiles in byEpisode.values) _episodeEntry(episodeFiles),
    ]..sort((a, b) => switch ((a.episodeId, b.episodeId)) {
          (null, null) => a.title.compareTo(b.title),
          (null, _) => 1,
          (_, null) => -1,
          (final int aId, final int bId) => aId.compareTo(bId),
        });
    return Completed(LibrarySeriesOutput(
      series: _summary(files, _seriesDetail(input.animeId)),
      episodes: episodes,
    ));
  }
}

Map<int, List<WatchHistoryItem>> _libraryGroups(
  Iterable<WatchHistoryItem> history,
) {
  final groups = <int, List<WatchHistoryItem>>{};
  for (final item in history) {
    if (UnifiedMediaLibrarySource.values
        .any((source) => mediaLibraryItemMatchesSource(item, source))) {
      groups.putIfAbsent(item.animeId!, () => []).add(item);
    }
  }
  for (final files in groups.values) {
    files.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
  }
  return groups;
}

SeriesSummary _summary(List<WatchHistoryItem> files, BangumiAnime? detail) {
  final latest = files.first;
  final titles = resolveSeriesTitles(detail, latest.animeName);
  return SeriesSummary(
    animeId: latest.animeId!,
    title: titles.title,
    originalTitle: titles.originalTitle,
    imageUrl: titles.imageUrl,
    episodeCount:
        files.map((file) => file.episodeId).whereType<int>().toSet().length +
            files.where((file) => file.episodeId == null).length,
    fileCount: files.length,
    lastWatchedAt: latest.lastWatchTime,
  );
}

EpisodeEntry _episodeEntry(List<WatchHistoryItem> files) {
  final latest = files.first;
  return EpisodeEntry(
    episodeId: latest.episodeId,
    title: switch (latest.episodeTitle) {
      final String title when title.isNotEmpty => title,
      _ => p.basename(latest.filePath),
    },
    files: [
      for (final file in files)
        EpisodeFile(
          path: file.filePath,
          source: UnifiedMediaLibrarySource.values
              .firstWhere(
                (source) => mediaLibraryItemMatchesSource(file, source),
              )
              .name,
          progress: file.watchProgress,
          positionMs: file.lastPosition,
          durationMs: file.duration,
          lastWatchedAt: file.lastWatchTime,
        ),
    ],
  );
}
