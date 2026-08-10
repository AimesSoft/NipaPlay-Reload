import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/emby_media_selection_resolver.dart';

typedef EmbyPlaybackSessionCreator = Future<PlaybackSession> Function(
  EmbyPlaybackSessionRequest request,
);

typedef EmbyPreferenceLoader = Future<EmbyPreferenceLayers> Function(
  EmbySelectionContext context,
);

/// Verifies that initialization produced a usable player state.
void ensureEmbyPlayerOpened(String? playerError, bool hasVideo) {
  final message = playerError?.trim();
  if (message != null && message.isNotEmpty) {
    throw StateError(message);
  }
  if (!hasVideo) {
    throw StateError('Emby player initialization completed without video.');
  }
}

/// Initializes one candidate, validates it, and starts playback in order.
Future<void> initializeEmbyPlayerAttempt({
  required Future<void> Function() initialize,
  required String? Function() readError,
  required bool Function() hasVideo,
  required Future<void> Function() play,
}) async {
  await initialize();
  final playerError = readError();
  final openedVideo = hasVideo();
  ensureEmbyPlayerOpened(playerError, openedVideo);
  await play();
}

/// Parameters required to create a playback session for one resolved source.
class EmbyPlaybackSessionRequest {
  const EmbyPlaybackSessionRequest({
    required this.itemId,
    required this.mediaSourceId,
    this.startPositionMs,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.burnInSubtitle = false,
    this.playSessionId,
  });

  final String itemId;
  final String mediaSourceId;
  final int? startPositionMs;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final bool burnInSubtitle;
  final String? playSessionId;
}

/// A playable Emby session together with the source decision that produced it.
class EmbyResolvedPlayback {
  const EmbyResolvedPlayback({
    required this.session,
    required this.reason,
    required this.didFallback,
    required this.tracks,
  });

  final PlaybackSession session;
  final EmbySelectionReason reason;
  final bool didFallback;
  final EmbyResolvedTrackBundle tracks;
}

/// Keeps the active track bundle aligned with player initialization calls.
class EmbyPlaybackStateCoordinator {
  EmbyPlaybackStateCoordinator({
    required Future<void> Function(
      PlaybackSession session,
      EmbyResolvedTrackBundle tracks,
    ) initializePlayer,
    EmbyResolvedPlayback? currentPlayback,
    Future<void> Function()? restorePlaybackState,
  })  : _initializePlayer = initializePlayer,
        _currentPlayback = currentPlayback,
        _currentTrackSelection = currentPlayback?.tracks,
        _restorePlaybackState = restorePlaybackState;

  final Future<void> Function(
    PlaybackSession session,
    EmbyResolvedTrackBundle tracks,
  ) _initializePlayer;
  final Future<void> Function()? _restorePlaybackState;

  EmbyResolvedPlayback? _currentPlayback;
  EmbyResolvedTrackBundle? _currentTrackSelection;

  EmbyResolvedTrackBundle? get currentTrackSelection => _currentTrackSelection;

  Future<void> initialize(EmbyResolvedPlayback playback) async {
    await _initializePlayer(playback.session, playback.tracks);
    _currentPlayback = playback;
    _currentTrackSelection = playback.tracks;
  }

