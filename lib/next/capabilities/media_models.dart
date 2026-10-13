import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/bangumi_model.dart';

({String title, String? originalTitle, String? imageUrl}) resolveSeriesTitles(
  BangumiAnime? detail,
  String animeName,
) {
  final title = switch (detail) {
    BangumiAnime(nameCn: final nameCn) when nameCn.isNotEmpty => nameCn,
    BangumiAnime(name: final name) when name.isNotEmpty => name,
    _ => animeName,
  };
  return (
    title: title,
    originalTitle: detail?.name == title ? null : detail?.name,
    imageUrl: switch (detail) {
      BangumiAnime(imageUrl: final url) when url.isNotEmpty => url,
      _ => null,
    },
  );
}

const seriesSummarySchema = ObjectSchema({
  'animeId': IntegerSchema(description: 'Dandanplay anime ID.'),
  'title': StringSchema(description: 'Resolved series display title.'),
  'originalTitle': StringSchema(
      nullable: true, description: 'Original-language series title, if known.'),
  'imageUrl':
      StringSchema(nullable: true, description: 'Recorded series image URL.'),
  'episodeCount': IntegerSchema(
      description:
          'Number of recorded library episodes, including unidentified files.'),
  'fileCount':
      IntegerSchema(description: 'Number of recorded files in this series.'),
  'lastWatchedAt':
      StringSchema(description: 'Latest UTC ISO-8601 watch timestamp.'),
}, required: [
  'animeId',
  'title',
  'originalTitle',
  'imageUrl',
  'episodeCount',
  'fileCount',
  'lastWatchedAt',
]);

final classicSeriesStateSchema = ObjectSchema({
  ...seriesSummarySchema.properties,
  'searchText': const StringSchema(
      description:
          'Concatenated resolved titles and recorded names for case-insensitive substring search.'),
});

final class SeriesSummary implements JsonEncodable {
  const SeriesSummary({
    required this.animeId,
    required this.title,
    required this.originalTitle,
    required this.imageUrl,
    required this.episodeCount,
    required this.fileCount,
    required this.lastWatchedAt,
  });

  final int animeId;
  final String title;
  final String? originalTitle;
  final String? imageUrl;
  final int episodeCount;
  final int fileCount;
  final DateTime lastWatchedAt;

  @override
  JsonMap toJson() => {
        'animeId': animeId,
        'title': title,
        'originalTitle': originalTitle,
        'imageUrl': imageUrl,
        'episodeCount': episodeCount,
        'fileCount': fileCount,
        'lastWatchedAt': lastWatchedAt.toUtc().toIso8601String(),
      };
}

const episodeFileSchema = ObjectSchema({
  'path': StringSchema(description: 'Recorded media location.'),
  'source': StringSchema(
      values: ['local', 'webdav', 'smb'],
      description: 'Classic library location source.'),
  'progress': NumberSchema(
      minimum: 0, maximum: 1, description: 'Watched fraction from 0 to 1.'),
  'positionMs':
      IntegerSchema(description: 'Saved playback position in milliseconds.'),
  'durationMs': IntegerSchema(
      description: 'Recorded duration in milliseconds; zero means unknown.'),
  'lastWatchedAt':
      StringSchema(description: 'UTC ISO-8601 last watch timestamp.'),
}, required: [
  'path',
  'source',
  'progress',
  'positionMs',
  'durationMs',
  'lastWatchedAt',
]);

final class EpisodeFile implements JsonEncodable {
  const EpisodeFile({
    required this.path,
    required this.source,
    required this.progress,
    required this.positionMs,
    required this.durationMs,
    required this.lastWatchedAt,
  });

  final String path;
  final String source;
  final double progress;
  final int positionMs;
  final int durationMs;
  final DateTime lastWatchedAt;

  @override
  JsonMap toJson() => {
        'path': path,
        'source': source,
        'progress': progress,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'lastWatchedAt': lastWatchedAt.toUtc().toIso8601String(),
      };
}

const episodeEntrySchema = ObjectSchema({
  'episodeId': IntegerSchema(
      nullable: true,
      description: 'Dandanplay episode ID; null for unidentified episodes.'),
  'title':
      StringSchema(description: 'Recorded episode title or file basename.'),
  'files': ArraySchema(episodeFileSchema,
      description: 'Recorded files for this episode, latest watch time first.'),
}, required: [
  'episodeId',
  'title',
  'files'
]);

