import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/abstract_player.dart'
    show PlayerNativeLogTap;
import 'package:nipaplay/player_abstraction/player_data_models.dart';

import '../core/arbiter.dart';
import '../core/clock.dart';
import '../features/kernel_features.dart' show ChapterFacts;
import 'driver.dart';
import 'instances.dart';
import 'op_queue.dart';

/// I1: only the lease holder makes a kernel. Called before anything native
/// is made, so a refused instance leaves nothing behind.
void requireLease(KernelLease lease, String kernel) {
  if (!lease.held || lease.owner != KernelOwner.next) {
    throw StateError('A $kernel instance is made only under Next\'s lease.');
  }
}

/// What the three kernels that play through a NipaPlay adapter (Media Kit,
/// Erika, video_player) share as a [KernelDriver]: the queue, the fence,
/// the order of opening and of release, and how the kernel's own words
/// become [KernelEvent]s. What differs (how each opens a media, seeks,
/// pauses, draws, lists tracks and goes away) is the subclass's.
///
/// One native player per instance, made with the driver and deleted by it,
/// never reused (I5, I6). Every call into the kernel runs in the queue (I8)
/// and looks at the fence after each await (I2); nothing reaches the
/// interface but [surface] (I3).
abstract class AdapterDriver implements KernelDriver {
  AdapterDriver(this.config) : instance = nextKernelInstance();

  /// A sample this far from where the last one runs on to is sent.
  static const driftLimit = Duration(milliseconds: 40);

  /// The kernel must have opened the media within this.
  static const openTimeout = Duration(seconds: 20);
  static const seekTimeout = Duration(seconds: 5);
  static const stepTimeout = Duration(seconds: 3);

  @override
  final int instance;
  @override
  final KernelConfig config;

  @protected
  final queue = KernelOpQueue();

  @override
  bool get fenced => queue.fenced;
  @override
  Stream<KernelEvent> get events => _events.stream;
  @override
  ValueListenable<VideoSurface?> get surface => _surface;
  @protected
  set picture(VideoSurface? value) => _surface.value = value;

  final _events = StreamController<KernelEvent>.broadcast(sync: true);
  final _surface = ValueNotifier<VideoSurface?>(null);
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _transportWaiters = <(KernelTransport, Completer<KernelTransport>)>[];
  final _times = <String, int>{};
  final _trackLog = <JsonMap>[];
  final _releaseTimeouts = <String>[];
  final _watch = Stopwatch()..start();
  int _seq = 0;
  int _late = 0;
  int _seekTicket = 0;
  bool _openStarted = false;
  bool _endSent = false;
  Future<void>? _release;
  Completer<Duration?>? _sampleWaiter;
  Duration _sampleNear = Duration.zero;

  /// The last position the kernel gave, drift or not.
  @protected
  Duration lastKnownPosition = Duration.zero;

  /// What the kernel has said last.
  @protected
  KernelTransport observed = KernelTransport.stopped;
  @protected
  double rate = 1;
  @protected
  bool opened = false;
  @protected
  Duration duration = Duration.zero;
  @protected
  MediaFacts? media;
  Duration _sampleAt = Duration.zero;
  Duration _samplePosition = Duration.zero;

  Duration get _now => PlayerTime.now();

  @protected
  void listen<T>(Stream<T> stream, void Function(T) handle) =>
      _subscriptions.add(stream.listen((value) {
        if (fenced) {
          _late++;
          return;
        }
        handle(value);
      }));

  // ---- what the kernel says, as events ----

  void _emit(KernelEvent Function(int seq, Duration at) make) {
    if (fenced || _events.isClosed) return;
    _events.add(make(++_seq, _now));
  }

  /// The kernel plays, paused or stopped. A change is sent once.
  @protected
  void transportChanged(KernelTransport transport) {
    if (fenced) {
      _late++;
      return;
    }
    if (transport == observed) return;
    // Where it was running to, before the course changes.
    final position = _samplePosition + _since;
    observed = transport;
    _emit((seq, at) => KernelTransportChanged(instance, seq, at, transport));
    if (opened) {
      _send(position, advancing: transport == KernelTransport.playing);
    }
    for (final (want, waiter) in [..._transportWaiters]) {
      if (want == transport && !waiter.isCompleted) waiter.complete(transport);
    }
    _transportWaiters.removeWhere((w) => w.$2.isCompleted);
  }

  Duration get _since => observed == KernelTransport.playing
      ? (_now - _sampleAt) * rate
      : Duration.zero;

