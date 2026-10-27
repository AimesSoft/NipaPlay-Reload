import 'dart:async';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/episode_file_candidate.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/episode_file_selection_service.dart';
import 'package:path/path.dart' as p;

import 'media_models.dart';

enum EpisodeDirection { next, previous }

abstract interface class PlayerPort {
  PlaybackSnapshot snapshot();
  FutureOr<void> setPaused(bool paused);
  FutureOr<void> seekTo(Duration position);
  Future<void> switchEpisode(EpisodeDirection direction);
}

final class PlaybackCapability implements Capability {
  PlaybackCapability({
    required PlayerPort player,
    required Future<bool> Function(PlayableItem item) start,
    required bool Function() usesExternalPlayer,
    required Future<WatchHistoryItem?> Function(String path) historyItem,
    required Future<WatchHistoryItem?> Function(int animeId, int episodeId)
        episodeItem,
    required EpisodeFileSelectionService fileSelection,
    Future<bool> Function(PlayableItem item, Duration start)? startAt,
  }) : actions = [
          PlaybackOpenAction._(player, start, usesExternalPlayer, historyItem,
              episodeItem, fileSelection, startAt),
          PlaybackStateAction._(player),
          PlaybackSetPausedAction._(player),
          PlaybackSeekAction._(player),
          PlaybackSwitchEpisodeAction._(player),
        ];

  @override
  final List<Action> actions;
}

final class PlaybackOpenAction
    extends Action<PlaybackOpenInput, PlaybackOpenOutput> {
  const PlaybackOpenAction._(
    this._player,
    this._start,
    this._usesExternalPlayer,
    this._historyItem,
    this._episodeItem,
    this._fileSelection, [
    this._startAt,
  ]);

  final PlayerPort _player;
  final Future<bool> Function(PlayableItem item) _start;
  final bool Function() _usesExternalPlayer;
  final Future<WatchHistoryItem?> Function(String path) _historyItem;
  final Future<WatchHistoryItem?> Function(int animeId, int episodeId)
      _episodeItem;
  final EpisodeFileSelectionService _fileSelection;

  /// Opens at a start position as part of the open, when the player can;
  /// otherwise the open is followed by a seek.
  final Future<bool> Function(PlayableItem item, Duration start)? _startAt;

  static const _spec = ActionSpec(
    id: 'playback.open',
    title: 'Open a video',
    description: 'Play a local file, URL, jellyfin://itemId or emby://itemId, '
        'including files with no watch history, or a recorded episode by IDs. '
        'Multiple episode files return a decision with executable path calls. '
        'An optional start position is supported by controllable players. '
        'Returns the selected path, player type and the state after opening; '
        'a source that failed to open leaves state.error with its stage, '
        'category and the kernel\'s own messages. When playback cannot be '
        'started at all, the failure details carry playerError if the player '
        'reported one.',
    effect: Effect.write,
    input: playbackOpenInputSchema,
    output: playbackOpenOutputSchema,
  );

  @override
  ActionSpec get spec => _spec;

  @override
  PlaybackOpenInput decodeInput(JsonMap json) => PlaybackOpenInput(
        path: json['path'] as String?,
        animeId: (json['animeId'] as num?)?.toInt(),
        episodeId: (json['episodeId'] as num?)?.toInt(),
        startPositionMs: (json['startPositionMs'] as num?)?.toInt(),
      );

  @override
  Future<Outcome<PlaybackOpenOutput>> run(
    PlaybackOpenInput input,
    Invocation invocation,
  ) async {
    var path = input.path;
    if (path != null && Uri.tryParse(path)?.scheme == 'file') {
      try {
        path = Uri.parse(path).toFilePath(windows: Platform.isWindows);
      } on UnsupportedError {
        throw const Failure(FailureCode.invalidInput, 'Invalid local file URL.');
      }
    }
    final history = path != null
        ? await _historyItem(path)
        : await _episodeItem(input.animeId!, input.episodeId!);
    if (history == null && path == null) {
      throw const Failure(FailureCode.notFound,
          'The requested file or episode was not found in watch history.');
    }
    if (history == null && path != null) {
      final uri = Uri.tryParse(path);
      if (p.isAbsolute(path) || uri == null || uri.scheme.isEmpty) {
        if (!p.isAbsolute(path)) {
          throw const Failure(FailureCode.invalidInput, 'Use an absolute file path.');
        }
        if (!await File(path).exists()) {
          throw const Failure(FailureCode.notFound, 'The local file does not exist or is inaccessible.');
        }
      } else if (uri.scheme == 'mesh') {
        if (uri.host.isNotEmpty || uri.pathSegments.length != 1 ||
            uri.pathSegments.single.isEmpty || uri.hasQuery || uri.hasFragment) {
          throw const Failure(FailureCode.invalidInput, 'A Mesh locator must name one episode.');
        }
      } else if (uri.host.isEmpty) {
        throw const Failure(FailureCode.invalidInput, 'A media URL must include a host or item ID.');
      }
    }
    final requested = PlayableItem(
      videoPath: history?.filePath ?? path!,
      title: history?.animeName,
      subtitle: history?.episodeTitle,
      animeId: history?.animeId,
      episodeId: history?.episodeId,
      historyItem: history,
      mediaKey: history?.mediaKey,
    );
    PlayableItem item = requested;
    if (path == null) {
      List<EpisodeFileCandidate>? candidates;
      final resolved = await _fileSelection.resolve(
        requested,
        choose: (files, unmatch) async {
          candidates = files;
          return null;
        },
      );
      if (candidates case final files?) {
        return NeedsDecision(Decision(
          prompt: 'Which file should be played for this episode?',
          options: [
            for (final candidate in files)
              DecisionOption(
                label: p.basename(candidate.displayPath),
                detail: '${candidate.sourceLabel} · '
                    '${(candidate.history.watchProgress * 100).round()}% watched',
                call: ActionCall.of(
                    this,
                    PlaybackOpenInput(
                      path: candidate.history.filePath,
                      startPositionMs: input.startPositionMs,
                    )),
              ),
          ],
        ));
      }
      if (resolved == null) {
        throw const Failure(FailureCode.notFound,
            'No playable file was found for the requested episode.');
      }
      item = resolved;
    }
    final position = input.startPositionMs;
    final startAt = _startAt;
    final started = position != null && startAt != null
        ? await startAt(item, Duration(milliseconds: position))
        : await _start(item);
    if (!started) {
      final error = _player.snapshot().error;
      throw Failure(FailureCode.unavailable,
          'NipaPlay cannot start playback right now; the window may not be ready.',
          retryable: true, details: {if (error != null) 'playerError': error});
    }
    if (position != null && startAt == null) {
      await _player.seekTo(Duration(milliseconds: position));
    }
    final state = _player.snapshot();
    return Completed(PlaybackOpenOutput(
      path: _usesExternalPlayer() ? item.videoPath : state.path ?? item.videoPath,
      player: state.player ?? (_usesExternalPlayer() ? 'external' : 'internal'),
      state: state,
    ));
  }
}

