import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:path/path.dart' as p;

import '../../harness_redaction.dart';
import '../kernel/driver.dart';
import '../perf/budget.dart';
import '../progress/records.dart';
import '../subtitles/controller.dart';
import '../subtitles/cue_index.dart';
import '../subtitles/look.dart';
import 'arbiter.dart';
import 'clock.dart';

/// Where a session is (player-core design §2.1).
enum SessionPhase {
  resolving,
  starting,
  loading,
  preparing,
  active,
  failed,
  closing,
  closed;

  /// The media is open in the kernel: there is a picture and a length.
  bool get open => this == preparing || this == active;
  bool get done => this == closing || this == closed;
}

/// What is asked to play.
@immutable
final class MediaRequest {
  const MediaRequest({
    required this.locator,
    required this.origin,
    this.title,
    this.episodeTitle,
    this.animeId,
    this.episodeId,
    this.start,
    this.paused,
  });

  /// A local path (P1); what playback.open's path names.
  final String locator;

  /// gui, agent, classic_redirect, download…
  final String origin;
  final String? title;
  final String? episodeTitle;
  final int? animeId;
  final int? episodeId;

  /// Where to start; null: where it was left.
  final Duration? start;

  /// Asked to open paused.
  final bool? paused;

  /// The same request for [path] (a file URL resolved to its path).
  MediaRequest withLocator(String path) => path == locator
      ? this
      : MediaRequest(
          locator: path,
          origin: origin,
          title: title,
          episodeTitle: episodeTitle,
          animeId: animeId,
          episodeId: episodeId,
          start: start,
          paused: paused);

  JsonMap toJson() => {
        'path': redactHarnessText(locator),
        'origin': origin,
        'startMs': start?.inMilliseconds,
        'paused': paused,
      };
}

/// Play and pause as asked ([playIntent], changed the moment a command
/// comes) and as the kernel says ([observed], changed only by the kernel).
/// The play button reads the intent; the timeline and Nipa's facts the
/// observation.
@immutable
final class Transport {
  const Transport({
    required this.playIntent,
    required this.intentBy,
    this.observed = KernelTransport.stopped,
    this.observedAt,
    this.buffering = false,
    this.seekTarget,
    this.rate = 1,
    this.volume = 1,
    this.ended = false,
  });

  final bool playIntent;
  final String intentBy;
  final KernelTransport observed;
  final DateTime? observedAt;
  final bool buffering;

  /// While a seek is under way.
  final Duration? seekTarget;
  final double rate;
  final double volume;
  final bool ended;

  Transport copyWith({
    bool? playIntent,
    String? intentBy,
    KernelTransport? observed,
    DateTime? observedAt,
    bool? buffering,
    Duration? Function()? seekTarget,
    double? rate,
    double? volume,
    bool? ended,
  }) =>
      Transport(
        playIntent: playIntent ?? this.playIntent,
        intentBy: intentBy ?? this.intentBy,
        observed: observed ?? this.observed,
        observedAt: observedAt ?? this.observedAt,
        buffering: buffering ?? this.buffering,
        seekTarget: seekTarget == null ? this.seekTarget : seekTarget(),
        rate: rate ?? this.rate,
        volume: volume ?? this.volume,
        ended: ended ?? this.ended,
      );

  JsonMap toJson() => {
        'paused': {
          'intent': !playIntent,
          'intentBy': intentBy,
          'observed': observed.name,
          'observedAt': observedAt?.toIso8601String(),
          'source': 'kernel',
        },
        'buffering': buffering,
        'seekTargetMs': seekTarget?.inMilliseconds,
        'rate': rate,
        'volume': volume,
        'ended': ended,
      };

  @override
  bool operator ==(Object other) =>
      other is Transport &&
      other.playIntent == playIntent &&
      other.intentBy == intentBy &&
      other.observed == observed &&
      other.observedAt == observedAt &&
      other.buffering == buffering &&
      other.seekTarget == seekTarget &&
      other.rate == rate &&
      other.volume == volume &&
      other.ended == ended;

