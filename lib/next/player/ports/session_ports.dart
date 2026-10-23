import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/services/file_picker_service.dart';

import '../../capabilities/media_models.dart';
import '../../capabilities/playback_capability.dart';
import '../../capabilities/playback_controls_capability.dart';
import '../../capabilities/playback_inspection.dart';
import '../../capabilities/player_facts.dart';
import '../../danmaku/service.dart';
import '../../danmaku/source.dart' show DanmakuEntry;
import '../../harness_redaction.dart';
import '../../state/change_history.dart';
import '../core/session.dart';
import '../kernel/driver.dart';
import '../next_playback.dart';
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
      canPrevious: false,
      canNext: false,
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
      supportedControls: const ['pause', 'resume', 'seek', 'close', 'wait'],
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
      notInPlaybackLayer('switch_episode',
          'Next\'s playback layer does not switch episodes yet.');
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
        // No countdown runs in Next's playback layer.
        return {'cancelled': false, 'state': _state};
      case 'playback.retry':
        notInPlaybackLayer('retry',
            'Next\'s playback layer does not retry yet; open the path again with playback.open.');
      case 'playback.chapters':
      case 'playback.navigate':
        notInPlaybackLayer('chapters',
            'Next\'s playback layer does not read chapters, step frames or skip segments yet.');
      case 'playback.playlist':
        notInPlaybackLayer('playlist',
            'Next\'s playback layer does not keep a playlist yet.');
      case 'subtitle.cues':
        notInPlaybackLayer('subtitles',
            'Next\'s playback layer does not present subtitles yet.');
      case 'danmaku.entries':
        notInPlaybackLayer('danmaku',
            'Next\'s playback layer does not present danmaku yet.');
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
      'danmakuRenderer': null,
    };
  }

  static const _tracks =
      'Next\'s playback layer does not list or select tracks, or mount subtitle files, yet.';
  static const _streams =
      'Next\'s playback layer plays local files only; stream versions and quality come with network sources.';

  @override
  Future<JsonMap> tracks(JsonMap input) async =>
      notInPlaybackLayer('tracks', _tracks);
  @override
  Future<JsonMap> selectTrack(JsonMap input) async =>
      notInPlaybackLayer('tracks', _tracks);
  @override
  Future<JsonMap> loadSubtitle(JsonMap input) async =>
      notInPlaybackLayer('tracks', _tracks);
  @override
  Future<JsonMap> removeSubtitle(JsonMap input) async =>
      notInPlaybackLayer('tracks', _tracks);
  @override
  Future<JsonMap> streamOptions(JsonMap input) async =>
      notInPlaybackLayer('streams', _streams);
  @override
  Future<JsonMap> selectStream(JsonMap input) async =>
      notInPlaybackLayer('streams', _streams);
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
  List<String> get externalSubtitles => const [];
  @override
  void selectEmbeddedAudio(int index) =>
      notInPlaybackLayer('kernel_control', _message);
  @override
  void subtitleTracksChanged() {}
  @override
  Future<void> addSubtitle(String path, String title) async =>
      notInPlaybackLayer('tracks', SessionControls._tracks);
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

/// The subtitle library's target while Next's layer plays: subtitles are
/// not presented yet, so nothing is offered or put on.
final class SessionSubtitleTarget implements SubtitleTarget {
  SessionSubtitleTarget(this._playback);
  final SessionPlayback _playback;

  @override
  String? get path => _playback.path;
  @override
  Future<void> offer(String playbackPath, String title) async =>
      notInPlaybackLayer('subtitles', SessionControls._tracks);
  @override
  Future<void> applyEmbedded(int index) async =>
      notInPlaybackLayer('subtitles', SessionControls._tracks);
  @override
  Future<void> applyExternal(String playbackPath, String title) async =>
      notInPlaybackLayer('subtitles', SessionControls._tracks);
  @override
  Future<void> clear() async =>
      notInPlaybackLayer('subtitles', SessionControls._tracks);
  @override
  Future<void> reapply(
          String fileId, List<JsonMap> tracks, JsonMap? selected) async {}
  @override
  set loader(Future<bool> Function(String path)? loader) {}
  @override
  set selection(
      Future<void> Function(String path, int? index, String? external)?
          selection) {}
}

/// Danmaku are not presented by Next's layer yet: no target, nothing
/// installed.
final class SessionDanmakuPort implements PlaybackDanmakuPort {
  @override
  DanmakuPlaybackTarget? get target => null;
  @override
  Set<String> get managedTracks => const {};
  @override
  JsonMap? loaded(String bindingId) => null;
  @override
  bool install(DanmakuPlaybackTarget target, JsonMap binding,
          List<DanmakuEntry> entries,
          {int startMs = 0, int? endMs}) =>
      false;
  @override
  void remove(String bindingId) {}
  @override
  List<JsonMap> get registry => const [];
  @override
  bool reuse(DanmakuPlaybackTarget target, JsonMap binding) => false;
  @override
  Future<bool> restoreClassic(
          DanmakuPlaybackTarget target, JsonMap binding) async =>
      false;
  @override
  bool updateTrack(
          DanmakuPlaybackTarget target, String trackId, JsonMap properties) =>
      false;
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