final class PlaybackStateAction extends Action<NoInput, PlaybackStateOutput> {
  const PlaybackStateAction._(this._player);

  final PlayerPort _player;

  static const _spec = ActionSpec(
    id: 'playback.state',
    title: 'Get playback state',
    description: 'Read the current player status, video metadata, position, '
        'duration, rate and episode navigation availability. '
        'The snapshot also describes the player when no video is loaded. '
        'For the internal player: rate is the chosen rate; effectiveRate the '
        'rate applied now (speedBoost.rate while the long-press boost is '
        'held, speedBoost.active); kernelRate the rate last given to the '
        'kernel; kernel the kernel playing (id, name; playback.info adds '
        'the kernel setting); danmakuRenderer the layer drawing danmaku '
        '(player_native when the kernel draws them, plugin with pluginId and '
        'rendererId, or a built-in engine id: cpu, gpu, canvas, '
        'nipaplay_next with nextPlusPlus, next2, dfm_plus); autoNext the end '
        'action and the next-episode countdown (countingDown, '
        'remainingSeconds, next). error, when set, carries stage, category, '
        'kernel, kernelRetryable (the kernel\'s own retry judgement, null '
        'when it makes none), messages (player, kernel, media) and failureId '
        'once recorded in playback.failures. Media details (codec, decoder, '
        'frame rate, bitrate, dropped frames) are in playback.info.',
    effect: Effect.read,
    input: ObjectSchema({}),
    output: playbackStateOutputSchema,
  );

  @override
  ActionSpec get spec => _spec;

  @override
  NoInput decodeInput(JsonMap json) => const NoInput();

  @override
  Future<Outcome<PlaybackStateOutput>> run(
    NoInput input,
    Invocation invocation,
  ) async =>
      Completed(PlaybackStateOutput(state: _player.snapshot()));
}