  @override
  int get hashCode => Object.hash(playIntent, intentBy, observed, observedAt,
      buffering, seekTarget, rate, volume, ended);
}

/// Why a session failed: the step ([stage], as playback.failures names
/// them) and the kernel's own words.
@immutable
final class PlaybackFault {
  PlaybackFault(this.stage, this.message, {this.code, this.retryable})
      : at = DateTime.now().toUtc();
  final String stage;
  final String message;
  final int? code;
  final bool? retryable;
  final DateTime at;

  JsonMap toJson() => {
        'stage': stage,
        'message': redactHarnessText(message),
        'code': code,
        'kernelRetryable': retryable,
        'at': at.toIso8601String(),
      };
}

/// How a command ended: applied (the kernel confirmed it), pending (not
/// confirmed in time, or waiting for the media to open), superseded (a
/// later one replaced it), rejected (the kernel turned it away) or
/// session_closed.
@immutable
final class CommandReceipt {
  const CommandReceipt(this.seq, this.command, this.outcome, [this.detail]);
  final int seq;
  final String command;
  final String outcome;
  final JsonMap? detail;
  bool get applied => outcome == 'applied';

  JsonMap toJson() =>
      {'seq': seq, 'command': command, 'outcome': outcome, ...?detail};
}

/// What happened in a session, in order: phase, transport, seek_requested,
/// seek_settled, started, ended, failed, progress_saved, closed.
@immutable
final class PlaybackEvent {
  PlaybackEvent(this.sessionId, this.seq, this.kind, this.data)
      : at = DateTime.now().toUtc();
  final String sessionId;
  final int seq;
  final String kind;
  final JsonMap data;
  final DateTime at;

  JsonMap toJson() => {
        'sessionId': sessionId,
        'seq': seq,
        'kind': kind,
        'at': at.toIso8601String(),
        ...data,
      };
}

/// The shared player settings a session opens with (D3).
@immutable
final class PlayerLevels {
  const PlayerLevels({this.volume = 1, this.boost = 1, this.rate = 1});
  final double volume;
  final double boost;
  final double rate;
}

/// What a session needs from its host.
final class SessionDeps {
  SessionDeps({
    required this.arbiter,
    required this.createDriver,
    required this.records,
    required this.levels,
    CueCache? cues,
    this.look = const SubtitleLook(),
    OverlayPlacement Function(String path)? placementOf,
    this.subtitleLoader,
    this.subtitleRecorder,
  })  : cues = cues ?? CueCache(),
        placementOf = placementOf ?? ((_) => const OverlayPlacement());
  final KernelArbiter arbiter;
  final Future<KernelDriver> Function(KernelLease lease) createDriver;
  final PlaybackRecords records;
  final PlayerLevels levels;
  final CueCache cues;
  final SubtitleLook look;
  final OverlayPlacement Function(String path) placementOf;

  /// The subtitle library's, read when the plan asks (it attaches and
  /// detaches as Next's interface opens and closes).
  final SubtitleLoader? Function()? subtitleLoader;
  final SubtitleRecorder? Function()? subtitleRecorder;
}

/// The audio track: the one asked for (null: the kernel's own first), who
/// asked, and what the kernel reported.
@immutable
final class AudioTrackState {
  const AudioTrackState(
      {this.want, this.selectedBy = 'default', this.kernel, this.confirmed = false});
  final int? want;
  final String selectedBy;
  final int? kernel;
  final bool confirmed;

  JsonMap toJson() => {
        'selected': want,
        'selectedBy': selectedBy,
        'kernel': kernel,
        'confirmed': confirmed,
      };

  @override
  bool operator ==(Object other) =>
      other is AudioTrackState &&
      other.want == want &&
      other.selectedBy == selectedBy &&
      other.kernel == kernel &&
      other.confirmed == confirmed;
  @override
  int get hashCode => Object.hash(want, selectedBy, kernel, confirmed);
}

