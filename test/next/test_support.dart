import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/next/capabilities/media_models.dart';
import 'package:nipaplay/next/capabilities/playback_capability.dart';
import 'package:nipaplay/services/episode_file_selection_service.dart';

WatchHistoryItem watchItem(
  String path, {
  int? animeId = 10,
  int? episodeId = 100,
  String animeName = 'Recorded title',
  String? episodeTitle = 'Episode one',
  double progress = 0.5,
  int positionMs = 500,
  int durationMs = 1000,
  String watchedAt = '2026-10-10T12:00:00+08:00',
  String? mediaKey = 'stored-key',
}) =>
    WatchHistoryItem(
      filePath: path,
      animeName: animeName,
      animeId: animeId,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
      watchProgress: progress,
      lastPosition: positionMs,
      duration: durationMs,
      lastWatchTime: DateTime.parse(watchedAt),
      mediaKey: mediaKey,
    );

BangumiAnime seriesDetail({
  int id = 10,
  String name = 'Original title',
  String nameCn = 'Localized title',
  String imageUrl = 'https://example.test/cover.jpg',
}) =>
    BangumiAnime(id: id, name: name, nameCn: nameCn, imageUrl: imageUrl);

Future<Outcome<JsonEncodable>> invoke(
  Harness harness,
  String id,
  JsonMap input,
) =>
    harness.invokeJson(
      id,
      jsonDecode(jsonEncode(input)),
      Invocation(origin: 'test'),
    );

Future<JsonMap> invokeCompleted(
  Harness harness,
  String id,
  JsonMap input,
) async {
  final outcome = await invoke(harness, id, input);
  expect(outcome, isA<Completed<JsonEncodable>>());
  final result = (outcome as Completed<JsonEncodable>).value.toJson();
  expect(harness.lookup(id)!.spec.output.validate(result), isEmpty);
  expect(outcome.toEnvelope(), {'status': 'completed', 'result': result});
  return result;
}

Future<Failure> invokeFailed(
  Harness harness,
  String id,
  JsonMap input,
  FailureCode code,
) async {
  final outcome = await invoke(harness, id, input);
  expect(outcome, isA<Failed<JsonEncodable>>());
  final failure = (outcome as Failed<JsonEncodable>).failure;
  expect(failure.code, code);
  expect(outcome.toEnvelope(), {'status': 'failed', 'error': failure.toJson()});
  return failure;
}

final class TestPlayer implements PlayerPort {
  bool hasVideo = true;
  bool paused = false;
  String? path = '/media/episode.mkv';
  String? seriesTitle = 'Recorded title';
  String? episodeTitle = 'Episode one';
  int? animeId = 10;
  int? episodeId = 100;
  int positionMs = 500;
  int durationMs = 1000;
  double rate = 1.25;
  bool canPrevious = true;
  bool canNext = true;
  JsonMap? error;
  final List<bool> pauseCalls = [];
  final List<Duration> seeks = [];
  final List<EpisodeDirection> switches = [];

  @override
  PlaybackSnapshot snapshot() => PlaybackSnapshot(
        status: !hasVideo
            ? 'idle'
            : paused
                ? 'paused'
                : 'playing',
        hasVideo: hasVideo,
        paused: paused,
        path: path,
        seriesTitle: seriesTitle,
        episodeTitle: episodeTitle,
        animeId: animeId,
        episodeId: episodeId,
        positionMs: positionMs,
        durationMs: durationMs,
        rate: rate,
        canPrevious: canPrevious,
        canNext: canNext,
        error: error,
      );

  @override
  void setPaused(bool value) {
    pauseCalls.add(value);
    paused = value;
  }

  @override
  void seekTo(Duration position) {
    seeks.add(position);
    positionMs = position.inMilliseconds;
  }

  @override
  Future<void> switchEpisode(EpisodeDirection direction) async {
    switches.add(direction);
    await Future<void>.delayed(Duration.zero);
    episodeId = episodeId! + (direction == EpisodeDirection.next ? 1 : -1);
    episodeTitle = 'Episode $episodeId';
  }
}

final class PlaybackFixture {
  PlaybackFixture({List<WatchHistoryItem>? rows})
      : rows = rows ?? [watchItem('/media/episode.mkv')] {
    capability = PlaybackCapability(
      player: player,
      start: (item) async {
        started.add(item);
        if (!startSucceeds) return false;
        player.hasVideo = true;
        player.path = item.videoPath;
        player.seriesTitle = item.title;
        player.episodeTitle = item.subtitle;
        player.animeId = item.animeId;
        player.episodeId = item.episodeId;
        return true;
      },
      usesExternalPlayer: () => external,
      historyItem: (path) async {
        pathLoads.add(path);
        return _byPath(path);
      },
      episodeItem: (animeId, episodeId) async {
        episodeLoads.add((animeId, episodeId));
        for (final item in this.rows) {
          if (item.animeId == animeId && item.episodeId == episodeId) {
            return item;
          }
        }
        return null;
      },
      fileSelection: EpisodeFileSelectionService(
        loadHistory: (path) async {
          selectionHistoryLoads.add(path);
          return storedForSelection ?? _byPath(path);
        },
        loadMatches: (animeId, episodeId) async {
          matchLoads.add((animeId, episodeId));
          return (matchesForSelection ?? this.rows)
              .where(
                (item) =>
                    item.animeId == animeId && item.episodeId == episodeId,
              )
              .toList();
        },
        clearMatch: (_) async =>
            throw StateError('Unmatching was not requested.'),
      ),
    );
    harness = Harness([capability]);
  }

  final List<WatchHistoryItem> rows;
  final TestPlayer player = TestPlayer();
  bool external = false;
  bool startSucceeds = true;
  WatchHistoryItem? storedForSelection;
  List<WatchHistoryItem>? matchesForSelection;
  final List<PlayableItem> started = [];
  final List<String> pathLoads = [];
  final List<(int, int)> episodeLoads = [];
  final List<String> selectionHistoryLoads = [];
  final List<(int, int)> matchLoads = [];
  late final PlaybackCapability capability;
  late final Harness harness;

  WatchHistoryItem? _byPath(String path) {
    for (final item in rows) {
      if (item.filePath == path) return item;
    }
    return null;
  }
}