  void _send(Duration position, {required bool advancing}) {
    _sampleAt = _now;
    _samplePosition = position;
    _emit((seq, at) => KernelPositionSample(instance, seq, at,
        position: position, rate: rate, advancing: advancing));
  }

  /// Where the kernel says it is. Told on only when it is not where the
  /// last sample runs on to: the clock extrapolates the rest.
  @protected
  void positionChanged(Duration at) {
    if (fenced) {
      _late++;
      return;
    }
    lastKnownPosition = at;
    final waiter = _sampleWaiter;
    if (waiter != null &&
        !waiter.isCompleted &&
        (at - _sampleNear).abs() <= const Duration(milliseconds: 1500)) {
      _sampleWaiter = null;
      waiter.complete(at);
    }
    if (!opened) return;
    final expected = _samplePosition + _since;
    if ((at - expected).abs() > driftLimit) {
      _send(at, advancing: observed == KernelTransport.playing);
    }
  }

  /// Call before asking the kernel to move: the returned wait completes
  /// with the first position the kernel gives within a second and a half of
  /// [near] (where it landed), or null when it gives none in that time.
  @protected
  SampleWait expectSample(Duration near) {
    final waiter = _sampleWaiter = Completer<Duration?>();
    _sampleNear = near;
    return SampleWait._(this, waiter);
  }

  @protected
  void bufferingChanged(bool buffering) =>
      _emit((seq, at) => KernelBuffering(instance, seq, at, buffering));

  /// The media played to its end. [inferred]: the kernel did not say.
  @protected
  void ended({bool inferred = false}) {
    if (_endSent || !opened) return;
    _endSent = true;
    _emit((seq, at) => KernelEnded(instance, seq, at, inferred: inferred));
  }

  @protected
  void failed(String message, {String stage = 'playback'}) => _emit((seq, at) =>
      KernelFailed(instance, seq, at, stage: stage, message: message));

  @protected
  void log(String level, String source, String text) =>
      PlayerNativeLogTap.observer
          ?.call(kernel.id, instance, level, source, text);

  // ---- what a kernel does (the subclass) ----

  /// The kernel lists the media's tracks (video_player does not: a media it
  /// opens may have audio it cannot name).
  @protected
  bool get listsTracks => true;

  @protected
  void applyVolume(double volume);

  @protected
  void applyRate(double rate);

  /// Properties and options set before the media opens.
  @protected
  Future<void> configure();

  /// Opens [source] at [start], paused. Completes once the media is open
  /// and its length known; returns where the first frame is.
  @protected
  Future<Duration> openMedia(ResolvedSource source, Duration start);

  /// Asks the kernel to seek. Completes once the kernel has the request.
  @protected
  Future<void> seekMedia(Duration target, {required bool exact});

  /// Asks the kernel to play or pause.
  @protected
  Future<void> pauseMedia(bool paused);

  /// The kernel's own position now, null when it has none to give.
  @protected
  Future<Duration?> readPosition();

  /// The media's facts as the kernel lists them now.
  @protected
  MediaFacts readMedia();

  /// Puts the picture where the interface takes it from.
  @protected
  Future<void> showPicture(MediaFacts media);

  /// The kernel-specific part of [readFacts].
  @protected
  Future<JsonMap> kernelFacts();

  /// The route this media is opened by: [ResolvedSource.direct] asks for no
  /// proxy for this open. A kernel with a proxy of its own clears it.
  @protected
  Future<void> routeSource(ResolvedSource source) async {}

  /// Before the media opens: what the kernel can be told then of the plan
  /// (mpv takes `aid` and `sid` as options of the file; Erika has no
  /// media yet) and the subtitle properties.
  @protected
  Future<void> applyPlan(KernelTrackPlan plan) async {}

  /// After the media opened: what the plan could not set before, put on,
  /// and what the kernel reports of the tracks it has on.
  @protected
  Future<KernelTracks> planOpened(KernelTrackPlan plan, MediaFacts media);

  /// Puts audio track [index] on and waits for the kernel to report it.
  @protected
  Future<TrackReport> switchAudio(int index);

  /// Puts [subtitle] on (and nothing else) and waits for the kernel to
  /// report it.
  @protected
  Future<TrackReport> switchSubtitle(KernelSubtitle subtitle, Duration? probe);

  /// How the kernel draws subtitles from now on.
  @protected
  Future<void> applySubtitleProperties(Map<String, String> properties);