final class _Closed implements Exception {
  const _Closed();
}

/// One playback, from open to close (player-core design §1.3, §2): its own
/// kernel instance (I6), the open plan (§2.3), intent and observation
/// (§2.2), the clock, progress and the watch record.
///
/// Everything here runs on the main isolate in O(1) per event; the kernel
/// is reached only through its driver's queue.
final class PlaybackSession {
  PlaybackSession(this.id, this.request, this._source, this._deps)
      : openedAt = DateTime.now().toUtc(),
        clock = PlaybackClock(position: request.start ?? Duration.zero),
        _transport = ValueNotifier(Transport(
          playIntent: request.paused != true,
          intentBy: 'open',
          volume: _deps.levels.volume,
          rate: _deps.levels.rate,
        ));

  /// Saved while it plays this often, and at pause, seek, end and close.
  static const saveEvery = Duration(seconds: 5);

  /// The watch record is written at every second save.
  static const recordEvery = 2;

  final String id;
  final MediaRequest request;
  final ResolvedSource _source;
  ResolvedSource get source => _source;
  final SessionDeps _deps;
  final DateTime openedAt;
  final PlaybackClock clock;

  final _phase = ValueNotifier(SessionPhase.resolving);
  final ValueNotifier<Transport> _transport;
  final _media = ValueNotifier<MediaFacts?>(null);
  final _audio = ValueNotifier(const AudioTrackState());

  /// The subtitles: what is chosen, what shows, the overlay's line.
  late final SubtitleController subtitles = SubtitleController(
    clock: clock,
    cues: _deps.cues,
    look: _deps.look,
    placementOf: _deps.placementOf,
    recorderOf: () => _deps.subtitleRecorder?.call(),
  )..mediaPath = request.locator;

  /// The audio track asked for and as the kernel reported it.
  ValueListenable<AudioTrackState> get audio => _audio;
  final _fault = ValueNotifier<PlaybackFault?>(null);
  final _surface = ValueNotifier<VideoSurface?>(null);
  final _events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final _phaseTimes = <String, int>{};
  final _watch = Stopwatch()..start();

  KernelDriver? _driver;
  KernelLease? _lease;
  StreamSubscription<KernelEvent>? _kernelEvents;
  WatchHistoryItem? _record;
  Duration _start = Duration.zero;
  bool _startMoved = false;
  Duration? _landed;
  int _eventSeq = 0;
  int _commandSeq = 0;
  bool _started = false;
  Future<void>? _closing;
  Timer? _saver;
  int _saves = 0;
  Future<void> _writes = Future.value();
  JsonMap? _lastSave;

  /// Source-owned work (final remote progress and transcode teardown) is
  /// drained before a replacement session can start. No native access.
  Future<void> Function()? closeSource;

  ValueListenable<SessionPhase> get phase => _phase;
  ValueListenable<Transport> get transport => _transport;
  ValueListenable<MediaFacts?> get media => _media;
  ValueListenable<PlaybackFault?> get fault => _fault;
  ValueListenable<VideoSurface?> get surface => _surface;
  Stream<PlaybackEvent> get events => _events.stream;
  KernelDriver? get driver => _driver;
  String get path => request.locator;

  /// What the watch record knows of the media when it opened.
  WatchHistoryItem? get record => _record;
  Duration get duration => _media.value?.duration ?? Duration.zero;

  /// Where the video is, never asked of the kernel.
  Duration get position => clock.now();

  /// The open plan finished: active, failed or closed.
  Future<void> get opened => _opened.future;
  final _opened = Completer<void>();

  void _emit(String kind, [JsonMap data = const {}]) {
    if (_events.isClosed) return;
    _events.add(PlaybackEvent(id, ++_eventSeq, kind, data));
  }

  void _setPhase(SessionPhase phase) {
    if (_phase.value == phase) return;
    _phaseTimes[phase.name] = _watch.elapsedMilliseconds;
    _phase.value = phase;
    _emit('phase', {'phase': phase.name});
  }

