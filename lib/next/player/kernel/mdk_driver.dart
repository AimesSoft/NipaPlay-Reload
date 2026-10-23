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
import 'instances.dart';
import 'native.dart';
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
      // Whether it draws a subtitle at all is the open's track plan.
      'auto_load': '0',
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
/// (`prepare(position:)`), with its tracks set before (MDK resets them when
/// the media is set, and draws its first subtitle track unless told).
///
/// Tracks change only while the media is open, never while MDK stops:
/// deactivating a subtitle track while MDK stops is where MDK hung in P0.
/// Turning the subtitle off stops MDK drawing it (the `subtitle` property)
/// and leaves the track decoding, so that off and back on deactivates
/// nothing.
final class MdkDriver implements KernelDriver, MdkNative {
  MdkDriver(KernelLease lease, this.config, {mdk.Player Function()? create})
      : instance = nextKernelInstance() {
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
  /// How long a track change waits for MDK to open the decoder for it.
  static const trackConfirmWait = Duration(milliseconds: 1500);

  /// A track change that leaves the position further than this from where
  /// it was is followed by a seek back there.
  static const trackSeekTolerance = Duration(seconds: 1);

  @override
  final KernelCapabilities capabilities = const KernelCapabilities(
    transportEvents: true,
    seekConfirm: true,
    bufferingTelemetry: true,
    endEvent: true,
    openAtPosition: true,
    trackConfirm: true,
    // libass ships inside mdk.framework; bitmap files demux through FFmpeg.
    subtitleFiles: {'ass', 'ssa', 'sup', 'idx'},
    subtitleScale: true,
    subtitleText: true,
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

  // ---- tracks ----
  KernelTracks _tracks = const KernelTracks();

  /// The subtitle MDK decodes (its active subtitle track or file), whether
  /// or not it draws it ([_drawing]).
  KernelSubtitle _decoding = KernelSubtitle.none;
  bool _drawing = false;
  final _subtitleProperties = <String, String>{};
  final _eventWaiters = <(String, Completer<mdk.MediaEvent>)>[];

  /// Opened with a subtitle (or audio) MDK had not reported yet: its
  /// decoder's report confirms it later.
  bool _awaitSubtitleDecoder = false;
  bool _awaitAudioDecoder = false;
  final _trackLog = <JsonMap>[];

  /// While a track changes, MDK's status changes go into the track log.
  bool _watchStatus = false;
  Completer<void>? _seekBegan;

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

  /// A call into MDK on the main isolate, timed: the slowest of each kind
  /// is kept in the lifecycle, and one over 50 ms goes into the track log
  /// (MDK's calls are synchronous; one that waits blocks the isolate).
  T _ffi<T>(String name, T Function() call) {
    final watch = Stopwatch()..start();
    try {
      return call();
    } finally {
      final us = watch.elapsedMicroseconds;
      final key = 'ffi.$name.maxUs';
      if (us > (_times[key] ?? 0)) _times[key] = us;
      if (us > 50000) {
        _trackLog.add({'atMs': _now.inMilliseconds, 'slowCall': name, 'us': us});
        if (_trackLog.length > 40) _trackLog.removeAt(0);
      }
    }
  }

  /// A track change while the media is open, off the main isolate (MDK
  /// can wait for its reader meanwhile: 2.3 ms measured on it).
  Future<void> _switchTracks(mdk.MediaType type, List<int> tracks) async {
    final watch = Stopwatch()..start();
    final call = _ffi('handOver.tracks',
        () => _player.setActiveTracksOffThread(type, tracks));
    await call;
    _queue.live();
    final key = 'mdk.tracks.${type.name}.maxUs';
    final us = watch.elapsedMicroseconds;
    if (us > (_times[key] ?? 0)) _times[key] = us;
  }

  /// MDK's setState, off the main isolate (measured on it: 3–16 ms to
  /// play, 30–35 ms to pause, and once 2.1 s for the first play of a
  /// process while the audio output started). The main isolate only hands
  /// it over; what it took MDK is kept as the slowest per kind.
  Future<void> _setState(mdk.PlaybackState state) async {
    final watch = Stopwatch()..start();
    final call = _ffi('handOver.state', () => _player.setStateOffThread(state));
    await call;
    final key = 'mdk.state.${state.name}.maxUs';
    final us = watch.elapsedMicroseconds;
    if (us > (_times[key] ?? 0)) _times[key] = us;
  }

  /// Where the media is, for a change made now: MDK's own reading while it
  /// plays; paused, the last position it confirmed (a seek's landing, a
  /// sample), as its reading stays where it was before a paused seek
  /// (measured: 59958 after landing at 108958).
  Duration _where() => _observed == KernelTransport.playing
      ? _position()
      : _samplePosition;

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
      if (_flashing) {
        final waiter = transport == KernelTransport.paused
            ? _flashPaused
            : transport == KernelTransport.playing
                ? _flashPlaying
                : null;
        if (waiter != null && !waiter.isCompleted) waiter.complete();
        return;
      }
      if (transport == _observed) return;
      final wasPlaying = _observed == KernelTransport.playing;
      _observed = transport;
      _emit((seq, at) => KernelTransportChanged(instance, seq, at, transport));
      if (_opened) {
        // From a pause it starts where it was confirmed paused (its own
        // reading can still be from before a paused seek); the sampler
        // follows it from there.
        _sample(wasPlaying ? _position() : _samplePosition,
            advancing: transport == KernelTransport.playing);
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
      if (!_seeking && seeking) {
        final began = _seekBegan;
        _seekBegan = null;
        if (began != null && !began.isCompleted) began.complete();
      }
      _seeking = seeking;
      if (_watchStatus) {
        _trackLog.add({
          'atMs': _now.inMilliseconds,
          'status': now.toString(),
          'positionMs': _player.position,
        });
        if (_trackLog.length > 40) _trackLog.removeAt(0);
      }
      if (_opened &&
          !_flashing &&
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
    if (e.category.startsWith('decoder.') ||
        e.category.startsWith('thread.')) {
      _noteTrackEvent(e);
    }
    for (final (category, waiter) in [..._eventWaiters]) {
      if (category == e.category && !waiter.isCompleted) waiter.complete(e);
    }
    _eventWaiters.removeWhere((w) => w.$2.isCompleted);
    if (!_opened) return;
    if (_awaitSubtitleDecoder && e.category == 'decoder.subtitle') {
      _awaitSubtitleDecoder = false;
      _confirm(_tracks.copyWith(
          subtitleConfirmed: e.error >= 0,
          basis: e.error >= 0 ? 'decoder_open' : 'decoder_failed'));
    }
    if (_awaitAudioDecoder && e.category == 'decoder.audio') {
      _awaitAudioDecoder = false;
      _confirm(_tracks.copyWith(
          audioConfirmed: e.error >= 0,
          basis: e.error >= 0 ? 'decoder_open' : 'decoder_failed'));
    }
  }

  /// The decoder and thread reports of the tracks, the last few kept for
  /// the facts (what MDK said when a track went on or off).
  void _noteTrackEvent(mdk.MediaEvent e) {
    _trackLog.add({
      'atMs': _now.inMilliseconds,
      'category': e.category,
      'error': e.error,
      'detail': e.detail,
    });
    if (_trackLog.length > 24) _trackLog.removeAt(0);
  }

  void _confirm(KernelTracks tracks) {
    if (tracks == _tracks) return;
    _tracks = tracks;
    _emit((seq, at) => KernelTracksChanged(instance, seq, at, tracks));
  }

  /// The next report of [category] MDK makes, or null after [wait].
  Future<mdk.MediaEvent?> _next(String category, Duration wait) {
    final waiter = Completer<mdk.MediaEvent>();
    _eventWaiters.add((category, waiter));
    return waiter.future.then<mdk.MediaEvent?>((e) => e).timeout(wait,
        onTimeout: () {
      _eventWaiters.removeWhere((w) => identical(w.$2, waiter));
      return null;
    });
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
  KernelTracks get tracks => _tracks;

  @override
  Future<KernelOpened> open(ResolvedSource source,
          {Duration start = Duration.zero,
          double volume = 1,
          double rate = 1,
          KernelTrackPlan tracks = const KernelTrackPlan()}) =>
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
        _ffi('media', () => p.media = source.uri);
        // MDK resets the tracks when the media is set and otherwise opens
        // with the first of each: the plan goes in now, before prepare.
        final audioReports = _count('decoder.audio');
        final subtitleReports = _count('decoder.subtitle');
        _plan(tracks);
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
          await _setState(mdk.PlaybackState.paused);
          _queue.live();
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
        var at = Duration(milliseconds: landed);
        // Opened at a position, MDK loses the first subtitle packet after
        // it (measured: of two ASS lines both starting 0.6 s after the
        // open point, only the second was drawn; opened earlier, or after
        // a seek there, both were). A seek to where it opened, before it
        // plays, gives its subtitle decoder every line from there.
        if (start > Duration.zero && _drawing && _decoding is EmbeddedKernelSubtitle) {
          final reseek = Stopwatch()..start();
          final again = await p
              .seek(
                  position: landed,
                  flags: const mdk.SeekFlag(mdk.SeekFlag.fromStart))
              .timeout(const Duration(seconds: 3), onTimeout: () => -3);
          _queue.live();
          _times['subtitleReseekUs'] = reseek.elapsedMicroseconds;
          if (again >= 0) at = Duration(milliseconds: again);
        }
        _sample(at, advancing: false);
        // What MDK reported of the planned tracks while it opened; what it
        // has not yet is confirmed when its decoder reports.
        final audioSeen = _count('decoder.audio') > audioReports;
        var subtitleSeen = _count('decoder.subtitle') > subtitleReports;
        final subtitle = _drawing ? _decoding : KernelSubtitle.none;
        if (subtitle is FileKernelSubtitle && !subtitleSeen) {
          if (tracks.subtitleProbe case final probe?) {
            final text =
                p.subtitleText(time: probe.inMicroseconds / 1e6).trim();
            _trackLog.add({
              'atMs': _now.inMilliseconds,
              'probe': {'atMs': probe.inMilliseconds, 'text': text},
            });
            subtitleSeen = text.isNotEmpty;
          }
        }
        _awaitAudioDecoder = tracks.audio != null && !audioSeen;
        _awaitSubtitleDecoder = subtitle.drawn && !subtitleSeen;
        _tracks = KernelTracks(
          audio: tracks.audio,
          subtitle: subtitle,
          audioConfirmed: tracks.audio == null || audioSeen,
          subtitleConfirmed: subtitle.drawn
              ? subtitleSeen
              : p.getProperty('subtitle') == '0',
          basis: 'opened',
        );
        _emit((seq, at) => KernelTracksChanged(instance, seq, at, _tracks));
        return KernelOpened(media, at, _tracks);
      });

  int _count(String category) => (_seen[category]?['count'] as int?) ?? 0;

  /// The open's tracks, told to MDK after the media is set and before it
  /// opens: nothing is deactivated, as nothing was active.
  void _plan(KernelTrackPlan plan) {
    final p = _player;
    for (final e in plan.subtitleProperties.entries) {
      if (_mdkCannot.contains(e.key)) continue;
      p.setProperty(e.key, e.value);
      _subtitleProperties[e.key] = e.value;
    }
    if (plan.audio case final audio?) {
      _ffi('activeAudioTracks', () => p.activeAudioTracks = [audio]);
    }
    switch (plan.subtitle) {
      case NoKernelSubtitle():
        _ffi('activeSubtitleTracks', () => p.activeSubtitleTracks = const []);
        _setDrawing(false);
      case EmbeddedKernelSubtitle(:final index):
        _ffi('activeSubtitleTracks', () => p.activeSubtitleTracks = [index]);
        _setDrawing(true);
      case FileKernelSubtitle(:final path):
        _ffi('setMedia.subtitle', () => p.setMedia(path, mdk.MediaType.subtitle));
        _ffi('activeSubtitleTracks', () => p.activeSubtitleTracks = const [0]);
        _setDrawing(true);
    }
    _decoding = plan.subtitle;
    _trackLog.add({
      'atMs': _now.inMilliseconds,
      'plan': plan.toJson(),
    });
  }

  void _setDrawing(bool on) {
    _drawing = on;
    _player.setProperty('subtitle', on ? '1' : '0');
  }

  @override
  Future<KernelTracks> selectSubtitle(KernelSubtitle subtitle,
          {Duration? probe}) =>
      _queue.run(() async {
        if (!_opened) throw StateError('The media is not open.');
        final current = _drawing ? _decoding : KernelSubtitle.none;
        if (subtitle == current && _tracks.subtitleConfirmed) return _tracks;
        _trackLog.add({
          'atMs': _now.inMilliseconds,
          'select': subtitle.toJson(),
          'from': current.toJson(),
          'decoding': _decoding.toJson(),
        });
        // Off, or back on to what MDK still decodes: only whether it draws.
        if (!subtitle.drawn || subtitle == _decoding) {
          _setDrawing(subtitle.drawn);
          _awaitSubtitleDecoder = false;
          _confirm(_tracks.copyWith(
              subtitle: subtitle,
              subtitleConfirmed:
                  _player.getProperty('subtitle') == (subtitle.drawn ? '1' : '0'),
              basis: 'property'));
          return _tracks;
        }
        final from = _where();
        _watchStatus = true;
        final reported = _next('decoder.subtitle', trackConfirmWait);
        switch (subtitle) {
          case EmbeddedKernelSubtitle(:final index):
            if (_decoding is FileKernelSubtitle) {
              _ffi('setMedia.subtitle',
                  () => _player.setMedia('', mdk.MediaType.subtitle));
            }
            await _switchTracks(mdk.MediaType.subtitle, [index]);
          case FileKernelSubtitle(:final path):
            _ffi('setMedia.subtitle',
                () => _player.setMedia(path, mdk.MediaType.subtitle));
            await _switchTracks(mdk.MediaType.subtitle, const [0]);
          case NoKernelSubtitle():
        }
        _decoding = subtitle;
        _setDrawing(true);
        var kept = false;
        try {
          // A text file MDK reads itself: no decoder reports it. Its text at
          // one of its lines does.
          if (subtitle is FileKernelSubtitle && probe != null) {
            await _keepPosition(from);
            kept = true;
            final text = _player.subtitleText(time: probe.inMicroseconds / 1e6);
            _trackLog.add({
              'atMs': _now.inMilliseconds,
              'probe': {'atMs': probe.inMilliseconds, 'text': text},
            });
            if (text.trim().isNotEmpty) {
              _awaitSubtitleDecoder = false;
              _confirm(_tracks.copyWith(
                  subtitle: subtitle,
                  subtitleConfirmed: true,
                  basis: 'text_at_probe'));
              return _tracks;
            }
          }
          final event = await reported;
          _queue.live();
          if (!kept) await _keepPosition(from);
          _awaitSubtitleDecoder = event == null;
          _confirm(_tracks.copyWith(
              subtitle: subtitle,
              subtitleConfirmed: event != null && event.error >= 0,
              basis: event == null
                  ? 'not_reported'
                  : event.error >= 0
                      ? 'decoder_open'
                      : 'decoder_failed'));
          return _tracks;
        } finally {
          _watchStatus = false;
        }
      });

  @override
  Future<KernelTracks> selectAudio(int index) => _queue.run(() async {
        if (!_opened) throw StateError('The media is not open.');
        if (_tracks.audio == index && _tracks.audioConfirmed) return _tracks;
        _trackLog.add({'atMs': _now.inMilliseconds, 'selectAudio': index});
        final from = _where();
        _watchStatus = true;
        try {
          final reported = _next('decoder.audio', trackConfirmWait);
          await _switchTracks(mdk.MediaType.audio, [index]);
          final event = await reported;
          _queue.live();
          await _keepPosition(from);
          _awaitAudioDecoder = event == null;
          _confirm(_tracks.copyWith(
              audio: () => index,
              audioConfirmed: event != null && event.error >= 0,
              basis: event == null
                  ? 'not_reported'
                  : event.error >= 0
                      ? 'decoder_open'
                      : 'decoder_failed'));
          return _tracks;
        } finally {
          _watchStatus = false;
        }
      });

  /// MDK changes a track by seeking to where it is (and while that seek
  /// runs its position can read far off, as seen paused: +9.6 s), and may
  /// land on the keyframe before. So: its own seek is waited out (it
  /// begins within a moment of the change, or not at all), then the
  /// position goes back where it would be if it is not there, unless a
  /// seek was asked meanwhile (that one runs next, in this queue). The
  /// clock gets the position only once it is settled.
  Future<void> _keepPosition(Duration from) async {
    final ticket = _seekTicket;
    final started = _now;
    if (!_seeking) {
      await (_seekBegan ??= Completer<void>())
          .future
          .timeout(const Duration(milliseconds: 250), onTimeout: () {});
      _queue.live();
    }
    if (_seeking) {
      await (_seekSettled ??= Completer<void>())
          .future
          .timeout(const Duration(seconds: 2), onTimeout: () {});
      _queue.live();
    }
    final playing = _observed == KernelTransport.playing;
    final expected = playing ? from + (_now - started) * _rate : from;
    final at = _position();
    if (ticket == _seekTicket && (at - expected).abs() > trackSeekTolerance) {
      final landed = await _player
          .seek(
              position: expected.inMilliseconds,
              flags: const mdk.SeekFlag(mdk.SeekFlag.fromStart))
          .timeout(const Duration(seconds: 3), onTimeout: () => -3);
      _queue.live();
      _trackLog.add({
        'atMs': _now.inMilliseconds,
        'keptPosition': {
          'fromMs': from.inMilliseconds,
          'foundMs': at.inMilliseconds,
          'seekMs': expected.inMilliseconds,
          'landed': landed,
        }
      });
      _sample(landed >= 0 ? Duration(milliseconds: landed) : expected,
          advancing: playing);
      return;
    }
    // The reading just checked, not another (one read after a good one
    // came back 9.6 s off while MDK settled).
    _sample(at, advancing: playing);
  }

  /// What the subtitle look asks that MDK cannot do: it has no subtitle delay.
  static const _mdkCannot = {'subtitle.delay'};

  @override
  Future<void> setSubtitleProperties(Map<String, String> properties) =>
      _queue.run(() async {
        for (final e in properties.entries) {
          if (_mdkCannot.contains(e.key)) continue;
          if (_subtitleProperties[e.key] == e.value) continue;
          _player.setProperty(e.key, e.value);
          _subtitleProperties[e.key] = e.value;
        }
      });

  @override
  Future<String?> subtitleText({Duration? at}) => _queue.run(() async =>
      _player.subtitleText(time: at == null ? -1 : at.inMicroseconds / 1e6));

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
        await _setState(
            paused ? mdk.PlaybackState.paused : mdk.PlaybackState.playing);
        return waiter.future
            .timeout(const Duration(seconds: 2), onTimeout: () => _observed);
      });