  /// The text of the subtitle the kernel draws, null when it cannot tell.
  @protected
  Future<String?> readSubtitleText(Duration? at) async => null;

  /// Draws the frame the media is paused at, when the kernel has not.
  @protected
  Future<void> showFrame() async {}

  /// The interface has built a frame without the picture: its Texture or
  /// native view is gone.
  @protected
  Future<void> aFramePasses() => SchedulerBinding.instance.endOfFrame;

  /// Waits for what the interface owes the kernel before it goes: a native
  /// view detached, a texture released.
  @protected
  Future<void> unmount() async {}

  /// ④⑤ Destroys the native player and waits for it.
  @protected
  Future<void> disposeKernel();

  // ---- commands ----

  @override
  Future<KernelOpened> open(ResolvedSource source,
          {Duration start = Duration.zero,
          double volume = 1,
          double rate = 1,
          KernelTrackPlan tracks = const KernelTrackPlan()}) =>
      queue.run(() async {
        // I5: an instance opens once; a released one never does.
        if (_openStarted) {
          throw StateError('A kernel instance opens once.');
        }
        _openStarted = true;
        await configure();
        queue.live();
        // The tracks the source maps (a server version's own ordinals) are
        // what the plan opens with, over the library's.
        tracks = _planOf(source, tracks);
        _subtitleProperties.addAll(tracks.subtitleProperties);
        await routeSource(source);
        queue.live();
        await applyPlan(tracks);
        queue.live();
        applyVolume(volume);
        applyRate(this.rate = rate);
        final landed = await openMedia(source, start).timeout(openTimeout,
            onTimeout: () => throw KernelOpenFailure('media_ready_timeout',
                '${kernel.label} did not open the media within ${openTimeout.inSeconds} s.'));
        queue.live();
        _times['openUs'] = _watch.elapsedMicroseconds;
        final facts = media = readMedia();
        if (listsTracks && !facts.hasVideo && facts.audio.isEmpty) {
          throw KernelOpenFailure('invalid_media',
              '${kernel.label} found no audio or video stream.');
        }
        if (facts.duration <= Duration.zero) {
          throw KernelOpenFailure(
              'media_open', '${kernel.label} reported no media duration.');
        }
        duration = facts.duration;
        // What the plan could not set before the media opened, and what the
        // kernel says it has on.
        final planned = await planOpened(tracks, facts);
        queue.live();
        _tracks = planned;
        // Opened paused: the kernel is told once more, so what it says
        // afterwards is the answer.
        await pauseMedia(true);
        queue.live();
        if (observed != KernelTransport.paused) {
          transportChanged(KernelTransport.paused);
        }
        await showPicture(facts);
        queue.live();
        _times['firstFrameUs'] = _watch.elapsedMicroseconds;
        opened = true;
        _send(landed, advancing: false);
        _emit((seq, at) => KernelTracksChanged(instance, seq, at, _tracks));
        return KernelOpened(media = readMedia(), landed, _tracks);
      });

  @override
  Future<KernelTransport> setPaused(bool paused) => queue.run(() async {
        final want = paused ? KernelTransport.paused : KernelTransport.playing;
        if (observed == want) return want;
        final waiter = Completer<KernelTransport>();
        _transportWaiters.add((want, waiter));
        await pauseMedia(paused);
        queue.live();
        return waiter.future
            .timeout(const Duration(seconds: 2), onTimeout: () => observed);
      });

  static KernelTrackPlan _planOf(ResolvedSource source, KernelTrackPlan plan) {
    if (source.audioTrack == null &&
        source.subtitleTrack == null &&
        source.externalSubtitle == null) {
      return plan;
    }
    return KernelTrackPlan(
      audio: source.audioTrack ?? plan.audio,
      subtitle: source.externalSubtitle != null
          ? FileKernelSubtitle(source.externalSubtitle!)
          : source.subtitleTrack != null
              ? (source.subtitleTrack! < 0
                  ? KernelSubtitle.none
                  : EmbeddedKernelSubtitle(source.subtitleTrack!))
              : plan.subtitle,
      subtitleProperties: plan.subtitleProperties,
      subtitleProbe: plan.subtitleProbe,
    );
  }