  void _setTransport(Transport next) {
    if (next == _transport.value) return;
    _transport.value = next;
  }

  void _check() {
    if (_phase.value.done) throw const _Closed();
  }

  /// Closed while the kernel was being made: what was made goes at once.
  Future<void> _checkOrRelease() async {
    if (!_phase.value.done) return;
    await _releaseKernel();
    throw const _Closed();
  }

  // ---- the open plan (§2.3) ----

  /// Runs the plan; completes [opened] at its end, whatever the end.
  Future<void> start() async {
    try {
      await _plan();
    } on _Closed {
      // Closed while opening: the close tears down what was made.
    } on KernelFenced {
      // Released underneath (closing).
    } on KernelOpenFailure catch (e) {
      await _fail(e.stage, e.message, code: e.code);
    } catch (error) {
      await _fail('initialize', '$error');
    } finally {
      if (!_opened.isCompleted) _opened.complete();
    }
  }

  Future<void> _plan() async {
    final path = _source.locator;
    // resolving: the file, its record and where it was left.
    if (_source.kind == 'local' && !await File(path).exists()) {
      throw const KernelOpenFailure(
          'file_check', 'The local file does not exist or is inaccessible.');
    }
    _check();
    final records = _deps.records;
    try {
      _record = await records.record(path);
    } catch (error) {
      debugPrint('[NextPlayer] watch record of the media: $error');
    }
    _check();
    var start = request.start;
    if (start == null) {
      try {
        start = Duration(milliseconds: await records.resumeAt(path));
      } catch (error) {
        debugPrint('[NextPlayer] resume position: $error');
        start = Duration.zero;
      }
    }
    _check();
    // A seek asked meanwhile moved it already.
    if (!_startMoved) {
      _start = start;
      clock.anchor(start, advancing: false, source: 'seek_target');
    }
    // …and its subtitles, as the subtitle library has them (it offers its
    // files and puts its choice on, into the open plan).
    final planWatch = Stopwatch()..start();
    await subtitles.loadFrom(_deps.subtitleLoader?.call(), path);
    _phaseTimes['subtitlePlanMs'] = planWatch.elapsedMilliseconds;
    _check();
    // starting: the lease, then a kernel instance of its own.
    _setPhase(SessionPhase.starting);
    _lease = await _deps.arbiter
        .acquire(KernelOwner.next, reason: 'session $id');
    await _checkOrRelease();
    final driver = _driver = await _deps.createDriver(_lease!);
    _kernelEvents = driver.events.listen(_kernel);
    driver.surface.addListener(_surfaceChanged);
    await _checkOrRelease();
    // loading: open at the start position, paused, the tracks set first.
    _setPhase(SessionPhase.loading);
    final t = _transport.value;
    final audioPlanned = _audio.value.want;
    final plan = subtitles.openPlan(audio: audioPlanned);
    _openPlan = plan;
    final opened = await driver.open(_source,
        start: _start, volume: t.volume * _boost, rate: t.rate, tracks: plan);
    _check();
    _landed = opened.landed;
    _media.value = opened.media;
    clock.limit = opened.media.duration;
    clock.anchor(opened.landed, advancing: false, source: 'kernel_open');
    _tracksReported(opened.tracks);
    // preparing: what the open could not set (a choice made meanwhile, a
    // track the media does not have), confirmed by the kernel…
    _setPhase(SessionPhase.preparing);
    await subtitles.opened(driver, opened.media);
    _check();
    if (_audio.value.want case final want? when want != audioPlanned) {
      await driver.selectAudio(want);
      _check();
    }
    // …the position the media was asked to open at…
    for (var attempt = 0;
        attempt < 3 && (clock.now() - _start).abs() > const Duration(seconds: 1);
        attempt++) {
      final outcome = await driver.seek(_start);
      _check();
      if (outcome.landed case final landed?) {
        clock.anchor(landed, advancing: false, source: 'seek_landed');
      }
    }
    _saveRecord(publish: true);
    // …then what was asked meanwhile: play or stay paused.
    for (var attempt = 0; attempt < 3; attempt++) {
      final want = _transport.value.playIntent;
      if (want == (_transport.value.observed == KernelTransport.playing)) break;
      await driver.setPaused(!want);
      _check();
    }
    // Staying paused, the picture is the frame it opened at, not black.
    if (!_transport.value.playIntent) {
      await driver.presentFrame();
      _check();
    }
    _setPhase(SessionPhase.active);
    _syncSaver();
  }