final class EpisodeEntry implements JsonEncodable {
  const EpisodeEntry({
    required this.episodeId,
    required this.title,
    required this.files,
  });

  final int? episodeId;
  final String title;
  final List<EpisodeFile> files;

  @override
  JsonMap toJson() => {
        'episodeId': episodeId,
        'title': title,
        'files': [for (final file in files) file.toJson()],
      };
}

const continueItemSchema = ObjectSchema({
  'path': StringSchema(),
  'animeId': IntegerSchema(nullable: true),
  'seriesTitle': StringSchema(),
  'episodeId': IntegerSchema(nullable: true),
  'episodeTitle': StringSchema(nullable: true),
  'progress': NumberSchema(minimum: 0, maximum: 1),
  'positionMs': IntegerSchema(),
  'durationMs': IntegerSchema(),
  'lastWatchedAt': StringSchema(),
}, required: [
  'path',
  'animeId',
  'seriesTitle',
  'episodeId',
  'episodeTitle',
  'progress',
  'positionMs',
  'durationMs',
  'lastWatchedAt',
]);

final class ContinueItem implements JsonEncodable {
  const ContinueItem({
    required this.path,
    required this.animeId,
    required this.seriesTitle,
    required this.episodeId,
    required this.episodeTitle,
    required this.progress,
    required this.positionMs,
    required this.durationMs,
    required this.lastWatchedAt,
  });

  final String path;
  final int? animeId;
  final String seriesTitle;
  final int? episodeId;
  final String? episodeTitle;
  final double progress;
  final int positionMs;
  final int durationMs;
  final DateTime lastWatchedAt;

  @override
  JsonMap toJson() => {
        'path': path,
        'animeId': animeId,
        'seriesTitle': seriesTitle,
        'episodeId': episodeId,
        'episodeTitle': episodeTitle,
        'progress': progress,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'lastWatchedAt': lastWatchedAt.toUtc().toIso8601String(),
      };
}

const playbackSnapshotSchema = ObjectSchema({
  'player': StringSchema(values: ['internal', 'external']),
  'external': ObjectSchema({}, additionalProperties: true),
  'status': StringSchema(),
  'observedState': StringSchema(),
  'hasVideo': BooleanSchema(),
  'paused': BooleanSchema(nullable: true),
  'path': StringSchema(nullable: true),
  'seriesTitle': StringSchema(nullable: true),
  'episodeTitle': StringSchema(nullable: true),
  'animeId': IntegerSchema(nullable: true),
  'episodeId': IntegerSchema(nullable: true),
  'positionMs': IntegerSchema(nullable: true),
  'durationMs': IntegerSchema(nullable: true),
  'rate': NumberSchema(nullable: true),
  'sessionId': StringSchema(nullable: true),
  'ready': BooleanSchema(nullable: true),
  'buffering': BooleanSchema(nullable: true),
  'bufferedPositionMs': IntegerSchema(nullable: true),
  'error': ObjectSchema({}, nullable: true, additionalProperties: true),
  'observedAt': StringSchema(nullable: true),
  'supportedControls': ArraySchema(StringSchema()),
  'volume': NumberSchema(minimum: 0, maximum: 1, nullable: true),
  'brightness': NumberSchema(minimum: 0, maximum: 1, nullable: true),
  'canPrevious': BooleanSchema(),
  'canNext': BooleanSchema(),
}, required: [
  'status',
  'hasVideo',
  'paused',
  'path',
  'seriesTitle',
  'episodeTitle',
  'animeId',
  'episodeId',
  'positionMs',
  'durationMs',
  'rate',
  'canPrevious',
  'canNext',
]);

final class PlaybackSnapshot implements JsonEncodable {
  const PlaybackSnapshot({
    required this.status,
    required this.hasVideo,
    required this.paused,
    required this.path,
    required this.seriesTitle,
    required this.episodeTitle,
    required this.animeId,
    required this.episodeId,
    required this.positionMs,
    required this.durationMs,
    required this.rate,
    required this.canPrevious,
    required this.canNext,
    this.external,
    this.player,
    this.volume,
    this.brightness,
    this.sessionId,
    this.ready,
    this.buffering,
    this.bufferedPositionMs,
    this.error,
    this.supportedControls = const [],
    this.observedAt,
  });