  @override
  Future<SeekOutcome> seek(Duration target, {bool exact = true}) {
    final ticket = ++_seekTicket;
    return queue.run(() async {
      // One slot: a later seek replaces one that has not run yet.
      if (ticket != _seekTicket) {
        return const SeekOutcome(SeekResult.superseded, null);
      }
      final sample = expectSample(target);
      try {
        await seekMedia(target, exact: exact).timeout(seekTimeout);
        queue.live();
        // The kernel's first position near the target tells where it landed.
        final landed = await sample.landed ?? await readPosition() ?? target;
        queue.live();
        _endSent = false;
        _send(landed, advancing: observed == KernelTransport.playing);
        // A paused picture is the frame the media is at, not the one before.
        if (observed != KernelTransport.playing) {
          await showFrame();
          queue.live();
        }
        return SeekOutcome(SeekResult.done, landed);
      } finally {
        sample.cancel();
      }
    });
  }

  @override
  Future<void> setRate(double value) => queue.run(() async {
        applyRate(rate = value);
        if (opened) {
          _send(_samplePosition + _since,
              advancing: observed == KernelTransport.playing);
        }
      });

  @override
  Future<void> setVolume(double value) =>
      queue.run(() async => applyVolume(value));

  // ---- tracks (player-core P2's interface) ----

  /// How long a track change waits for the kernel's report.
  static const trackConfirmWait = Duration(milliseconds: 1500);

  KernelTracks _tracks = const KernelTracks();
  final _subtitleProperties = <String, String>{};

  @override
  KernelTracks get tracks => _tracks;

  /// What the kernel reports of the tracks, told once and kept.
  @protected
  void confirmTracks(KernelTracks next) {
    if (next == _tracks) return;
    _tracks = next;
    _emit((seq, at) => KernelTracksChanged(instance, seq, at, next));
  }

  /// A fuller report of the opened media arrived after [open]'s snapshot
  /// (for example, metadata that the kernel made available later).
  @protected
  void confirmMedia(MediaFacts next) {
    _emit((seq, at) => KernelMediaChanged(instance, seq, at, next));
  }

  Duration get _where => _samplePosition + _since;

  /// A track change that moved the position puts it back, unless a seek
  /// was asked meanwhile (design §2.4).
  Future<void> _keepPosition(Duration from, int ticket) async {
    if (ticket != _seekTicket || !opened) return;
    final now = lastKnownPosition;
    if ((now - from).abs() <= const Duration(seconds: 1)) return;
    _trackLog.add({
      'atMs': _now.inMilliseconds,
      'moved': {'fromMs': from.inMilliseconds, 'toMs': now.inMilliseconds},
    });
    final sample = expectSample(from);
    try {
      await seekMedia(from, exact: true).timeout(seekTimeout);
      queue.live();
      final landed = await sample.landed ?? from;
      _send(landed, advancing: observed == KernelTransport.playing);
    } finally {
      sample.cancel();
    }
  }

  @override
  Future<KernelTracks> selectAudio(int index) => queue.run(() async {
        if (!opened) throw StateError('The media is not open.');
        if (_tracks.audio == index && _tracks.audioConfirmed) return _tracks;
        final from = _where;
        final ticket = _seekTicket;
        final report = await switchAudio(index);
        queue.live();
        await _keepPosition(from, ticket);
        confirmTracks(_tracks.copyWith(
            audio: () => index,
            audioConfirmed: report.confirmed,
            basis: report.basis));
        return _tracks;
      });

  @override
  Future<KernelTracks> selectSubtitle(KernelSubtitle subtitle,
          {Duration? probe}) =>
      queue.run(() async {
        if (!opened) throw StateError('The media is not open.');
        if (subtitle == _tracks.subtitle && _tracks.subtitleConfirmed) {
          return _tracks;
        }
        final from = _where;
        final ticket = _seekTicket;
        final report = await switchSubtitle(subtitle, probe);
        queue.live();
        await _keepPosition(from, ticket);
        confirmTracks(_tracks.copyWith(
            subtitle: subtitle,
            subtitleConfirmed: report.confirmed,
            basis: report.basis));
        return _tracks;
      });

  @override
  Future<void> setSubtitleProperties(Map<String, String> properties) =>
      queue.run(() async {
        final changed = {
          for (final e in properties.entries)
            if (_subtitleProperties[e.key] != e.value) e.key: e.value
        };
        if (changed.isEmpty) return;
        await applySubtitleProperties(changed);
        queue.live();
        _subtitleProperties.addAll(changed);
      });

  @override
  Future<String?> subtitleText({Duration? at}) =>
      queue.run(() => readSubtitleText(at));

  @override
  Future<void> presentFrame() => queue.run(showFrame);

  // ---- facts ----