  Future<void> _fail(String stage, String message, {int? code}) async {
    if (_phase.value.done) return;
    _fault.value = PlaybackFault(stage, message, code: code);
    _setPhase(SessionPhase.failed);
    _emit('failed', {'stage': stage, 'message': redactHarnessText(message)});
    // A failed session keeps no kernel, and draws nothing.
    subtitles.close();
    await _releaseKernel();
    await closeSource?.call();
  }

  // ---- what the kernel says, reduced (O(1) each) ----

  void _kernel(KernelEvent event) => PlayerPerf.span('session.kernel', () {
        if (_phase.value.done) return;
        switch (event) {
          case KernelTransportChanged(:final transport):
            _setTransport(_transport.value.copyWith(
                observed: transport, observedAt: DateTime.now().toUtc()));
            _emit('transport', {'observed': transport.name});
            if (transport == KernelTransport.playing && !_started) {
              _started = true;
              _emit('started', {'positionMs': clock.now().inMilliseconds});
            }
            if (transport != KernelTransport.playing &&
                _phase.value == SessionPhase.active) {
              _save('paused');
            }
            _syncSaver();
          case KernelPositionSample(:final position, :final rate, :final advancing):
            // A seek keeps its target; EOF keeps the endpoint even if the
            // native stream subsequently reports a reset position (HLS).
            if (_transport.value.seekTarget != null || _transport.value.ended) {
              return;
            }
            clock.anchor(position,
                advancing: advancing, rate: rate, source: 'kernel_sample');
          case KernelBuffering(:final buffering):
            _setTransport(_transport.value.copyWith(buffering: buffering));
          case KernelEnded(:final inferred):
            clock.anchor(duration > Duration.zero ? duration : position,
                advancing: false, source: 'kernel_ended');
            _setTransport(_transport.value.copyWith(ended: true));
            _emit('ended', {'inferred': inferred});
            _save('ended');
          case KernelFailed(:final stage, :final message, :final retryable):
            _fault.value = PlaybackFault(stage, message, retryable: retryable);
            _emit('failed', {'stage': stage, 'message': redactHarnessText(message)});
          case KernelTracksChanged(:final tracks):
            _tracksReported(tracks);
        }
      });

  void _tracksReported(KernelTracks tracks) {
    final a = _audio.value;
    _audio.value = AudioTrackState(
        want: a.want,
        selectedBy: a.selectedBy,
        kernel: tracks.audio,
        confirmed: tracks.audioConfirmed);
    subtitles.kernelReported(tracks);
    _emit('tracks', tracks.toJson());
  }

  void _surfaceChanged() => _surface.value = _driver?.surface.value;

  // ---- commands (§2.2): the intent at once, the receipt once confirmed ----

  bool get _commandable =>
      _phase.value == SessionPhase.active && _driver != null;

  CommandReceipt _receipt(int seq, String command, String outcome,
          [JsonMap? detail]) =>
      CommandReceipt(seq, command, outcome, detail);

  Future<CommandReceipt> setPaused(bool paused, {required String origin}) async {
    final seq = ++_commandSeq;
    if (_phase.value.done) return _receipt(seq, 'set_paused', 'session_closed');
    _setTransport(
        _transport.value.copyWith(playIntent: !paused, intentBy: origin));
    // While opening the plan applies the intent at its end.
    if (!_commandable) return _receipt(seq, 'set_paused', 'pending');
    try {
      final observed = await _driver!.setPaused(paused);
      final want = paused ? KernelTransport.paused : KernelTransport.playing;
      return _receipt(seq, 'set_paused', observed == want ? 'applied' : 'pending',
          {'observed': observed.name});
    } on KernelFenced {
      return _receipt(seq, 'set_paused', 'session_closed');
    }
  }

