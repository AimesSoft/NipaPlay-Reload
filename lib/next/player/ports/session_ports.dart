import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/remote_subtitle_service.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:path/path.dart' as p;

import '../../capabilities/media_models.dart';
import '../../capabilities/playback_capability.dart';
import '../../capabilities/playback_controls_capability.dart';
import '../../capabilities/playback_inspection.dart';
import '../../capabilities/player_facts.dart';
import '../../harness_redaction.dart';
import '../../state/change_history.dart';
import '../core/session.dart';
import '../kernel/driver.dart';
import '../next_playback.dart';
import '../perf/budget.dart';
import '../subtitles/controller.dart';
import 'session_playback.dart';

/// What Next's playback layer cannot do yet (D5): unavailable, with the
/// feature named in the details.
Never notInPlaybackLayer(String feature, String message) => throw Failure(
    FailureCode.unavailable, message,
    details: {'reason': 'not_in_playback_layer', 'feature': feature});

/// Who asked, for the intent's record: the person in Next's interface or
/// Nipa.
String commandOrigin() =>
    BodyChanges.invocation?.origin == 'gui' ? 'gui' : 'agent';

/// playback.open/state/set_paused/seek over Next's playback layer.
final class SessionPlayerPort implements PlayerPort {
  SessionPlayerPort(this._playback);
  final SessionPlayback _playback;

  @override
  PlaybackSnapshot snapshot() {
    final p = _playback;
    final s = p.session;
    final t = s?.transport.value;
    final phase = s?.phase.value;
    final open = phase?.open ?? false;
    final live = s != null && phase != SessionPhase.closed;
    final shown = p.transport.value;
    final record = s?.record;
    return PlaybackSnapshot(
      observedAt: DateTime.now(),
      player: 'internal',
      status: shown.status,
      hasVideo: shown.hasVideo,
      paused: open ? t!.observed != KernelTransport.playing : null,
      path: live ? s.path : null,
      seriesTitle: live ? p.workTitle : null,
      episodeTitle: live ? p.episodeTitle : null,
      animeId: live ? record?.animeId ?? s.request.animeId : null,
      episodeId: live ? record?.episodeId ?? s.request.episodeId : null,
      positionMs: live ? s.position.inMilliseconds : 0,
      durationMs: live ? s.duration.inMilliseconds : 0,
      rate: t?.rate ?? p.rate,
      effectiveRate: t?.rate ?? p.rate,
      kernelRate: t?.rate ?? p.rate,
      volume: p.volume,
      canPrevious: p.sources.canPrevious,
      canNext: p.sources.canNext,
      autoNext: p.sources.autoNext,
      sessionId: live ? s.id : null,
      ready: live ? open : null,
      buffering: open ? t!.buffering : null,
      error: live ? errorFacts(s) : null,
      kernel: {
        'id': KernelId.mdk.id,
        'name': KernelId.mdk.label,
        'instance': s?.driver?.instance,
        'configured': p.host.configuredKernel(),
        'layer': 'next_core',
      },
      supportedControls: const [
        'pause',
        'resume',
        'seek',
        'close',
        'wait',
        'playlist'
      ],
    );
  }

  /// A failed session's error, as playback.state carries it.
  static JsonMap? errorFacts(PlaybackSession s) {
    final fault = s.fault.value;
    if (fault == null) return null;
    final recorded = PlaybackFailures.instance.latestFor(s.id);
    return {
      'code': 'media_load_failed',
      'message': redactHarnessText(fault.message),
      'reason': 'source_or_decoder_failure',
      'retryable': true,
      'recoveryAction': 'playback.open',
      'stage': fault.stage,
      'category': recorded?['category'] ??
          playbackFailureCategory(
              stage: fault.stage, kernelMessage: fault.message),
      'kernel': KernelId.mdk.id,
      'kernelRetryable': fault.retryable,
      'messages': {
        'player': null,
        'kernel': safePlayerText(fault.message),
        'media': null,
      },
      if (recorded?['failureId'] case final id?) 'failureId': id,
    };
  }

  @override
  Future<void> setPaused(bool paused) async {
    final s = _playback.session;
    if (s == null) return;
    await s.setPaused(paused, origin: commandOrigin());
  }

  @override
  Future<void> seekTo(Duration position) async {
    final s = _playback.session;
    if (s == null) return;
    await s.seek(position, origin: commandOrigin());
  }

  @override
  Future<void> switchEpisode(EpisodeDirection direction) async =>
      _playback.sources.switchEpisode(direction == EpisodeDirection.next,
          origin: commandOrigin());
}

