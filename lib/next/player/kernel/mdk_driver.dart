import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/abstract_player.dart'
    show PlayerNativeLogTap;
import 'package:nipaplay/player_abstraction/hwdec_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/arbiter.dart';
import '../core/clock.dart';
import '../perf/budget.dart';
import 'driver.dart';
import 'op_queue.dart';

/// The MDK settings Classic and Next share (D3), read when a kernel
/// instance is created: they hold for that instance (I6).
KernelConfig mdkConfigFrom(SharedPreferences prefs) {
  final hardware = prefs.getBool('use_hardware_decoder') ?? true;
  final mode = prefs.getString('hwdec_mode');
  final saved = prefs.getStringList('selected_decoders') ?? const <String>[];
  List<String> decoders;
  const autoModes = {null, 'auto', 'autoSafe', 'autoCopy', 'no'};
  if (!autoModes.contains(mode) && mode != null) {
    // A named hardware decoder: that one, software after it, as Classic.
    decoders = [_mdkDecoderFor(mode), 'FFmpeg'];
  } else {
    bool software(String d) {
      final lower = d.toLowerCase();
      return lower.contains('ffmpeg') || lower.contains('dav1d');
    }

    decoders = [
      ...saved.where((d) => software(d) != hardware),
      ...saved.where((d) => software(d) == hardware),
    ];
  }
  final pixelFormat = prefs.getString('soft_decode_pixel_format') ?? '';
  final seconds = prefs.getInt('player_precache_buffer_duration_seconds');
  return KernelConfig(
    kernel: KernelId.mdk,
    videoDecoders: decoders,
    hardwareDecoding: hardware,
    bufferMaxMs: seconds == null ? null : seconds.clamp(1, 120) * 1000,
    properties: {
      // MDK loads no subtitle file it finds beside the video by itself.
      'auto_load': '0',
      'subtitle': '1',
      if (pixelFormat.isNotEmpty) 'video.decoder': 'pixel_format=$pixelFormat',
    },
  );
}

/// Classic's mapping of a named hwdec mode to MDK's decoder name.
String _mdkDecoderFor(String mode) {
  final hwdec =
      HwDecType.values.where((h) => h.name == mode).firstOrNull?.hwdec ?? mode;
  return hwdec.replaceAll('-copy', '').split('-').first;
}

/// MDK (fvp) as a [KernelDriver]: one native player per instance, made
/// here and deleted here, never reused (I6, D6).
///
/// Everything that touches the native player runs in this instance's queue
/// (I8), except the position read of the sampler; nothing does once the
/// instance is fenced (I2). The media opens at its start position, paused
/// (`prepare(position:)`), and nothing changes its tracks: deactivating a
/// subtitle track while MDK stops is where MDK hung in P0, so no track is
/// switched at all here.
final class MdkDriver implements KernelDriver {
  MdkDriver(KernelLease lease, this.config, {mdk.Player Function()? create})
      : instance = ++_instances {
    // I1: only the lease holder makes a kernel.
    if (!lease.held || lease.owner != KernelOwner.next) {
      throw StateError('An MDK instance is made only under Next\'s lease.');
    }
    final watch = Stopwatch()..start();
    _player = (create ?? mdk.Player.new)();
    _player.onStateChanged(_stateChanged);
    _player.onMediaStatus(_statusChanged);
    _player.onEvent(_event);
    _times['createUs'] = watch.elapsedMicroseconds;
  }

  static int _instances = 0;

  /// How often the position is read while the kernel plays.
  static const sampleEvery = Duration(milliseconds: 250);

  /// A read this far from where the last sample runs on to is sent.
  static const driftLimit = Duration(milliseconds: 40);

  @override
  final int instance;
  @override
  final KernelConfig config;
  @override
  KernelId get kernel => KernelId.mdk;
  @override
  final KernelCapabilities capabilities = const KernelCapabilities(
    transportEvents: true,
    seekConfirm: true,
    bufferingTelemetry: true,
    endEvent: true,
    openAtPosition: true,
  );

  late final mdk.Player _player;
  final _queue = KernelOpQueue();
  final _events = StreamController<KernelEvent>.broadcast(sync: true);
  final _surface = ValueNotifier<VideoSurface?>(null);
  int _seq = 0;
  KernelTransport _observed = KernelTransport.stopped;
  final _transportWaiters = <(KernelTransport, Completer<KernelTransport>)>[];
  bool _buffering = false;
  bool _seeking = false;
  Completer<void>? _seekSettled;
  int _seekTicket = 0;
  double _rate = 1;
  bool _opened = false;
  Duration _duration = Duration.zero;
  MediaFacts? _media;
  Timer? _sampler;
  Duration _sampleAt = Duration.zero;
  Duration _samplePosition = Duration.zero;
  Duration? _lastRead;
  Duration _still = Duration.zero;
  bool _endSent = false;
  Future<void>? _release;
  int _late = 0;
  final _times = <String, int>{};
  final _releaseTimeouts = <String>[];
  final _seen = <String, JsonMap>{};