  void togglePlay({required String origin}) =>
      unawaited(setPaused(_transport.value.playIntent, origin: origin));

  Future<CommandReceipt> seek(Duration to,
      {required String origin, bool exact = true}) async {
    final seq = ++_commandSeq;
    if (_phase.value.done) return _receipt(seq, 'seek', 'session_closed');
    final length = duration;
    var target = to < Duration.zero ? Duration.zero : to;
    if (length > Duration.zero && target > length) target = length;
    _setTransport(_transport.value
        .copyWith(seekTarget: () => target, ended: false));
    clock.anchor(target, advancing: false, source: 'seek_target');
    _emit('seek_requested',
        {'targetMs': target.inMilliseconds, 'origin': origin});
    final driver = _driver;
    if (!_phase.value.open || driver == null) {
      // Not open yet: the plan opens there.
      _start = target;
      _startMoved = true;
      _setTransport(_transport.value.copyWith(seekTarget: () => null));
      return _receipt(seq, 'seek', 'pending', {'targetMs': target.inMilliseconds});
    }
    final SeekOutcome outcome;
    try {
      outcome = await driver.seek(target, exact: exact);
    } on KernelFenced {
      return _receipt(seq, 'seek', 'session_closed');
    }
    if (outcome.result == SeekResult.superseded) {
      return _receipt(seq, 'seek', 'superseded');
    }
    final current = _transport.value;
    if (current.seekTarget == target) {
      _setTransport(current.copyWith(seekTarget: () => null));
    }
    final playing = current.observed == KernelTransport.playing;
    final landed = outcome.landed;
    clock.anchor(landed ?? target,
        advancing: playing,
        source: landed == null ? 'seek_rejected' : 'seek_landed');
    _emit('seek_settled', {
      'targetMs': target.inMilliseconds,
      'landedMs': landed?.inMilliseconds,
      'result': outcome.result.name,
    });
    if (landed != null) _save('seek');
    return _receipt(
        seq,
        'seek',
        outcome.result == SeekResult.done ? 'applied' : 'rejected',
        {
          'targetMs': target.inMilliseconds,
          'landedMs': landed?.inMilliseconds,
          if (outcome.code != null) 'kernelCode': outcome.code,
        });
  }

  Future<CommandReceipt> setRate(double rate, {required String origin}) async {
    final seq = ++_commandSeq;
    if (_phase.value.done) return _receipt(seq, 'set_rate', 'session_closed');
    _setTransport(_transport.value.copyWith(rate: rate));
    if (!_commandable) return _receipt(seq, 'set_rate', 'pending');
    try {
      await _driver!.setRate(rate);
      return _receipt(seq, 'set_rate', 'applied');
    } on KernelFenced {
      return _receipt(seq, 'set_rate', 'session_closed');
    }
  }

  Future<CommandReceipt> setVolume(double volume,
      {required String origin, double? boost}) async {
    final seq = ++_commandSeq;
    if (_phase.value.done) return _receipt(seq, 'set_volume', 'session_closed');
    _setTransport(_transport.value.copyWith(volume: volume));
    if (boost != null) _boost = boost;
    if (!_commandable) return _receipt(seq, 'set_volume', 'pending');
    try {
      await _driver!.setVolume(volume * _boost);
      return _receipt(seq, 'set_volume', 'applied');
    } on KernelFenced {
      return _receipt(seq, 'set_volume', 'session_closed');
    }
  }

  late double _boost = _deps.levels.boost;
  double get volumeBoost => _boost;

  KernelTrackPlan? _openPlan;