/// playback.wait/close/info/failures… over Next's playback layer; what it
/// does not do yet is unavailable, with the reason.
final class SessionControls
    implements PlaybackControlsPort, PlaybackInspectionPort {
  SessionControls(this._playback);
  final SessionPlayback _playback;

  JsonMap get _state => _playback.port.snapshot().toJson();

  @override
  Future<JsonMap> inspect(String operation, JsonMap input) async {
    switch (operation) {
      case 'playback.wait':
        return _wait(input);
      case 'playback.info':
        return _info();
      case 'playback.failures':
        final records = PlaybackFailures.instance.records.reversed.toList();
        return {
          'failures': records.take(input['limit'] as int? ?? 20).toList(),
          'total': records.length,
          'capacity': PlaybackFailures.capacity,
        };
      case 'playback.cancel_auto_next':
        return {
          'cancelled': _playback.sources.cancelAutoNext(),
          'state': _state
        };
      case 'playback.retry':
        notInPlaybackLayer('retry',
            'Next\'s playback layer does not retry yet; open the path again with playback.open.');
      case 'playback.chapters':
        return {
          'sessionId': _playback.session?.id,
          'items': _playback.danmaku.chapters,
          'index': _playback.danmaku.chapters.lastIndexWhere((c) =>
              (c['startMs'] as num) <= _playback.position.inMilliseconds),
          'skipSegments': [for (final segment in _playback.danmaku.timeline.segments)
            {'kind': segment.kind.name, 'source': segment.source.name,
              'startMs': segment.start.inMilliseconds,
              'endMs': segment.end.inMilliseconds,
              'evidenceCount': segment.evidenceCount}],
          'activeSkipKind': _playback.activeSkipSegment?.kind.name,
        };
      case 'playback.navigate':
        if (input['skipKind'] case final String kind) {
          final segment = kind == 'current' ? _playback.activeSkipSegment
              : _playback.danmaku.timeline.segments.where((s) => s.kind.name == kind).firstOrNull;
          if (segment != null) {
            await _playback.skipTo(segment, origin: commandOrigin());
          }
          return {'commandStatus': 'accepted', 'method': 'skip', 'state': _state};
        }
        if (input['chapterIndex'] case final int index) {
          final chapters = _playback.danmaku.chapters;
          if (index < 0 || index >= chapters.length) {
            throw const Failure(FailureCode.invalidInput, 'Chapter index out of range.');
          }
          await _playback.session?.seek(Duration(milliseconds: chapters[index]['startMs'] as int),
              origin: commandOrigin());
          return {'commandStatus': 'accepted', 'method': 'chapter', 'state': _state};
        }
        notInPlaybackLayer('chapters',
            'Next\'s playback layer does not read chapters, step frames or skip segments yet.');
      case 'playback.playlist':
        return _playback.sources.playlist();
      case 'subtitle.cues':
        return _cues(input);
      case 'danmaku.entries':
        return _playback.danmaku.entries(input, _playback.position.inMilliseconds);
    }
    throw Failure(FailureCode.invalidInput, 'Unknown operation $operation.');
  }

  /// Event-driven: completes when the session gets there, ends, changes or
  /// the time is up. Nothing polls.
  Future<JsonMap> _wait(JsonMap input) async {
    final s = _playback.session;
    if (s == null || s.id != input['sessionId']) {
      return {'outcome': 'session_changed', 'state': _state};
    }
    final until = input['until'] as String;
    final timeout = Duration(milliseconds: input['timeoutMs'] as int? ?? 5000);
    bool matched() {
      final open = s.phase.value.open;
      final t = s.transport.value;
      return switch (until) {
        'ready' => open,
        'playing' =>
          open && t.observed == KernelTransport.playing && !t.buffering,
        'paused' => open && t.observed != KernelTransport.playing,
        'buffering' => t.buffering,
        'error' => s.fault.value != null,
        _ => false,
      };
    }

    String? outcome() {
      if (!identical(_playback.session, s) || s.phase.value.done) {
        return 'session_changed';
      }
      if (matched()) return 'matched';
      if (s.fault.value != null) return 'error';
      return null;
    }

    if (outcome() case final now?) return {'outcome': now, 'state': _state};
    final done = Completer<String>();
    void check() {
      if (done.isCompleted) return;
      if (outcome() case final now?) done.complete(now);
    }

    final sources = [
      s.phase,
      s.transport,
      s.fault,
      _playback.host.current,
    ];
    for (final source in sources) {
      source.addListener(check);
    }
    final timer = Timer(timeout, () {
      if (!done.isCompleted) done.complete('timeout');
    });
    try {
      return {'outcome': await done.future, 'state': _state};
    } finally {
      timer.cancel();
      for (final source in sources) {
        source.removeListener(check);
      }
    }
  }

  Future<JsonMap> _info() async {
    final s = _playback.session;
    final driver = s?.driver;
    JsonMap? kernel;
    if (driver != null && !driver.fenced) {
      try {
        kernel = await driver.readFacts();
      } on KernelFenced {
        kernel = null;
      }
    }
    final media = s?.media.value;
    final decoders = kernel?['decoders'] as JsonMap?;
    final first = media?.audio.firstOrNull;
    return {
      'sessionId': s?.id,
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'player': 'internal',
      'hasVideo': _playback.hasVideo,
      'layer': 'next_core',
      'kernel': {
        'id': KernelId.mdk.id,
        'name': KernelId.mdk.label,
        'configured': _playback.host.configuredKernel(),
        'version': kernel?['version'],
        'instance': driver?.instance,
      },
      'container': media == null
          ? null
          : {'format': media.format, 'bitrate': media.bitRate},
      'video': media == null || !media.hasVideo
          ? null
          : {
              'codec': media.videoCodec,
              'width': media.width,
              'height': media.height,
              'fps': media.frameRate,
            },
      'decoder': decoders == null
          ? null
          : {
              'name': decoders['video'],
              'requested': decoders['requested'],
            },
      'audio': first == null
          ? null
          : {
              'codec': first.codec,
              'decoder': decoders?['audio'],
              'sampleRate': first.sampleRate,
              'channels': first.channels,
            },
      'cache': kernel == null
          ? null
          : {
              'aheadSeconds': (kernel['bufferedAheadMs'] as int?) == null
                  ? null
                  : (kernel['bufferedAheadMs'] as int) / 1000,
            },
      'session': s?.facts(),
      'kernelDetails': kernel,
      'host': _playback.host.facts(),
      'danmakuRenderer': _playback.danmakuRendererFacts,
    };
  }

  /// The session whose media is open; unavailable otherwise, as Classic.
  PlaybackSession _open() {
    final s = _playback.session;
    if (s == null || !s.phase.value.open) {
      throw const Failure(
          FailureCode.unavailable, 'No internal video is loaded.');
    }
    return s;
  }

  /// The media's audio and subtitle tracks and the subtitle files of this
  /// playback, each with what was chosen, by whom, who draws it and
  /// whether it shows (player-core design §5.1).
  @override
  Future<JsonMap> tracks(JsonMap input) async {
    // A media server's own streams (the server decides what is decoded)
    // are listed in place of the kernel's tracks while one plays.
    if (_playback.sources.plan?.isServer == true) {
      return {
        'sessionId': _playback.session?.id,
        'tracks': [
          for (final v
              in _playback.sources.streamOptions()['versions'] as List)
            if (v['id'] ==
                _playback.sources.plan?.serverSession?.mediaSourceId)
              ...v['tracks'] as List
        ]
      };
    }
    final s = _open();
    return PlayerPerf.span('ports.tracks', () => trackFacts(s));
  }

  static JsonMap trackFacts(PlaybackSession s) {
    final media = s.media.value;
    final audio = s.audio.value;
    final subs = s.subtitles;
    final state = subs.state.value;
    bool shows(SubtitleWant want) =>
        state.presented.any((p) => p.want == want);
    PresentedSubtitle? shown(SubtitleWant want) =>
        state.presented.where((p) => p.want == want).firstOrNull;
    final kernelAudio = audio.kernel ?? 0;
    return {
      'tracks': [
        for (final t in media?.audio ?? const <TrackFacts>[])
          {
            'kind': 'audio',
            'origin': 'embedded',
            'index': t.index,
            'title': t.title,
            'language': t.language,
            'codec': t.codec,
            'selected': (audio.want ?? kernelAudio) == t.index,
            'selectedBy': audio.want == t.index ? audio.selectedBy : 'default',
            'confirmed': audio.want == null
                ? t.index == kernelAudio
                : audio.kernel == t.index && audio.confirmed,
          },
        for (final t in media?.subtitles ?? const <TrackFacts>[])
          {
            'kind': 'subtitle',
            'origin': 'embedded',
            'index': t.index,
            'title': t.title,
            'language': t.language,
            'codec': t.codec,
            'renderer': SubtitleRenderer.kernel.name,
            'selected': state.want == SubtitleWant.embedded(t.index),
            if (state.want == SubtitleWant.embedded(t.index))
              'selectedBy': state.selectedBy,
            'presented': shows(SubtitleWant.embedded(t.index)),
            if (shown(SubtitleWant.embedded(t.index)) case final p?)
              'confirmed': p.confirmed,
          },
        for (final f in state.files)
          {
            'kind': 'subtitle',
            'origin': 'external',
            'path': redactHarnessText(f.path),
            'title': f.title,
            'language': null,
            'source': f.origin,
            'trackId': null,
            'format': f.format,
            'renderer': f.renderer.name,
            'selected': state.want == SubtitleWant.file(f.path),
            if (state.want == SubtitleWant.file(f.path))
              'selectedBy': state.selectedBy,
            'presented': shows(SubtitleWant.file(f.path)),
            if (shown(SubtitleWant.file(f.path)) case final p?)
              'confirmed': p.confirmed,
          },
      ],
      'subtitles': {
        'selected': state.want.toJson(),
        'selectedBy': state.selectedBy,
        'presented': [for (final p in state.presented) p.toJson()],
        'presentedIsSelected': subs.presentedIsSelected,
        if (state.failure != null) 'failure': state.failure,
      },
    };
  }

  /// An embedded audio or subtitle track (index -1: no subtitle). Returns
  /// once the kernel reported it, with the receipt.
  @override
  Future<JsonMap> selectTrack(JsonMap input) async {
    if (input['origin'] == 'server') {
      return _playback.sources.selectStream({
        input['kind'] == 'audio' ? 'audioIndex' : 'subtitleIndex':
            input['index']
      }, origin: commandOrigin());
    }
    final s = _open();
    final kind = input['kind'] as String;
    final index = (input['index'] as num).toInt();
    if (kind == 'audio' && index < 0) {
      throw const Failure(FailureCode.invalidInput,
          'An audio track index must be nonnegative.');
    }
    final media = s.media.value;
    final count = kind == 'audio'
        ? (media?.audio.length ?? 0)
        : (media?.subtitles.length ?? 0);
    if (index >= count) {
      throw const Failure(
          FailureCode.notFound, 'The requested embedded track does not exist.');
    }
    final origin = commandOrigin();
    final receipt = kind == 'audio'
        ? await s.selectAudio(index, origin: origin)
        : await s.chooseSubtitle(
            index < 0
                ? const SubtitleWant.off()
                : SubtitleWant.embedded(index),
            origin: origin);
    return {...trackFacts(s), 'receipt': receipt.toJson()};
  }

  /// A local subtitle file or an HTTP(S) one (cached as Classic caches
  /// them), mounted on this playback and, by default, put on alone. Kept
  /// in the subtitle list Classic and Next share.
  @override
  Future<JsonMap> loadSubtitle(JsonMap input) async {
    final s = _open();
    var path = input['path'] as String;
    final uri = Uri.tryParse(path);
    final extension = p.extension(uri?.path ?? path).toLowerCase();
    if (!{'.srt', '.ass', '.ssa', '.vtt', '.sub', '.idx', '.sup'}
        .contains(extension)) {
      throw const Failure(
          FailureCode.invalidInput, 'Unsupported subtitle file extension.');
    }
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final name = p.posix.basename(uri.path);
      path = await RemoteSubtitleService.instance.ensureSubtitleCached(
          SharedRemoteSubtitleCandidate(
              shareId: 'agent',
              fileName: name,
              subtitleUri: uri,
              authorizationHeader: null,
              isLikelyMatch: true,
              name: name,
              extension: p.extension(name)));
    } else if (!p.isAbsolute(path) || !await File(path).exists()) {
      throw const Failure(FailureCode.notFound,
          'Use an accessible absolute subtitle path or HTTP(S) URL.');
    }
    final origin = commandOrigin();
    CommandReceipt? receipt;
    if (input['activate'] != false) {
      receipt = await s.chooseSubtitle(SubtitleWant.file(path),
          origin: origin, title: p.basename(path));
    } else {
      s.subtitles.offer(path, p.basename(path), origin: origin);
    }
    await rememberSubtitle(s.path, path,
        active: s.subtitles.want == SubtitleWant.file(path));
    return {
      'path': path,
      'active': s.subtitles.want == SubtitleWant.file(path),
      'renderer': s.subtitles.rendererOf(path).name,
      if (receipt != null) 'receipt': receipt.toJson(),
    };
  }

  /// Keeps [subtitle] in the subtitle list Classic and Next share for
  /// [video] (D3), as Classic's load does.
  static Future<void> rememberSubtitle(String video, String subtitle,
      {required bool active}) async {
    final saved = await SubtitleService().addExternalSubtitles(video, [
      {
        'path': subtitle,
        'name': p.basename(subtitle),
        'type': p.extension(subtitle).replaceFirst('.', ''),
        'addTime': DateTime.now().millisecondsSinceEpoch,
        'isActive': active,
      }
    ]);
    if (!saved) {
      throw const Failure(FailureCode.unavailable,
          'The shared subtitle list could not be saved.');
    }
  }

  /// Takes a subtitle file off this playback (nothing shows if it did),
  /// and out of the shared list; the file stays.
  @override
  Future<JsonMap> removeSubtitle(JsonMap input) async {
    final s = _open();
    final path = input['path'] as String;
    final showing = s.subtitles.want == SubtitleWant.file(path);
    if (showing) {
      await s.chooseSubtitle(const SubtitleWant.off(), origin: commandOrigin());
    }
    await s.subtitles.unmount(path, by: commandOrigin());
    final subtitles = await SubtitleService().loadExternalSubtitles(s.path);
    final index = subtitles.indexWhere((subtitle) => subtitle['path'] == path);
    if (index >= 0 &&
        !await SubtitleService().removeExternalSubtitle(s.path, index)) {
      throw const Failure(FailureCode.unavailable,
          'The shared subtitle list could not be updated.');
    }
    return {
      'path': path,
      'active': s.subtitles.want == SubtitleWant.file(path),
    };
  }

  /// subtitle.cues over what shows: the file's timed text, parsed off the
  /// main isolate, at the times it is drawn.
  Future<JsonMap> _cues(JsonMap input) async {
    final s = _playback.session;
    final sessionId = input['sessionId'];
    if (sessionId != null && s?.id != sessionId) {
      throw const Failure(FailureCode.conflict,
          'Playback session changed. Read playback.state.');
    }
    if (s == null || !s.phase.value.open) {
      throw const Failure(
          FailureCode.unavailable, 'No internal video is loaded.');
    }
    final position = input['positionMs'] as int? ?? s.position.inMilliseconds;
    final page = await s.subtitles.readCues(input, positionMs: position);
    if (!identical(_playback.session, s)) {
      throw const Failure(
          FailureCode.conflict, 'Playback session changed while reading cues.');
    }
    return {'sessionId': s.id, ...page};
  }
  @override
  Future<JsonMap> streamOptions(JsonMap input) async =>
      _playback.sources.streamOptions();
  @override
  Future<JsonMap> selectStream(JsonMap input) async =>
      _playback.sources.selectStream(input, origin: commandOrigin());
  @override
  Future<JsonMap> external(JsonMap input) async => notInPlaybackLayer(
      'external_player',
      'Next\'s playback layer does not hand media to an external player yet.');
  @override
  Future<JsonMap> capture(JsonMap input) async => notInPlaybackLayer(
      'capture', 'Next\'s playback layer does not take stills or GIFs yet.');

  @override
  Future<JsonMap> close(JsonMap input) async {
    await _playback.close(reason: commandOrigin() == 'gui' ? 'gui' : 'agent');
    return {'closed': !_playback.hasVideo};
  }

  @override
  Future<JsonMap> authorizeDirectory(JsonMap input) async => {
        'path': await FilePickerService().pickDirectory(
            initialDirectory: input['initialDirectory'] as String?),
      };
}