  final String status;
  final bool hasVideo;
  final bool? paused;
  final String? path;
  final String? seriesTitle;
  final String? episodeTitle;
  final int? animeId;
  final int? episodeId;
  final int? positionMs;
  final int? durationMs;
  final double? rate;
  final String? sessionId;
  final bool? ready;
  final bool? buffering;
  final int? bufferedPositionMs;
  final JsonMap? error;
  final List<String> supportedControls;
  final DateTime? observedAt;
  final bool canPrevious;
  final bool canNext;
  final JsonMap? external;
  final String? player;
  final double? volume;
  final double? brightness;

  @override
  JsonMap toJson() => {
        if (external != null) 'external': external,
        if (player != null) 'player': player,
        if (player != null) 'volume': volume,
        if (player != null) 'brightness': brightness,
        'status': status,
        'observedState': error != null ? 'error' : buffering == true ? 'buffering'
            : ready == false && hasVideo ? 'loading' : status,
        'sessionId': sessionId,
        'ready': ready,
        'buffering': buffering,
        'bufferedPositionMs': bufferedPositionMs,
        'error': error,
        'observedAt': observedAt?.toUtc().toIso8601String(),
        'supportedControls': supportedControls,
        'hasVideo': hasVideo,
        'paused': paused,
        'path': path,
        'seriesTitle': seriesTitle,
        'episodeTitle': episodeTitle,
        'animeId': animeId,
        'episodeId': episodeId,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'rate': rate,
        'canPrevious': canPrevious,
        'canNext': canNext,
      };
}

const librarySearchInputSchema = ObjectSchema({
  'query': StringSchema(
    minLength: 1,
    description: 'Case-insensitive substring of a series title. '
        'Omit to list the whole library.',
  ),
  'limit': IntegerSchema(
    minimum: 1,
    maximum: 200,
    description: 'Maximum number of series to return. Defaults to 50.',
  ),
});

final class LibrarySearchInput implements JsonEncodable {
  const LibrarySearchInput({this.query, this.limit = 50});

  final String? query;
  final int limit;

  @override
  JsonMap toJson() => {if (query != null) 'query': query, 'limit': limit};
}

const librarySearchOutputSchema = ObjectSchema({
  'series': ArraySchema(seriesSummarySchema),
  'total': IntegerSchema(),
}, required: [
  'series',
  'total'
]);

final class LibrarySearchOutput implements JsonEncodable {
  const LibrarySearchOutput({required this.series, required this.total});

  final List<SeriesSummary> series;
  final int total;

  @override
  JsonMap toJson() => {
        'series': [for (final item in series) item.toJson()],
        'total': total,
      };
}

const librarySeriesInputSchema = ObjectSchema({
  'animeId': IntegerSchema(
    description: 'Dandanplay anime ID identifying a recorded series.',
  ),
}, required: [
  'animeId'
]);

final class LibrarySeriesInput implements JsonEncodable {
  const LibrarySeriesInput({required this.animeId});

  final int animeId;

  @override
  JsonMap toJson() => {'animeId': animeId};
}

const librarySeriesOutputSchema = ObjectSchema({
  'series': seriesSummarySchema,
  'episodes': ArraySchema(episodeEntrySchema),
}, required: [
  'series',
  'episodes'
]);

final class LibrarySeriesOutput implements JsonEncodable {
  const LibrarySeriesOutput({required this.series, required this.episodes});

  final SeriesSummary series;
  final List<EpisodeEntry> episodes;

  @override
  JsonMap toJson() => {
        'series': series.toJson(),
        'episodes': [for (final episode in episodes) episode.toJson()],
      };
}

const continueWatchingInputSchema = ObjectSchema({
  'limit': IntegerSchema(
    minimum: 1,
    maximum: 100,
    description: 'Maximum number of items to return. Defaults to 20.',
  ),
});

final class ContinueWatchingInput implements JsonEncodable {
  const ContinueWatchingInput({this.limit = 20});

  final int limit;

  @override
  JsonMap toJson() => {'limit': limit};
}

const continueWatchingOutputSchema = ObjectSchema({
  'items': ArraySchema(continueItemSchema),
}, required: [
  'items'
]);