  /// Puts on audio track [index]: the intent at once; applied once the
  /// kernel reports it. Before the media opens it goes into the open plan.
  Future<CommandReceipt> selectAudio(int index, {required String origin}) async {
    final seq = ++_commandSeq;
    if (_phase.value.done) return _receipt(seq, 'select_track', 'session_closed');
    final a = _audio.value;
    _audio.value = AudioTrackState(
        want: index, selectedBy: origin, kernel: a.kernel, confirmed: a.confirmed);
    if (!_phase.value.open || _driver == null) {
      return _receipt(seq, 'select_track', 'pending', {'kind': 'audio', 'index': index});
    }
    try {
      final tracks = await _driver!.selectAudio(index);
      return _receipt(
          seq,
          'select_track',
          tracks.audio == index && tracks.audioConfirmed ? 'applied' : 'pending',
          {'kind': 'audio', 'index': index, 'kernel': tracks.toJson()});
    } on KernelFenced {
      return _receipt(seq, 'select_track', 'session_closed');
    }
  }

  /// Puts [want] on screen and nothing else (the invariant). [record]: the
  /// subtitle library keeps it for the next open (the receipt says whether
  /// it did); false: it holds for this playback only. [fromLibrary]: the
  /// library's own record put on.
  Future<CommandReceipt> chooseSubtitle(SubtitleWant want,
      {required String origin,
      bool record = true,
      bool fromLibrary = false,
      String? title}) async {
    final seq = ++_commandSeq;
    if (_phase.value.done) return _receipt(seq, 'select_track', 'session_closed');
    final (:state, :remembered) = await subtitles.choose(want,
        by: origin, record: record, fromLibrary: fromLibrary, title: title);
    if (_phase.value.done) return _receipt(seq, 'select_track', 'session_closed');
    final presented = state.presented;
    final String outcome;
    if (!_phase.value.open) {
      outcome = 'pending';
    } else if (state.want != want) {
      outcome = 'superseded';
    } else if (state.failure != null && !want.off) {
      outcome = 'rejected';
    } else if (want.off
        ? presented.isEmpty
        : presented.length == 1 &&
            presented.single.want == want &&
            presented.single.confirmed) {
      outcome = 'applied';
    } else {
      outcome = 'pending';
    }
    return _receipt(seq, 'select_track', outcome, {
      'kind': 'subtitle',
      'selected': want.toJson(),
      'presented': [for (final p in presented) p.toJson()],
      'remembered': remembered,
      if (state.failure != null) 'failure': state.failure,
    });
  }

  // ---- progress and the watch record (§4.2) ----

  void _syncSaver() {
    final playing = _phase.value == SessionPhase.active &&
        _transport.value.observed == KernelTransport.playing;
    if (playing == (_saver != null)) return;
    _saver?.cancel();
    _saver = playing ? Timer.periodic(saveEvery, (_) => _save('timer')) : null;
  }

  /// Where it is now, or 0 once it ended (as Classic keeps it: the next
  /// open starts from the beginning).
  int get _resumeMs => _transport.value.ended
      ? 0
      : (_transport.value.seekTarget ?? clock.now()).inMilliseconds;

  void _save(String why, {bool publish = false}) {
    if (!_phase.value.open && !(_phase.value == SessionPhase.closing && _landed != null)) {
      return;
    }
    final position = _transport.value.seekTarget ?? clock.now();
    final resume = _resumeMs;
    final record = ++_saves % recordEvery == 0 || why != 'timer';
    final path = _source.locator;
    final records = _deps.records;
    final item = record ? _item(position) : null;
    _writes = _writes.then((_) async {
      try {
        await records.savePosition(path, resume);
        if (item != null) await records.saveRecord(item, publish: publish);
        _lastSave = {
          'why': why,
          'positionMs': resume,
          'record': item != null,
          'at': DateTime.now().toUtc().toIso8601String(),
        };
        _emit('progress_saved', {'why': why, 'positionMs': resume});
      } catch (error) {
        debugPrint('[NextPlayer] progress ($why): $error');
      }
    });
  }