/// Kernel control (playback.kernel and the rest) is not in the playback
/// layer yet: the kernel is never handed out (I3).
final class SessionKernelHost implements KernelHost {
  SessionKernelHost(this._playback);
  final SessionPlayback _playback;

  static const _message =
      'Next\'s playback layer does not hand out its kernel; kernel reads and changes come later.';

  @override
  Player get player => notInPlaybackLayer('kernel_control', _message);
  @override
  PlayableItem? get request => null;
  @override
  String? get path => _playback.path;
  @override
  ValueListenable<PlaybackMedia> get media => _playback.media;
  @override
  ValueListenable<PlaybackTransport> get transport => _playback.transport;
  @override
  bool get hasVideo => _playback.hasVideo;
  @override
  bool get paused => !_playback.playIntent;
  @override
  Duration get position => _playback.position;
  @override
  double get rate => _playback.rate;
  @override
  List<String> get externalSubtitles => [
        for (final f in _playback.session?.subtitles.files ?? const <SubtitleFile>[])
          f.path
      ];
  @override
  void selectEmbeddedAudio(int index) =>
      notInPlaybackLayer('kernel_control', _message);
  @override
  void subtitleTracksChanged() {}
  @override
  Future<void> addSubtitle(String path, String title) async =>
      notInPlaybackLayer('kernel_control', _message);
  @override
  PlaybackSnapshot snapshot() => _playback.snapshot();
  @override
  JsonMap? error(String sessionId) {
    final s = _playback.session;
    return s == null || s.id != sessionId
        ? null
        : SessionPlayerPort.errorFacts(s);
  }