  /// MDK draws nothing into the texture after `prepare` until it plays.
  @override
  Future<void> presentFrame() => _queue.run(() async {
        if (!_opened || _count('render.video') > 0) return;
        final at = _samplePosition;
        final landed = await _drawPaused(at, firstFrame: true);
        _sample(landed, advancing: false);
      });

  /// Paused, MDK does not draw the frame it seeks to (measured: the old
  /// picture stayed at 5:00 while the media was there), nor its first frame
  /// after `prepare`. So it plays, muted, until it says it plays and a
  /// couple of frames are drawn, pauses, and seeks back exactly to
  /// [target]: the picture is the frame a few hundredths of a second on,
  /// the position exactly [target]. Inside the driver, not told as a
  /// transport change (design §2.2). Returns where it is paused.
  Future<Duration> _drawPaused(Duration target,
      {bool firstFrame = false}) async {
    final watch = Stopwatch()..start();
    final rendered =
        firstFrame ? _next('render.video', const Duration(milliseconds: 600)) : null;
    mdk.MediaEvent? event;
    _flashing = true;
    try {
      _ffi('mute', () => _player.mute = true);
      final playing = _flashPlaying = Completer<void>();
      await _setState(mdk.PlaybackState.playing);
      await playing.future.timeout(const Duration(seconds: 1), onTimeout: () {});
      _queue.live();
      if (rendered != null) {
        event = await rendered;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      _queue.live();
      final paused = _flashPaused = Completer<void>();
      await _setState(mdk.PlaybackState.paused);
      await paused.future.timeout(const Duration(seconds: 1), onTimeout: () {});
      _queue.live();
    } finally {
      _flashing = false;
      _flashPlaying = null;
      _flashPaused = null;
      if (!fenced) _ffi('mute', () => _player.mute = false);
    }
    _observed = KernelTransport.paused;
    final playedTo = _player.position;
    final back = await _player
        .seek(
            position: target.inMilliseconds,
            flags: const mdk.SeekFlag(mdk.SeekFlag.fromStart))
        .timeout(const Duration(seconds: 3), onTimeout: () => -3);
    _queue.live();
    _times['drawPausedUs'] = watch.elapsedMicroseconds;
    _drawn++;
    _trackLog.add({
      'atMs': _now.inMilliseconds,
      'drawPaused': {
        'targetMs': target.inMilliseconds,
        'playedToMs': playedTo,
        'backMs': back,
        if (firstFrame) 'renderEvent': event?.detail,
        'ms': watch.elapsedMilliseconds,
      },
    });
    if (_trackLog.length > 40) _trackLog.removeAt(0);
    return back >= 0 ? Duration(milliseconds: back) : target;
  }

  /// Playing to draw a paused frame (above): not a transport change.
  bool _flashing = false;
  Completer<void>? _flashPlaying;
  Completer<void>? _flashPaused;
  int _drawn = 0;

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
          var landed = Duration(milliseconds: result);
          _endSent = false;
          // Paused, the picture follows only if MDK plays a moment; not if
          // another seek is already asked (it draws its own).
          if (_observed != KernelTransport.playing && ticket == _seekTicket) {
            landed = await _drawPaused(landed);
          }
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
          _sample(_where(), advancing: _observed == KernelTransport.playing);
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
          'tracks': {
            ..._tracks.toJson(),
            'decoding': _decoding.toJson(),
            'drawing': _drawing,
            'drawingProperty': _player.getProperty('subtitle'),
            'activeAudio': _player.activeAudioTracks,
            'activeSubtitles': _player.activeSubtitleTracks,
            'subtitleProperties': Map.of(_subtitleProperties),
            'log': List.of(_trackLog),
          },
          'lifecycle': lifecycle,
        };
      });

  // ---- MdkNative: the handle kernel control gets ----

  @override
  KernelNative get native => this;

  @override
  Future<Object?> version() => _queue.run(() async => {'mdk': _version()});

  @override
  Future<Map<String, NativeRead>> read(List<String> names) => _queue.run(() async => {
        for (final name in names)
          name: (value: _player.getProperty(name), error: null)
      });

  @override
  Future<void> write(String name, String value) =>
      _queue.run(() async => _player.setProperty(name, value));

  @override
  Future<List<String>> decoders({required bool video}) => _queue.run(
      () async => video ? _player.videoDecoders : _player.audioDecoders);

  @override
  Future<void> setDecoders(List<String> names, {required bool video}) =>
      _queue.run(() async => _player.setDecoders(
          video ? mdk.MediaType.video : mdk.MediaType.audio, names));

  @override
  Future<String?> activeDecoder({required bool video}) => _queue.run(() async =>
      _seen[video ? 'decoder.video' : 'decoder.audio']?['detail'] as String?);

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
        'pausedFramesDrawn': _drawn,
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
      await _step('pause', () => _setState(mdk.PlaybackState.paused));
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