  /// What the media says of its tracks, in the shape the facts have.
  @protected
  MediaFacts mediaFromInfo(PlayerMediaInfo info,
      {List<int> activeAudio = const [],
      List<int> activeSubtitles = const [],
      double? frameRate,
      List<ChapterFacts>? chapters}) {
    final first = info.video?.firstOrNull;
    return MediaFacts(
      duration: Duration(milliseconds: info.duration),
      width: first?.codec.width ?? 0,
      height: first?.codec.height ?? 0,
      videoCodec: first == null || first.codecName == 'unknown'
          ? null
          : first.codecName,
      audio: [
        for (final (i, a)
            in (info.audio ?? const <PlayerAudioStreamInfo>[]).indexed)
          TrackFacts(
              index: i,
              codec: a.codec.name,
              title: a.title,
              language: a.language,
              channels: a.codec.channels,
              sampleRate: a.codec.sampleRate),
      ],
      subtitles: [
        for (final (i, s)
            in (info.subtitle ?? const <PlayerSubtitleStreamInfo>[]).indexed)
          TrackFacts(index: i, title: s.title, language: s.language),
      ],
      activeAudio: List.of(activeAudio),
      activeSubtitles: List.of(activeSubtitles),
      frameRate: frameRate,
      chapters: chapters ??
          (info.chapters == null
              ? null
              : [for (final c in info.chapters!) ChapterFacts(c.title, c.startMs)]),
    );
  }

  @override
  Future<JsonMap> readFacts() => queue.run(() async => {
        'kernel': {'id': kernel.id, 'name': kernel.label, 'instance': instance},
        'config': config.toJson(),
        'capabilities': capabilities.toJson(),
        'media': media?.toJson(),
        'transport': observed.name,
        'tracks': {
          'kernel': _tracks.toJson(),
          'subtitleProperties': Map.of(_subtitleProperties),
          'log': List.of(_trackLog),
        },
        ...await kernelFacts(),
        'lifecycle': lifecycle,
      });

  @override
  JsonMap get lifecycle => {
        'instance': instance,
        ..._times,
        'fenced': fenced,
        'lateCallbacks': _late,
        'releaseTimeouts': List.of(_releaseTimeouts),
      };

  // ---- release (I2, I4, I5) ----

  @override
  Future<void> release() {
    if (_release case final release?) return release;
    // ① The fence, before anything waits: nothing reaches the kernel after
    // this but its own teardown.
    queue.fence();
    for (final (_, waiter) in _transportWaiters) {
      if (!waiter.isCompleted) waiter.complete(observed);
    }
    _transportWaiters.clear();
    if (_sampleWaiter case final waiter? when !waiter.isCompleted) {
      waiter.complete(null);
    }
    return _release = _teardown();
  }

  Future<void> _teardown() async {
    final watch = Stopwatch()..start();
    // ② The sound stops at once.
    if (observed == KernelTransport.playing) {
      await _step('stop', () => pauseMedia(true));
    }
    // What was in flight ends before anything is taken away.
    await _step('drain', () => queue.drained);
    // ③ The picture leaves the interface, and a frame passes without it.
    _surface.value = null;
    await _step('unmount', () async {
      await aFramePasses();
      await unmount();
    });
    // ④⑤ The kernel frees what it renders with, then goes.
    await _step('dispose', disposeKernel);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _times['releaseUs'] = watch.elapsedMicroseconds;
    await _events.close();
  }

  Future<void> _step(String name, Future<void> Function() step) async {
    try {
      await step().timeout(stepTimeout);
    } on TimeoutException {
      _releaseTimeouts.add(name);
    } catch (error) {
      debugPrint(
          '[NextPlayer] ${kernel.label} $instance release $name: $error');
    }
  }
}

/// A wait for the position a kernel gives after it was asked to move
/// ([AdapterDriver.expectSample]).
final class SampleWait {
  SampleWait._(this._driver, this._waiter);
  final AdapterDriver _driver;
  final Completer<Duration?> _waiter;

  Future<Duration?> get landed => _waiter.future
      .timeout(const Duration(milliseconds: 1500), onTimeout: () => null);

  void cancel() {
    if (identical(_driver._sampleWaiter, _waiter)) _driver._sampleWaiter = null;
  }
}

/// What a kernel said of a track change: reported by the kernel itself
/// (a property read back, an event naming the track on) or only taken,
/// and which of those it was.
typedef TrackReport = ({bool confirmed, String basis});