  @override
  Future<void> reopen(PlayerKernelType? kernel, PlayableItem? request) async =>
      notInPlaybackLayer('kernel_control', _message);
}

/// The subtitle library's and Mesh's target while Next's layer plays: what
/// they offer and put on goes to the session's subtitles, before the media
/// opens (into its open plan) or while it plays. What they put on is
/// theirs (`library_selection`); it is not told back to them as the
/// person's choice.
final class SessionSubtitleTarget implements SubtitleTarget {
  SessionSubtitleTarget(this._playback);
  final SessionPlayback _playback;

  PlaybackSession? get _session {
    final s = _playback.session;
    return s == null || s.phase.value.done ? null : s;
  }

  @override
  String? get path => _session?.path;

  @override
  Future<void> offer(String playbackPath, String title) async =>
      _session?.subtitles.offer(playbackPath, title);

  @override
  Future<void> applyEmbedded(int index) async => _session?.chooseSubtitle(
      SubtitleWant.embedded(index),
      origin: 'library_selection',
      record: false);

  @override
  Future<void> applyExternal(String playbackPath, String title) async =>
      _session?.chooseSubtitle(SubtitleWant.file(playbackPath),
          origin: 'library_selection', record: false, title: title);

  @override
  Future<void> clear() async => _session?.chooseSubtitle(
      const SubtitleWant.off(),
      origin: 'library_selection',
      record: false);

