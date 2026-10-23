import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/utils/media_identity_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../harness_redaction.dart';
import '../core/host.dart';
import '../core/session.dart';
import 'progress.dart';
import 'resolver.dart';

/// Source and episode operations own only Dart data. All transport and
/// teardown remain with the session/host; no operation calls Classic.
final class PlaybackSources extends ChangeNotifier {
  PlaybackSources(this.host, this.resolver,
      {this.readEndSettings = defaultEndSettings}) {
    _events = host.events.listen(_event);
  }
  final NextPlayerHost host;
  final NextSourceResolver resolver;
  final Future<(String, int)> Function() readEndSettings;
  late final StreamSubscription<PlaybackEvent> _events;
  SourcePlan? plan;
  SourceProgress? progress;
  PlaybackSession? _bound;
  int _ticket = 0;
  int _endGeneration = 0;
  List<PlaybackDetailEpisode> _episodes = const [];
  int _index = -1;
  Timer? _countdown;
  int? _remaining;
  String? _endAction;
  String? _endHandled;
  String? error;
  bool _disposed = false;
  bool _switching = false;
  Future<void>? _playlistLoading;

  static Future<(String, int)> defaultEndSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      prefs.getString('playback_end_action') ?? 'autoNext',
      (prefs.getInt('auto_next_countdown_seconds') ?? 5).clamp(0, 15)
    );
  }

  bool get canPrevious => _bound?.phase.value.done == false && _index > 0;
  bool get canNext =>
      _bound?.phase.value.done == false &&
      _index >= 0 &&
      _index + 1 < _episodes.length;
  List<PlaybackDetailEpisode> get episodes => _episodes;
  int get currentIndex => _index;
  JsonMap? get autoNext => _remaining == null
      ? null
      : {
          'sessionId': _bound?.id,
          'endAction': _endAction,
          'countingDown': true,
          'remainingSeconds': _remaining,
          'nextTitle': canNext ? _episodes[_index + 1].title : null,
          'next': canNext
              ? {
                  'path': redactHarnessText(_episodes[_index + 1].videoPath),
                  'title': _episodes[_index + 1].title,
                  'subtitle': _episodes[_index + 1].subtitle,
                  'animeId': _episodes[_index + 1].animeId,
                  'episodeId': _episodes[_index + 1].episodeId
                }
              : null,
          'source': 'playback_end_action',
        };

  Future<PlaybackSession> open(PlayableItem item,
      {Duration? start,
      bool? paused,
      String origin = 'gui',
      JsonMap selection = const {},
      bool direct = false,
      PlayerLevels? initialLevels}) async {
    final ticket = ++_ticket;
    cancelAutoNext();
    host.resolve(MediaRequest(locator: item.videoPath, origin: origin));
    final effectiveStart = start ??
        Duration(milliseconds: await host.records.resumeAt(item.videoPath));
    final SourcePlan prepared;
    try {
      prepared = await resolver.resolve(item,
          start: effectiveStart, selection: selection, direct: direct);
    } on Failure {
      rethrow;
    } catch (e) {
      throw Failure(
          FailureCode.unavailable, 'Could not resolve the media source.',
          details: {
            'stage': 'source_resolution',
            'error': e.runtimeType.toString()
          });
    }
    if (_disposed || ticket != _ticket) {
      await prepared.progress?.stopTranscoding();
      throw const Failure(
          FailureCode.conflict, 'Playback changed while resolving the source.');
    }
    final history = item.historyItem;
    final session = await host.open(
        MediaRequest(
            locator: prepared.source.locator,
            origin: origin,
            title: item.title ?? history?.animeName ?? prepared.detail.title,
            episodeTitle: item.subtitle ??
                history?.episodeTitle ??
                prepared.detail.subtitle,
            animeId: item.animeId ?? history?.animeId,
            episodeId: item.episodeId ?? history?.episodeId,
            start: effectiveStart,
            paused: paused),
        initialLevels: initialLevels,
        resolvedSource: prepared.source, onCreated: (session) {
      if (_disposed || ticket != _ticket) {
        throw const Failure(FailureCode.conflict,
            'A newer playback request replaced this source.');
      }
      plan = prepared;
      _bound = session;
      _episodes = const [];
      _index = -1;
      _endHandled = null;
      error = null;
      if (prepared.source.kind != 'local') {
        progress = SourceProgress(session, prepared);
      } else {
        progress = null;
      }
      _playlistLoading = _loadPlaylist(session, prepared);
      notifyListeners();
    });
    return session;
  }

  Future<void> _loadPlaylist(PlaybackSession session, SourcePlan source) async {
    try {
      final episodes = await source.detail.episodeLoader();
      final key = MediaIdentityResolver.forPath(session.path);
      final prepared = await compute(
          _locatePlaylist, (episodes, session.path, key),
          debugLabel: 'next.source.playlist');
      if (!identical(_bound, session) ||
          session.phase.value.done ||
          _disposed) {
        return;
      }
      _episodes = prepared.$1;
      _index = prepared.$2;
      notifyListeners();
    } catch (e) {
      if (!identical(_bound, session) || _disposed) return;
      error = e.runtimeType.toString();
      notifyListeners();
    }
  }

  Future<JsonMap> playlist() async {
    final session = _bound;
    final source = plan;
    await _playlistLoading;
    if (session == null || source == null || session.phase.value.done) {
      return {
        'supported': true,
        'source': null,
        'items': <JsonMap>[],
        'currentIndex': null,
        'autoNext': null
      };
    }
    final rows = await compute(_playlistRows, _episodes,
        debugLabel: 'next.source.playlist_rows');
    _check(session);
    return {
      'supported': true,
      'source': source.detail.sourceKey,
      'items': rows,
      'currentIndex': _index,
      'autoNext': autoNext,
      'loadError': error
    };
  }

  void _check(PlaybackSession session) {
    if (_disposed ||
        !identical(host.current.value, session) ||
        session.phase.value.done) {
      throw const Failure(FailureCode.conflict, 'Playback session changed.');
    }
  }

  Future<void> playEpisode(PlaybackDetailEpisode episode,
      {String origin = 'gui'}) async {
    final session = _bound;
    final source = plan;
    if (session == null || source == null) return;
    _check(session);
    if (!_episodes.contains(episode)) {
      throw const Failure(
          FailureCode.conflict, 'The episode belongs to a previous playlist.');
    }
    if (_switching) {
      throw const Failure(
          FailureCode.conflict, 'An episode change is already running.');
    }
    _switching = true;
    try {
      await open(
          PlayableItem.fromDetailEpisode(episode, detailContext: source.detail),
          origin: origin);
    } finally {
      _switching = false;
    }
  }

  Future<void> switchEpisode(bool next, {String origin = 'gui'}) async {
    if (next ? !canNext : !canPrevious) {
      throw const Failure(
          FailureCode.notFound, 'There is no episode in that direction.');
    }
    await playEpisode(_episodes[_index + (next ? 1 : -1)], origin: origin);
  }

  bool cancelAutoNext() {
    final counting = _remaining != null;
    _endGeneration++;
    _countdown?.cancel();
    _countdown = null;
    _remaining = null;
    if (counting && !_disposed) notifyListeners();
    return counting;
  }

  /// Closing during asynchronous URL/credential resolution must fence the
  /// request too; otherwise its late result could open a new native core.
  void cancelPendingOpen() {
    _ticket++;
    cancelAutoNext();
  }

  void _event(PlaybackEvent event) {
    final session = _bound;
    if (session == null || session.id != event.sessionId) return;
    if (event.kind == 'ended' && _endHandled != session.id) {
      _endHandled = session.id;
      final generation = ++_endGeneration;
      // Do not close a synchronous event stream from inside its listener.
      unawaited(Future<void>(() => _ended(session, generation))
          .catchError((Object e) {
        error = e.runtimeType.toString();
      }));
    } else if (event.kind == 'seek_requested' ||
        event.kind == 'closed' ||
        event.kind == 'phase' && event.data['phase'] == 'closing') {
      cancelAutoNext();
      if (event.kind == 'seek_requested') _endHandled = null;
    }
  }

  Future<void> _ended(PlaybackSession session, int generation) async {
    final (action, seconds) = await readEndSettings();
    _endAction = action;
    await _playlistLoading;
    bool live() =>
        !_disposed &&
        generation == _endGeneration &&
        identical(host.current.value, session) &&
        !session.phase.value.done &&
        session.transport.value.ended;
    if (!live()) return;
    switch (action) {
      case 'loop':
        await session.seek(Duration.zero, origin: 'playback_end');
        if (identical(host.current.value, session) &&
            !session.phase.value.done) {
          await session.setPaused(false, origin: 'playback_end');
        }
      case 'exitPlayer':
        await host.close(reason: 'playback_end');
      case 'pause':
        await session.setPaused(true, origin: 'playback_end');
      case 'autoNext':
        if (!canNext) {
          await session.setPaused(true, origin: 'playback_end');
          return;
        }
        if (seconds == 0) {
          await switchEpisode(true, origin: 'playback_end');
          return;
        }
        _remaining = seconds;
        notifyListeners();
        _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!live()) {
            cancelAutoNext();
            return;
          }
          _remaining = _remaining! - 1;
          if (_remaining! <= 0) {
            cancelAutoNext();
            unawaited(switchEpisode(true, origin: 'playback_end')
                .catchError((Object e) {
              error = e.runtimeType.toString();
            }));
          } else {
            notifyListeners();
          }
        });
    }
  }

  JsonMap streamOptions() {
    final source = plan;
    final session = source?.serverSession;
    if (source == null || session == null || _bound?.phase.value.done == true) {
      throw const Failure(FailureCode.unavailable,
          'The current source is not a Jellyfin or Emby session.');
    }
    return {
      'server': source.source.kind,
      'itemId': session.itemId,
      'isTranscoding': session.isTranscoding,
      ...source.selection,
      'qualities': [for (final q in JellyfinVideoQuality.values) q.name],
      'versions': [
        for (final version in session.mediaSources)
          {
            'id': version.id,
            'name': version.name,
            'size': version.size,
            'bitrate': version.bitRate,
            'container': version.container,
            'supportsTranscoding': version.supportsTranscoding,
            'tracks': [
              for (final stream in version.mediaStreams)
                if (stream['Type'] == 'Audio' || stream['Type'] == 'Subtitle')
                  {
                    'index': stream['Index'],
                    'kind': (stream['Type'] as String).toLowerCase(),
                    'origin': 'server',
                    'codec': stream['Codec'],
                    'language': stream['Language'],
                    'title': stream['DisplayTitle'] ?? stream['Title'],
                    'external': stream['IsExternal'] == true,
                    'default': stream['IsDefault'] == true,
                    'selected': source.selection[stream['Type'] == 'Audio'
                            ? 'audioIndex'
                            : 'subtitleIndex'] ==
                        stream['Index'],
                  }
            ],
          }
      ],
    };
  }

  Future<JsonMap> selectStream(JsonMap input, {String origin = 'gui'}) async {
    final before = streamOptions();
    final session = _bound!;
    final source = plan!;
    final selection = {...source.selection, ...input};
    final versions = source.serverSession!.mediaSources;
    final version =
        versions.where((v) => v.id == selection['mediaSourceId']).firstOrNull;
    if (version == null) {
      throw const Failure(
          FailureCode.notFound, 'The media version does not exist.');
    }
    if (selection['mediaSourceId'] != before['mediaSourceId']) {
      if (!input.containsKey('audioIndex')) selection.remove('audioIndex');
      if (!input.containsKey('subtitleIndex')) {
        selection.remove('subtitleIndex');
      }
    }
    for (final (key, kind) in [
      ('audioIndex', 'Audio'),
      ('subtitleIndex', 'Subtitle')
    ]) {
      final index = selection[key];
      if (index == null || key == 'subtitleIndex' && index == -1) continue;
      if (!version.mediaStreams
          .any((t) => t['Type'] == kind && t['Index'] == index)) {
        throw Failure(
            FailureCode.notFound, 'The $kind track is not in this version.');
      }
    }
    if (input['transcode'] == false && !input.containsKey('quality')) {
      selection['quality'] = 'original';
    }
    final quality =
        JellyfinVideoQuality.values.byName(selection['quality'] as String);
    final reduced = quality != JellyfinVideoQuality.original;
    final enabled = input['transcode'] as bool? ??
        (reduced || selection['transcode'] == true);
    if (!enabled && reduced ||
        selection['burnIn'] == true &&
            (!enabled ||
                !reduced ||
                selection['subtitleIndex'] == null ||
                selection['subtitleIndex'] == -1)) {
      throw const Failure(FailureCode.invalidInput,
          'Reduced quality and subtitle burn-in require transcoding and a selected subtitle.');
    }
    final emby = source.source.kind == 'emby';
    final saved = emby
        ? await EmbyTranscodeProvider().setDefaultVideoQuality(quality) &&
            await EmbyTranscodeProvider().setTranscodeEnabled(enabled)
        : await JellyfinTranscodeProvider().setDefaultVideoQuality(quality) &&
            await JellyfinTranscodeProvider().setTranscodeEnabled(enabled);
    if (!saved) {
      throw const Failure(FailureCode.unavailable,
          'Could not save the shared stream settings.');
    }
    _check(session);
    final next = await open(source.item,
        start: session.position,
        paused: !session.transport.value.playIntent,
        origin: origin,
        selection: selection);
    if (next.phase.value == SessionPhase.failed) {
      throw Failure(
          FailureCode.unavailable, 'The selected stream failed to open.',
          details: next.fault.value?.toJson() ?? const {});
    }
    return streamOptions();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticket++;
    cancelAutoNext();
    unawaited(_events.cancel());
    super.dispose();
  }
}

(List<PlaybackDetailEpisode>, int) _locatePlaylist(
    (List<PlaybackDetailEpisode>, String, String) input) {
  final (episodes, path, key) = input;
  var index = -1;
  for (var i = 0; i < episodes.length; i++) {
    final episode = episodes[i];
    if (episode.videoPath == path ||
        (episode.mediaKey ??
                MediaIdentityResolver.forPath(episode.videoPath)) ==
            key) {
      index = i;
    }
  }
  return (List.unmodifiable(episodes), index);
}

List<JsonMap> _playlistRows(List<PlaybackDetailEpisode> episodes) => [
      for (final episode in episodes)
        {
          'id': episode.id,
          'path': redactHarnessText(episode.videoPath),
          'title': episode.title,
          'episodeId': episode.episodeId,
        }
    ];