  @override
  Stream<KernelEvent> get events => _events.stream;
  @override
  ValueListenable<VideoSurface?> get surface => _surface;
  @override
  bool get fenced => _queue.fenced;

  Duration get _now => PlayerTime.now();

  void _emit(KernelEvent Function(int seq, Duration at) make) {
    if (fenced || _events.isClosed) return;
    _events.add(make(++_seq, _now));
  }

  void _sample(Duration position, {required bool advancing}) {
    _sampleAt = _now;
    _samplePosition = position;
    _emit((seq, at) => KernelPositionSample(instance, seq, at,
        position: position, rate: _rate, advancing: advancing));
  }

  Duration _position() => Duration(milliseconds: _player.position);

  // ---- what MDK says ----

  void _stateChanged(mdk.PlaybackState old, mdk.PlaybackState now) {
    if (fenced) {
      _late++;
      return;
    }
    PlayerPerf.span('mdk.state', () {
      final transport = switch (now) {
        mdk.PlaybackState.playing => KernelTransport.playing,
        mdk.PlaybackState.paused => KernelTransport.paused,
        _ => KernelTransport.stopped,
      };
      if (transport == _observed) return;
      _observed = transport;
      _emit((seq, at) => KernelTransportChanged(instance, seq, at, transport));
      if (_opened) {
        _sample(_position(), advancing: transport == KernelTransport.playing);
      }
      _sampler?.cancel();
      _sampler = null;
      if (transport == KernelTransport.playing) {
        _still = Duration.zero;
        _lastRead = null;
        _sampler = Timer.periodic(sampleEvery, (_) => _read());
      }
      for (final (want, waiter) in [..._transportWaiters]) {
        if (want == transport && !waiter.isCompleted) waiter.complete(transport);
      }
      _transportWaiters.removeWhere((w) => w.$2.isCompleted);
    });
  }

  bool _statusChanged(mdk.MediaStatus old, mdk.MediaStatus now) {
    if (fenced) {
      _late++;
      return true;
    }
    PlayerPerf.span('mdk.status', () {
      final buffering = now.test(mdk.MediaStatus.buffering);
      if (buffering != _buffering) {
        _buffering = buffering;
        _emit((seq, at) => KernelBuffering(instance, seq, at, buffering));
      }
      final seeking = now.test(mdk.MediaStatus.seeking);
      if (_seeking && !seeking) {
        final settled = _seekSettled;
        _seekSettled = null;
        if (settled != null && !settled.isCompleted) settled.complete();
      }
      _seeking = seeking;
      if (_opened &&
          !old.test(mdk.MediaStatus.end) &&
          now.test(mdk.MediaStatus.end)) {
        _ended(inferred: false);
      }
      if (_opened &&
          !old.test(mdk.MediaStatus.invalid) &&
          now.test(mdk.MediaStatus.invalid)) {
        _emit((seq, at) => KernelFailed(instance, seq, at,
            stage: 'invalid_media', message: 'MDK marked the media invalid.'));
      }
      _log('status', 'media_status', now.toString());
    });
    return true;
  }

  void _event(mdk.MediaEvent e) {
    if (fenced) {
      _late++;
      return;
    }
    final seen = _seen[e.category];
    _seen[e.category] = {
      'count': ((seen?['count'] as int?) ?? 0) + 1,
      'firstAtMs': seen?['firstAtMs'] ?? _now.inMilliseconds,
      'lastAtMs': _now.inMilliseconds,
      'error': e.error,
      'detail': e.detail,
    };
    _log(e.error < 0 ? 'error' : 'event', e.category,
        'error=${e.error} detail=${e.detail}');
  }

  void _log(String level, String source, String text) =>
      PlayerNativeLogTap.observer?.call('mdk', instance, level, source, text);