  Future<void> reload(EmbyResolvedPlayback playback) async {
    final previousPlayback = _currentPlayback;
    try {
      await _initializePlayer(playback.session, playback.tracks);
      _currentPlayback = playback;
      _currentTrackSelection = playback.tracks;
    } catch (error, stackTrace) {
      if (previousPlayback != null) {
        _currentPlayback = previousPlayback;
        _currentTrackSelection = previousPlayback.tracks;
        try {
          await _initializePlayer(
            previousPlayback.session,
            previousPlayback.tracks,
          );
          try {
            await _restorePlaybackState?.call();
          } catch (_) {
            // The failed replacement remains the primary reload error.
          }
        } catch (_) {
          // The original reload failure remains the actionable error.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// Extracts the episode item identifier from an Emby playback path.
String embyItemIdFromVideoPath(String videoPath) {
  final path = videoPath.replaceFirst('emby://', '');
  return path.split('/').where((segment) => segment.isNotEmpty).lastOrNull ??
      path;
}

/// Creates a session using the source and track indexes owned by [candidate].
Future<PlaybackSession> createEmbyPlaybackSessionForCandidate({
  required String itemId,
  required EmbySourceCandidate candidate,
  int? startPositionMs,
  String? playSessionId,
  required EmbyPlaybackSessionCreator createSession,
}) {
  final audio = candidate.tracks.audio;
  final subtitle = candidate.tracks.subtitle;
  return createSession(
    EmbyPlaybackSessionRequest(
      itemId: itemId,
      mediaSourceId: candidate.source.source.id,
      startPositionMs: startPositionMs,
      playSessionId: playSessionId,
      audioStreamIndex:
          audio.mode == EmbyResolvedTrackMode.track ? audio.sourceIndex : null,
      subtitleStreamIndex: subtitle.mode == EmbyResolvedTrackMode.track
          ? subtitle.sourceIndex
          : null,
      burnInSubtitle: requiresEmbySubtitleBurnIn(subtitle),
    ),
  );
}

bool requiresEmbySubtitleBurnIn(EmbyResolvedTrackSelection subtitle) {
  if (subtitle.mode != EmbyResolvedTrackMode.track) return false;
  final fingerprint = subtitle.fingerprint;
  if (fingerprint == null || fingerprint.isExternal != false) return false;
  final codec = fingerprint.codec
      ?.trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]'), '');
  return const <String>{
    'pgs',
    'pgssub',
    'hdmvpgssubtitle',
    'dvdsub',
    'dvdsubtitle',
    'vobsub',
    'dvbsub',
    'dvbsubtitle',
    'xsub',
  }.contains(codec);
}

/// Tries each unique source in plan order and returns the first usable session.
Future<EmbyResolvedPlayback> resolveEmbyPlaybackSession({
  required EmbyResolutionPlan plan,
  required Future<PlaybackSession> Function(EmbySourceCandidate candidate)
      createSession,
  Future<void> Function(EmbyResolvedPlayback playback)? startPlayback,
}) async {
  final attemptedSourceIds = <String>{};
  Object? lastError;
  StackTrace? lastStackTrace;
  var attemptIndex = 0;

  for (final candidate in plan.candidates) {
    if (!attemptedSourceIds.add(candidate.source.source.id)) continue;
    try {
      final session = await createSession(candidate);
      final expectedSourceId = candidate.source.source.id;
      if (session.mediaSourceId != expectedSourceId) {
        throw StateError(
          'Emby returned media source ${session.mediaSourceId} '
          'for requested source $expectedSourceId.',
        );
      }
      final playback = EmbyResolvedPlayback(
        session: session,
        reason: candidate.reason,
        didFallback: attemptIndex > 0,
        tracks: candidate.tracks,
      );
      await startPlayback?.call(playback);
      return playback;
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
      attemptIndex++;
    }
  }

  if (lastError != null) {
    Error.throwWithStackTrace(lastError, lastStackTrace!);
  }
  throw StateError('No Emby media source is available for playback.');
}

/// Resolves ordered playback candidates without reading unavailable identity.
Future<EmbyResolutionPlan> loadEmbyPlaybackResolutionPlan({
  required EmbySelectionContext? context,
  required List<EmbyMediaSourceDescriptor> sources,
  required EmbyPreferenceLoader loadPreferences,
  required EmbyMediaSelectionResolver resolver,
}) async {
  final preferences = context == null
      ? const EmbyPreferenceLayers()
      : await loadPreferences(context);
  return resolver.resolve(sources: sources, preferences: preferences);
}

/// Resolves, creates, and starts one Emby episode playback operation.
Future<EmbyResolvedPlayback> startEmbyEpisodePlayback({
  required String itemId,
  required EmbySelectionContext? context,
  required List<EmbyMediaSourceDescriptor> sources,
  required EmbyPreferenceLoader loadPreferences,
  required EmbyMediaSelectionResolver resolver,
  required EmbyPlaybackSessionCreator createSession,
  required Future<void> Function(EmbyResolvedPlayback playback) startPlayback,
  int? startPositionMs,
  String? playSessionId,
}) async {
  final plan = await loadEmbyPlaybackResolutionPlan(
    context: context,
    sources: sources,
    loadPreferences: loadPreferences,
    resolver: resolver,
  );
  final playback = await resolveEmbyPlaybackSession(
    plan: plan,
    createSession: (candidate) => createEmbyPlaybackSessionForCandidate(
      itemId: itemId,
      candidate: candidate,
      startPositionMs: startPositionMs,
      playSessionId: playSessionId,
      createSession: createSession,
    ),
    startPlayback: startPlayback,
  );
  return playback;
}