  void _saveRecord({required bool publish}) {
    final item = _item(clock.now());
    final records = _deps.records;
    _writes = _writes.then((_) async {
      try {
        await records.saveRecord(item, publish: publish);
      } catch (error) {
        debugPrint('[NextPlayer] watch record: $error');
      }
    });
  }

  WatchHistoryItem _item(Duration position) {
    final known = _record;
    final length = duration.inMilliseconds;
    final ended = _transport.value.ended;
    final at = ended && length > 0 ? length : position.inMilliseconds;
    return WatchHistoryItem(
      filePath: known?.filePath ?? _source.locator,
      animeName: known?.animeName ??
          request.title ??
          p.basenameWithoutExtension(_source.locator),
      episodeTitle: known?.episodeTitle ?? request.episodeTitle,
      animeId: known?.animeId ?? request.animeId,
      episodeId: known?.episodeId ?? request.episodeId,
      watchProgress: length > 0 ? (at / length).clamp(0.0, 1.0) : 0,
      lastPosition: at,
      duration: length,
      lastWatchTime: DateTime.now(),
      thumbnailPath: known?.thumbnailPath,
      isFromScan: known?.isFromScan ?? false,
      videoHash: known?.videoHash,
      mediaKey: known?.mediaKey,
    );
  }

  // ---- close (§2.1, I4) ----

  /// Saves where it is, releases the kernel and gives back the lease.
  /// Idempotent.
  Future<void> close({required String reason}) =>
      _closing ??= _close(reason);

  Future<void> _close(String reason) async {
    final wasOpen = _phase.value.open;
    _saver?.cancel();
    _saver = null;
    // Nothing more is drawn over the video or asked of the kernel's tracks
    // (none change while it stops).
    subtitles.close();
    clock.anchor(position, advancing: false, source: 'session_close');
    if (wasOpen) {
      // The last word on progress, before the kernel goes.
      _setPhase(SessionPhase.closing);
      _save('close', publish: true);
    } else {
      _setPhase(SessionPhase.closing);
    }
    final watch = Stopwatch()..start();
    await _releaseKernel();
    final releaseMs = watch.elapsedMilliseconds;
    // The plan ends on the fence; anything it made after the release above
    // it releases itself before it ends.
    await _opened.future;
    await _releaseKernel();
    await _writes;
    try {
      await closeSource?.call();
    } catch (error) {
      _emit('source_report_failed', {'error': error.runtimeType.toString()});
    }
    _setPhase(SessionPhase.closed);
    _emit('closed', {'reason': reason, 'releaseMs': releaseMs});
    if (!_opened.isCompleted) _opened.complete();
    await _events.close();
  }

  /// The kernel instance, then the lease (I4 ⑥). Safe to call again: it
  /// releases what is there now.
  Future<void> _releaseKernel() async {
    final driver = _driver;
    final lease = _lease;
    if (driver != null) {
      driver.surface.removeListener(_surfaceChanged);
      _surface.value = null;
      await driver.release();
      await _kernelEvents?.cancel();
    }
    if (lease != null && lease.held) await lease.release();
  }

  // ---- facts ----

  /// O(1): what Nipa and the interface read of this session.
  JsonMap facts() => {
        'sessionId': id,
        'phase': _phase.value.name,
        'openedAt': openedAt.toIso8601String(),
        'phaseTimesMs': Map.of(_phaseTimes),
        'request': request.toJson(),
        'startMs': _start.inMilliseconds,
        'landedMs': _landed?.inMilliseconds,
        'position': {
          'ms': clock.now().inMilliseconds,
          'source': clock.source,
          'advancing': clock.advancing,
        },
        'durationMs': duration.inMilliseconds,
        'transport': _transport.value.toJson(),
        'tracks': {
          'openPlan': _openPlan?.toJson(),
          'kernel': _driver?.tracks.toJson(),
          'audio': _audio.value.toJson(),
          'subtitles': subtitles.facts(),
        },
        'fault': _fault.value?.toJson(),
        'lastSave': _lastSave,
        'lease': _lease?.id,
      };
}