  /// The library's record of the file changed (a subtitle.select, an
  /// import): its files are offered again and its choice put on.
  @override
  Future<void> reapply(
      String fileId, List<JsonMap> tracks, JsonMap? selected) async {
    final s = _session;
    if (s == null) return;
    s.subtitles.withdraw('library');
    for (final track in tracks) {
      if (track['origin'] != 'embedded' && track['available'] == true) {
        s.subtitles.offer(
            track['playbackPath'] as String? ?? track['path'] as String,
            track['title'] as String? ?? '');
      }
    }
    final SubtitleWant want;
    if (selected == null) {
      want = const SubtitleWant.off();
    } else if (selected['origin'] == 'embedded') {
      want = SubtitleWant.embedded(selected['index'] as int);
    } else {
      want = SubtitleWant.file(selected['playbackPath'] as String? ??
          selected['path'] as String);
    }
    // The person's own choice, recorded and told back: it stays theirs.
    final current = s.subtitles.state.value;
    final origin = current.want == want && current.selectedBy != 'default'
        ? current.selectedBy
        : 'library_selection';
    await s.chooseSubtitle(want,
        origin: origin,
        record: false,
        title: selected?['title'] as String?);
  }

  @override
  set loader(Future<bool> Function(String path)? loader) =>
      _playback.host.subtitleLoader = loader;

  @override
  set selection(
          Future<void> Function(String path, int? index, String? external)?
              selection) =>
      _playback.host.subtitleRecorder = selection;
}

/// [capability]'s actions, the same ids and schemas, each unavailable with
/// [message] (what Next's playback layer does not do yet).
final class NotInPlaybackLayer implements Capability {
  NotInPlaybackLayer(Capability capability, String feature, String message)
      : actions = [
          for (final action in capability.actions)
            _NotYet(action, feature, message)
        ];
  @override
  final List<Action> actions;
}

final class _NotYet extends Action<JsonEncodable, JsonEncodable> {
  const _NotYet(this.action, this.feature, this.message);
  final Action action;
  final String feature;
  final String message;
  @override
  ActionSpec get spec => action.spec;
  @override
  JsonEncodable decodeInput(JsonMap input) => action.decodeInput(input);
  @override
  Future<Outcome<JsonEncodable>> run(
          JsonEncodable input, Invocation invocation) async =>
      notInPlaybackLayer(feature, message);
}