final class PlaybackSetPausedAction
    extends Action<PlaybackSetPausedInput, PlaybackStateOutput> {
  const PlaybackSetPausedAction._(this._player);

  final PlayerPort _player;

  static const _spec = ActionSpec(
    id: 'playback.set_paused',
    title: 'Set playback pause',
    description: 'Pause or resume the current video and return its state. '
        'Returns unavailable when no video is loaded.',
    effect: Effect.write,
    input: playbackSetPausedInputSchema,
    output: playbackStateOutputSchema,
  );

  @override
  ActionSpec get spec => _spec;

  @override
  PlaybackSetPausedInput decodeInput(JsonMap json) =>
      PlaybackSetPausedInput(paused: json['paused'] as bool);

  @override
  Future<Outcome<PlaybackStateOutput>> run(
    PlaybackSetPausedInput input,
    Invocation invocation,
  ) async {
    if (!_player.snapshot().hasVideo) {
      throw const Failure(FailureCode.unavailable, 'No video is loaded.');
    }
    await _player.setPaused(input.paused);
    return Completed(PlaybackStateOutput(state: _player.snapshot()));
  }
}

final class PlaybackSeekAction
    extends Action<PlaybackSeekInput, PlaybackStateOutput> {
  const PlaybackSeekAction._(this._player);

  final PlayerPort _player;

  static const _spec = ActionSpec(
    id: 'playback.seek',
    title: 'Seek in the current video',
    description: 'Seek to an absolute position or move by a relative offset '
        'in milliseconds, clamped to the video duration. '
        'Returns the resulting state, or unavailable when no video is loaded.',
    effect: Effect.write,
    input: playbackSeekInputSchema,
    output: playbackStateOutputSchema,
  );

  @override
  ActionSpec get spec => _spec;

  @override
  PlaybackSeekInput decodeInput(JsonMap json) => PlaybackSeekInput(
        positionMs: (json['positionMs'] as num?)?.toInt(),
        offsetMs: (json['offsetMs'] as num?)?.toInt(),
      );

  @override
  Future<Outcome<PlaybackStateOutput>> run(
    PlaybackSeekInput input,
    Invocation invocation,
  ) async {
    final state = _player.snapshot();
    if (!state.hasVideo) {
      throw const Failure(FailureCode.unavailable, 'No video is loaded.');
    }
    if (input.offsetMs != null && state.positionMs == null) {
      throw const Failure(FailureCode.unavailable, 'The external player cannot report position for a relative seek.');
    }
    final target = input.positionMs ?? state.positionMs! + input.offsetMs!;
    await _player.seekTo(Duration(milliseconds: target.clamp(0,
      state.durationMs == null || state.external != null && state.durationMs == 0 ? target.abs() : state.durationMs!)));
    return Completed(PlaybackStateOutput(state: _player.snapshot()));
  }
}

final class PlaybackSwitchEpisodeAction
    extends Action<PlaybackSwitchEpisodeInput, PlaybackStateOutput> {
  const PlaybackSwitchEpisodeAction._(this._player);

  final PlayerPort _player;

  static const _spec = ActionSpec(
    id: 'playback.switch_episode',
    title: 'Switch the current episode',
    description: 'Play the next or previous episode and return the new state '
        'after the switch completes. Returns unavailable when no video is '
        'loaded or the requested direction is unavailable.',
    effect: Effect.write,
    input: playbackSwitchEpisodeInputSchema,
    output: playbackStateOutputSchema,
  );

  @override
  ActionSpec get spec => _spec;

  @override
  PlaybackSwitchEpisodeInput decodeInput(JsonMap json) =>
      PlaybackSwitchEpisodeInput(direction: json['direction'] as String);

  @override
  Future<Outcome<PlaybackStateOutput>> run(
    PlaybackSwitchEpisodeInput input,
    Invocation invocation,
  ) async {
    final direction = EpisodeDirection.values.byName(input.direction);
    final state = _player.snapshot();
    final canSwitch = switch (direction) {
      EpisodeDirection.next => state.canNext,
      EpisodeDirection.previous => state.canPrevious,
    };
    if (!state.hasVideo || !canSwitch) {
      throw Failure(FailureCode.unavailable,
          'The ${direction.name} episode is unavailable.');
    }
    await _player.switchEpisode(direction);
    return Completed(PlaybackStateOutput(state: _player.snapshot()));
  }
}