final class ContinueWatchingOutput implements JsonEncodable {
  const ContinueWatchingOutput({required this.items});

  final List<ContinueItem> items;

  @override
  JsonMap toJson() => {
        'items': [for (final item in items) item.toJson()]
      };
}

const playbackOpenInputSchema = ObjectSchema({
  'path': StringSchema(
    minLength: 1,
    description: 'Absolute local file path, URL, jellyfin://itemId or emby://itemId. '
        'Watch history is optional. Mutually exclusive '
        'with animeId and episodeId.',
  ),
  'animeId': IntegerSchema(
    description:
        'Dandanplay anime ID. Required together with episodeId; mutually exclusive with path.',
  ),
  'episodeId': IntegerSchema(
    description:
        'Dandanplay episode ID. Required together with animeId; mutually exclusive with path.',
  ),
  'startPositionMs': IntegerSchema(
    minimum: 0,
    description: 'Start position in milliseconds; 0 plays from the '
        'beginning. Omit to resume from the saved position.',
  ),
}, oneOfRequired: [
  ['path'],
  ['animeId', 'episodeId']
]);

final class PlaybackOpenInput implements JsonEncodable {
  const PlaybackOpenInput({
    this.path,
    this.animeId,
    this.episodeId,
    this.startPositionMs,
  });

  final String? path;
  final int? animeId;
  final int? episodeId;
  final int? startPositionMs;

  @override
  JsonMap toJson() => {
        if (path != null) 'path': path,
        if (animeId != null) 'animeId': animeId,
        if (episodeId != null) 'episodeId': episodeId,
        if (startPositionMs != null) 'startPositionMs': startPositionMs,
      };
}

const playbackOpenOutputSchema = ObjectSchema({
  'path': StringSchema(),
  'player': StringSchema(values: ['internal', 'external']),
  'state': playbackSnapshotSchema,
  'commandStatus': StringSchema(values: ['accepted']),
}, required: [
  'path',
  'player',
  'state'
]);

final class PlaybackOpenOutput implements JsonEncodable {
  const PlaybackOpenOutput({
    required this.path,
    required this.player,
    required this.state,
  });

  final String path;
  final String player;
  final PlaybackSnapshot state;

  @override
  JsonMap toJson() => {'path': path, 'player': player, 'state': state.toJson(), 'commandStatus': 'accepted'};
}

const playbackStateOutputSchema = ObjectSchema({
  'state': playbackSnapshotSchema,
}, required: [
  'state'
]);

final class PlaybackStateOutput implements JsonEncodable {
  const PlaybackStateOutput({required this.state});

  final PlaybackSnapshot state;

  @override
  JsonMap toJson() => {'state': state.toJson()};
}

const playbackSetPausedInputSchema = ObjectSchema({
  'paused': BooleanSchema(
    description: 'true pauses the current video; false resumes it.',
  ),
}, required: [
  'paused'
]);

final class PlaybackSetPausedInput implements JsonEncodable {
  const PlaybackSetPausedInput({required this.paused});

  final bool paused;

  @override
  JsonMap toJson() => {'paused': paused};
}

const playbackSeekInputSchema = ObjectSchema({
  'positionMs': IntegerSchema(
    minimum: 0,
    description: 'Absolute target position in milliseconds.',
  ),
  'offsetMs': IntegerSchema(
    description: 'Relative move in milliseconds; negative values rewind.',
  ),
}, oneOfRequired: [
  ['positionMs'],
  ['offsetMs']
]);

final class PlaybackSeekInput implements JsonEncodable {
  const PlaybackSeekInput({this.positionMs, this.offsetMs});

  final int? positionMs;
  final int? offsetMs;

  @override
  JsonMap toJson() => {
        if (positionMs != null) 'positionMs': positionMs,
        if (offsetMs != null) 'offsetMs': offsetMs,
      };
}

const playbackSwitchEpisodeInputSchema = ObjectSchema({
  'direction': StringSchema(
    values: ['next', 'previous'],
    description: 'Which neighbouring episode to play.',
  ),
}, required: [
  'direction'
]);

final class PlaybackSwitchEpisodeInput implements JsonEncodable {
  const PlaybackSwitchEpisodeInput({required this.direction});

  final String direction;

  @override
  JsonMap toJson() => {'direction': direction};
}
