import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:path/path.dart' as p;

import 'media_models.dart';

final class HistoryCapability implements Capability {
  HistoryCapability({
    required List<WatchHistoryItem> Function() continueWatching,
    required BangumiAnime? Function(int animeId) seriesDetail,
  }) : actions = [ContinueWatchingAction._(continueWatching, seriesDetail)];

  @override
  final List<Action> actions;
}

final class ContinueWatchingAction
    extends Action<ContinueWatchingInput, ContinueWatchingOutput> {
  const ContinueWatchingAction._(this._continueWatching, this._seriesDetail);

  final List<WatchHistoryItem> Function() _continueWatching;
  final BangumiAnime? Function(int animeId) _seriesDetail;

  static const _spec = ActionSpec(
    id: 'history.continue_watching',
    title: 'Get continue watching',
    description: 'List files available to continue watching in the order '
        'provided by watch history. Each item includes series and episode '
        'titles, progress, playback position and last watch time. '
        'Returns up to 20 items unless a limit is specified.',
    effect: Effect.read,
    input: continueWatchingInputSchema,
    output: continueWatchingOutputSchema,
  );

  @override
  ActionSpec get spec => _spec;

  @override
  ContinueWatchingInput decodeInput(JsonMap json) =>
      ContinueWatchingInput(limit: (json['limit'] as num?)?.toInt() ?? 20);

  @override
  Future<Outcome<ContinueWatchingOutput>> run(
    ContinueWatchingInput input,
    Invocation invocation,
  ) async =>
      Completed(ContinueWatchingOutput(items: [
        for (final item in _continueWatching().take(input.limit))
          ContinueItem(
            path: item.filePath,
            animeId: item.animeId,
            seriesTitle: item.animeId != null
                ? resolveSeriesTitles(
                        _seriesDetail(item.animeId!), item.animeName)
                    .title
                : item.animeName.isNotEmpty
                    ? item.animeName
                    : p.basename(item.filePath),
            episodeId: item.episodeId,
            episodeTitle: item.episodeTitle,
            progress: item.watchProgress,
            positionMs: item.lastPosition,
            durationMs: item.duration,
            lastWatchedAt: item.lastWatchTime,
          ),
      ]));
}