  /// While playing: where MDK is, sent when it is not where the last
  /// sample runs on to; and the end when MDK stands still there without
  /// saying so.
  void _read() {
    if (fenced || _observed != KernelTransport.playing) return;
    PlayerPerf.span('mdk.sample', () {
      final at = _position();
      final expected = _samplePosition + (_now - _sampleAt) * _rate;
      if ((at - expected).abs() > driftLimit) _sample(at, advancing: true);
      final last = _lastRead;
      _lastRead = at;
      if (_duration > Duration.zero &&
          at >= _duration - const Duration(milliseconds: 1500) &&
          last == at) {
        _still += sampleEvery;
        if (_still >= const Duration(milliseconds: 1500)) _ended(inferred: true);
      } else {
        _still = Duration.zero;
      }
    });
  }

  void _ended({required bool inferred}) {
    if (_endSent) return;
    _endSent = true;
    _emit((seq, at) => KernelEnded(instance, seq, at, inferred: inferred));
  }

  // ---- commands ----

  @override
  Future<KernelOpened> open(ResolvedSource source,
          {Duration start = Duration.zero, double volume = 1, double rate = 1}) =>
      _queue.run(() async {
        final watch = Stopwatch()..start();
        final p = _player;
        for (final e in config.properties.entries) {
          p.setProperty(e.key, e.value);
        }
        if (config.videoDecoders.isNotEmpty) {
          p.videoDecoders = config.videoDecoders;
        }
        if (config.bufferMaxMs case final max?) {
          p.setBufferRange(min: 1000, max: max);
        }
        p.volume = volume;
        p.playbackRate = _rate = rate;
        p.media = source.uri;
        // The frame at [start] itself, not the keyframe before it.
        final landed = await p
            .prepare(
                position: start.inMilliseconds,
                flags: const mdk.SeekFlag(mdk.SeekFlag.fromStart))
            .timeout(const Duration(seconds: 15), onTimeout: () => -100);
        _queue.live();
        _times['prepareUs'] = watch.elapsedMicroseconds;
        if (landed == -100) {
          throw const KernelOpenFailure('media_ready_timeout',
              'MDK did not open the media within 15 s.');
        }
        if (landed < 0) {
          throw KernelOpenFailure(
              'media_open', 'MDK could not open the media (code $landed).',
              code: landed);
        }
        final media = _media = _readMedia();
        if (!media.hasVideo && media.audio.isEmpty) {
          throw const KernelOpenFailure(
              'invalid_media', 'MDK found no audio or video stream.');
        }
        _duration = media.duration;
        if (_player.state != mdk.PlaybackState.paused) {
          _player.state = mdk.PlaybackState.paused;
        }
        if (media.hasVideo) {
          final texture = await p
              .updateTexture()
              .timeout(const Duration(seconds: 10), onTimeout: () => -2);
          _queue.live();
          if (texture < 0) {
            throw KernelOpenFailure('media_open',
                'MDK did not make the picture (texture $texture).',
                code: texture);
          }
          final size = await p.textureSize;
          _queue.live();
          _surface.value = TextureSurface(texture,
              width: size?.width.round() ?? media.width,
              height: size?.height.round() ?? media.height);
        }
        _times['firstFrameUs'] = watch.elapsedMicroseconds;
        _opened = true;
        final at = Duration(milliseconds: landed);
        _sample(at, advancing: false);
        return KernelOpened(media, at);
      });

  MediaFacts _readMedia() {
    final info = _player.mediaInfo;
    final video = info.video ?? const [];
    final first = video.firstOrNull;
    String? text(Object? Function() read) {
      try {
        final v = read();
        return v == null || '$v'.isEmpty ? null : '$v';
      } catch (_) {
        return null;
      }
    }

    return MediaFacts(
      duration: Duration(milliseconds: info.duration),
      width: first?.codec.width ?? 0,
      height: first?.codec.height ?? 0,
      videoCodec: first == null ? null : text(() => first.codec.codec),
      frameRate: first?.codec.frameRate,
      format: text(() => info.format),
      bitRate: info.bitRate,
      audio: [
        for (final (i, a) in (info.audio ?? const <mdk.AudioStreamInfo>[]).indexed)
          TrackFacts(
            index: i,
            codec: text(() => a.codec.codec),
            title: a.metadata['title'],
            language: a.metadata['language'],
            channels: a.codec.channels,
            sampleRate: a.codec.sampleRate,
          ),
      ],
      subtitles: [
        for (final (i, s)
            in (info.subtitle ?? const <mdk.SubtitleStreamInfo>[]).indexed)
          TrackFacts(
            index: i,
            codec: text(() => s.codec.codec),
            title: s.metadata['title'],
            language: s.metadata['language'],
          ),
      ],
      activeAudio: List.of(_player.activeAudioTracks),
      activeSubtitles: List.of(_player.activeSubtitleTracks),
    );
  }

  @override
  Future<KernelTransport> setPaused(bool paused) => _queue.run(() async {
        final want = paused ? KernelTransport.paused : KernelTransport.playing;
        if (_observed == want) return want;
        final waiter = Completer<KernelTransport>();
        _transportWaiters.add((want, waiter));
        _player.state =
            paused ? mdk.PlaybackState.paused : mdk.PlaybackState.playing;
        return waiter.future
            .timeout(const Duration(seconds: 2), onTimeout: () => _observed);
      });

  @override
  Future<SeekOutcome> seek(Duration target, {bool exact = true}) {
    final ticket = ++_seekTicket;
    return _queue.run(() async {
      // One slot: a later seek replaces one that has not run yet.
      if (ticket != _seekTicket) {
        return const SeekOutcome(SeekResult.superseded, null);
      }
      final flags = mdk.SeekFlag(exact
          ? mdk.SeekFlag.fromStart
          : mdk.SeekFlag.defaultFlags);
      for (var attempt = 0;; attempt++) {
        final result = await _player
            .seek(position: target.inMilliseconds, flags: flags)
            .timeout(const Duration(seconds: 3), onTimeout: () => -3);
        _queue.live();
        if (result >= 0) {
          final landed = Duration(milliseconds: result);
          _endSent = false;
          _sample(landed, advancing: _observed == KernelTransport.playing);
          return SeekOutcome(SeekResult.done, landed);
        }
        if (result == -2 || ticket != _seekTicket) {
          return SeekOutcome(SeekResult.superseded, null, code: result);
        }
        // MDK turns a seek away while one of its own runs; once that one
        // is done, ask again.
        if (attempt >= 2) return SeekOutcome(SeekResult.rejected, null, code: result);
        if (_seeking) {
          await (_seekSettled ??= Completer<void>())
              .future
              .timeout(const Duration(seconds: 2), onTimeout: () {});
          _queue.live();
        }
      }
    });
  }

  @override
  Future<void> setRate(double rate) => _queue.run(() async {
        _player.playbackRate = _rate = rate;
        if (_opened) {
          _sample(_position(), advancing: _observed == KernelTransport.playing);
        }
      });

  @override
  Future<void> setVolume(double volume) =>
      _queue.run(() async => _player.volume = volume);

  @override
  Future<JsonMap> readFacts() => _queue.run(() async {
        final buffered = _player.buffered();
        return {
          'kernel': {'id': kernel.id, 'name': kernel.label, 'instance': instance},
          'version': _version(),
          'config': config.toJson(),
          'capabilities': capabilities.toJson(),
          'media': _media?.toJson(),
          'transport': _observed.name,
          'positionMs': _player.position,
          'bufferedAheadMs': buffered < 0 ? null : buffered,
          'decoders': {
            'video': _seen['decoder.video']?['detail'],
            'audio': _seen['decoder.audio']?['detail'],
            'requested': config.videoDecoders,
          },
          'events': {for (final e in _seen.entries) e.key: Map.of(e.value)},
          'lifecycle': lifecycle,
        };
      });

  static String? _version() {
    try {
      final v = mdk.version();
      return '${(v >> 16) & 0xff}.${(v >> 8) & 0xff}.${v & 0xff}';
    } catch (_) {
      return null;
    }
  }

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
    // ① The fence, before anything waits: nothing reaches MDK after this
    // but its own teardown.
    _queue.fence();
    _sampler?.cancel();
    _sampler = null;
    for (final (_, waiter) in _transportWaiters) {
      if (!waiter.isCompleted) waiter.complete(_observed);
    }
    _transportWaiters.clear();
    final settled = _seekSettled;
    if (settled != null && !settled.isCompleted) settled.complete();
    return _release = _teardown();
  }

  Future<void> _teardown() async {
    final watch = Stopwatch()..start();
    // ② The sound stops at once. No track changes here (P0's MDK hang).
    if (_observed == KernelTransport.playing) {
      try {
        _player.state = mdk.PlaybackState.paused;
      } catch (_) {}
    }
    // ③ The picture leaves the interface, and a frame passes without it.
    _surface.value = null;
    await _step('unmount', () => SchedulerBinding.instance.endOfFrame);
    // ④⑤ fvp releases the texture, closes its port, stops MDK and deletes
    // the native player on another isolate.
    await _step('dispose', _player.dispose);
    _times['releaseUs'] = watch.elapsedMicroseconds;
    await _events.close();
  }

  Future<void> _step(String name, Future<void> Function() step) async {
    try {
      await step().timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _releaseTimeouts.add(name);
    } catch (error) {
      debugPrint('[NextPlayer] MDK $instance release $name: $error');
    }
  }
}
