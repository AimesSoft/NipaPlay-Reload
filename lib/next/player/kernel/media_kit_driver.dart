import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:media_kit/media_kit.dart' show Tracks;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/widgets/macos_native_video_view.dart';

import '../core/arbiter.dart';
import '../features/kernel_features.dart';
import 'adapter_driver.dart';
import 'driver.dart';
import 'native.dart';

/// Media Kit (mpv) as a [KernelDriver]. mpv draws into a Flutter texture,
/// or, with the macOS native video setting, into a native view under the
/// window ([PlatformVideoSurface]); that view must be on screen before the
/// media opens, so it is published first. The media opens at its start
/// position (`start` for this file), paused, with its tracks as the plan
/// says (`aid`, `sid` as options of the file), and mpv tells every change
/// of state, position and buffering, and its end.
///
/// A track is confirmed by reading `aid` and `sid` back from mpv. The
/// media's own track `i` is mpv's track `i + 1` (mpv numbers each kind from
/// 1 in container order); the open checks that against the tracks mpv
/// lists and corrects it if they differ. A subtitle file is mounted with
/// `sub-add … select` after the open.
///
/// The teardown order is a789943e's: the video output frees mpv's render
/// context before mpv is destroyed, which [MediaKitPlayerAdapter]'s
/// disposal does in that order and this driver waits for.
final class MediaKitDriver extends AdapterDriver
    implements MpvNative, KernelFrameFeatures {
  factory MediaKitDriver(KernelLease lease, KernelConfig config) {
    requireLease(lease, 'Media Kit');
    final megabytes = config.settings['player.precacheBufferSizeMb'];
    return MediaKitDriver._(
        config,
        MediaKitPlayerAdapter(
            sessionOwned: true,
            bufferSize: megabytes is int ? megabytes * 1024 * 1024 : null,
            httpProxy: config.settings['network.httpProxy'] as String?));
  }

  MediaKitDriver._(KernelConfig config, this.adapter) : super(config) {
    final stream = adapter.sessionPlayer.stream;
    listen(stream.playing, (playing) => transportChanged(
        playing ? KernelTransport.playing : KernelTransport.paused));
    listen(stream.position, positionChanged);
    listen(stream.buffering, bufferingChanged);
    listen(stream.completed, (done) {
      if (done) ended();
    });
    listen(stream.error, failed);
    listen(adapter.textureId.toStream(), (_) => _texture());
  }

  final MediaKitPlayerAdapter adapter;

  @override
  KernelId get kernel => KernelId.mediaKit;
  @override
  KernelNative get native => this;
  @override
  final KernelCapabilities capabilities = const KernelCapabilities(
    transportEvents: true,
    seekConfirm: true,
    bufferingTelemetry: true,
    endEvent: true,
    openAtPosition: true,
    trackConfirm: true,
    subtitleFiles: {'ass', 'ssa', 'sup', 'idx'},
    subtitleScale: true,
    subtitleDelay: true,
    subtitleText: true,
  );

  /// The tracks mpv has on, as indices of the media's own lists (null: none
  /// or one outside them), read back from mpv at every change.
  int? _audio, _subtitle;

  // ---- the kernel's part ----

  @override
  void applyVolume(double volume) => adapter.volume = volume;

  @override
  void applyRate(double rate) => adapter.playbackRate = rate;

  @override
  Future<void> configure() async {
    for (final entry in config.properties.entries) {
      adapter.setProperty(entry.key, entry.value);
    }
  }

  /// A source that asks to go direct (a mesh or local proxy address) goes
  /// without the proxy this player was made with.
  @override
  Future<void> routeSource(ResolvedSource source) async {
    if (source.direct) adapter.setProperty('http-proxy', '');
  }

  @override
  Future<void> applyPlan(KernelTrackPlan plan) async {
    // As options of the file: mpv opens with exactly these.
    if (plan.audio case final audio?) adapter.setProperty('aid', '${audio + 1}');
    adapter.setProperty(
        'sid',
        switch (plan.subtitle) {
          EmbeddedKernelSubtitle(:final index) => '${index + 1}',
          _ => 'no',
        });
    await applySubtitleProperties(plan.subtitleProperties);
  }

  Widget _nativeView() => adapter.usesWindowOverlayVideoSurface
      ? MacOSWindowNativeVideoOverlaySurface(
          player: adapter, debugLabel: 'next-media-kit-$instance')
      : MacOSNativeVideoView(
          player: adapter, debugLabel: 'next-media-kit-$instance');

  @override
  Future<Duration> openMedia(ResolvedSource source, Duration start) async {
    if (adapter.prefersPlatformVideoSurface) {
      // The native view takes the media when it attaches: it is shown first.
      picture = PlatformVideoSurface(_nativeView(), aspect: 16 / 9);
    }
    adapter.openForSession(source.uri, start);
    final ready = await adapter.waitUntilMediaReady(timeout: AdapterDriver.openTimeout);
    queue.live();
    if (!ready) {
      throw KernelOpenFailure(
          adapter.hasMediaLoadFailed ? 'media_open' : 'media_ready_timeout',
          adapter.mediaLoadError ?? 'mpv did not open the media.');
    }
    await _lengthAndTracksListed();
    queue.live();
    await adapter.prepare();
    queue.live();
    if (start <= Duration.zero) return Duration.zero;
    // mpv's first position is where the start took it.
    if ((lastKnownPosition - start).abs() <= const Duration(milliseconds: 1500)) {
      return lastKnownPosition;
    }
    final sample = expectSample(start);
    try {
      return await sample.landed ?? await readPosition() ?? start;
    } finally {
      sample.cancel();
    }
  }

  /// mpv says the media is ready on the first of its length or its tracks;
  /// the media's facts are read once it has both.
  Future<void> _lengthAndTracksListed() async {
    final player = adapter.sessionPlayer;
    bool listed(Tracks tracks) =>
        tracks.video.any((t) => int.tryParse(t.id) != null) ||
        tracks.audio.any((t) => int.tryParse(t.id) != null);
    if (player.state.duration <= Duration.zero) {
      await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5), onTimeout: () => Duration.zero);
    }
    if (listed(player.state.tracks)) return;
    await player.stream.tracks.firstWhere(listed).timeout(
        const Duration(seconds: 2), onTimeout: () => player.state.tracks);
  }

  // ---- tracks ----

  int _indexOf(List<dynamic>? infos, String? id) {
    if (infos == null || id == null) return -1;
    for (var i = 0; i < infos.length; i++) {
      if ((infos[i] as dynamic).metadata['id'] == id) return i;
    }
    return -1;
  }

  /// mpv's `aid` and `sid`, read back, as indices of the media's lists.
  Future<void> _readTracks() async {
    final read = await adapter.readMpvPropertiesChecked(['aid', 'sid']);
    queue.live();
    final aid = read['aid']?.value;
    final sid = read['sid']?.value;
    final audio = _indexOf(adapter.mediaInfo.audio, aid);
    final subtitle = _indexOf(adapter.mediaInfo.subtitle, sid);
    _audio = audio < 0 ? null : audio;
    _subtitle = subtitle < 0 ? null : subtitle;
    _sidOn = sid != null && sid != 'no' && sid != '';
  }

  bool _sidOn = false;

  @override
  Future<KernelTracks> planOpened(KernelTrackPlan plan, MediaFacts media) async {
    final fps = (await adapter.readMpvPropertiesChecked(['container-fps']))['container-fps']
        ?.value;
    _fps = double.tryParse(fps ?? '');
    await _readTracks();
    var basis = 'property';
    // The plan said `i + 1`; where mpv lists them otherwise, the right one
    // is put on now.
    if (plan.audio case final audio? when _audio != audio) {
      await adapter.selectTracksForSession(audio: audio);
      await _readTracks();
      basis = 'corrected';
    }
    switch (plan.subtitle) {
      case NoKernelSubtitle():
        if (_sidOn) {
          await adapter.selectTracksForSession(subtitles: const []);
          await _readTracks();
          basis = 'corrected';
        }
      case EmbeddedKernelSubtitle(:final index):
        if (_subtitle != index) {
          await adapter.selectTracksForSession(subtitles: [index]);
          await _readTracks();
          basis = 'corrected';
        }
      case FileKernelSubtitle(:final path):
        await adapter.mountSubtitleForSession(path);
        await _readTracks();
    }
    final subtitleOk = switch (plan.subtitle) {
      NoKernelSubtitle() => !_sidOn,
      EmbeddedKernelSubtitle(:final index) => _subtitle == index,
      FileKernelSubtitle() => _sidOn && _subtitle == null,
    };
    return KernelTracks(
        audio: plan.audio,
        subtitle: plan.subtitle,
        audioConfirmed: plan.audio == null || _audio == plan.audio,
        subtitleConfirmed: subtitleOk,
        basis: basis);
  }

  @override
  Future<TrackReport> switchAudio(int index) async {
    await adapter.selectTracksForSession(audio: index);
    await _readTracks();
    final ok = _audio == index;
    return (confirmed: ok, basis: ok ? 'property' : 'not_reported');
  }

  @override
  Future<TrackReport> switchSubtitle(
      KernelSubtitle subtitle, Duration? probe) async {
    switch (subtitle) {
      case NoKernelSubtitle():
        await adapter.selectTracksForSession(subtitles: const []);
      case EmbeddedKernelSubtitle(:final index):
        await adapter.selectTracksForSession(subtitles: [index]);
      case FileKernelSubtitle(:final path):
        await adapter.mountSubtitleForSession(path);
    }
    await _readTracks();
    final ok = switch (subtitle) {
      NoKernelSubtitle() => !_sidOn,
      EmbeddedKernelSubtitle(:final index) => _subtitle == index,
      FileKernelSubtitle() => _sidOn && _subtitle == null,
    };
    return (confirmed: ok, basis: ok ? 'property' : 'not_reported');
  }

  /// MDK's names for how subtitles are drawn, as mpv's options.
  @override
  Future<void> applySubtitleProperties(Map<String, String> properties) async {
    String? color(String? rgba) {
      // MDK: 0xRRGGBBAA. mpv: #AARRGGBB.
      final hex = rgba?.replaceFirst('0x', '');
      return hex == null || hex.length != 8
          ? null
          : '#${hex.substring(6)}${hex.substring(0, 6)}';
    }

    final options = <String, String?>{
      'sub-scale': properties['subtitle.scale'],
      'sub-color': color(properties['subtitle.color']),
      'sub-border-color': color(properties['subtitle.color.outline']),
      'sub-bold': properties['subtitle.bold'] == null
          ? null
          : properties['subtitle.bold'] == '1' ? 'yes' : 'no',
      'sub-italic': properties['subtitle.italic'] == null
          ? null
          : properties['subtitle.italic'] == '1' ? 'yes' : 'no',
      'sub-delay': properties['subtitle.delay'],
    };
    for (final entry in options.entries) {
      final value = entry.value;
      if (value == null) continue;
      // Before the media opens they are the file's options; after, mpv's now.
      if (opened) {
        await adapter.writeMpvProperty(entry.key, value);
      } else {
        adapter.setProperty(entry.key, value);
      }
    }
  }

  @override
  Future<String?> readSubtitleText(Duration? at) async {
    if (at != null) return null;
    final read = await adapter.readMpvPropertiesChecked(['sub-text']);
    return read['sub-text']?.value;
  }

  @override
  Future<void> seekMedia(Duration target, {required bool exact}) =>
      adapter.seekForSession(target);

  @override
  Future<void> pauseMedia(bool paused) =>
      paused ? adapter.pauseDirectly() : adapter.playDirectly();

  @override
  Future<Duration?> readPosition() async {
    final read = (await adapter.readMpvPropertiesChecked(['time-pos']))['time-pos'];
    final seconds = double.tryParse(read?.value ?? '');
    return seconds == null
        ? null
        : Duration(microseconds: (seconds * 1000000).round());
  }

  double? _fps;

  @override
  MediaFacts readMedia() => mediaFromInfo(adapter.mediaInfo,
      activeAudio: [if (_audio != null) _audio!],
      activeSubtitles: [if (_subtitle != null) _subtitle!],
      frameRate: _fps);

  // ---- frames (design: the kernel's own primitives, in the queue) ----

  /// mpv steps a frame itself and pauses there; it says where it landed
  /// by the position it then reports.
  @override
  Future<SeekOutcome> stepFrame(int delta) => queue.run(() async {
        final from = lastKnownPosition;
        final landed = expectSample(from);
        try {
          final reply = await adapter.runMpvCommand(
              [delta < 0 ? 'frame-back-step' : 'frame-step']);
          queue.live();
          if (reply.error != null) {
            return const SeekOutcome(SeekResult.rejected, null);
          }
          final at = await landed.landed ?? await readPosition();
          queue.live();
          if (at == null) return const SeekOutcome(SeekResult.rejected, null);
          return SeekOutcome(SeekResult.done, at);
        } finally {
          landed.cancel();
        }
      });

  /// mpv's own screenshot, subtitles drawn by libass in it, decoded to RGBA
  /// off the main isolate by the engine's codec.
  @override
  Future<KernelPicture> snapshotPicture() => queue.run(() async {
        final bytes = await adapter.sessionPlayer
            .screenshot(format: 'image/png', includeLibassSubtitles: true);
        queue.live();
        if (bytes == null || bytes.isEmpty) {
          throw StateError('mpv returned no picture.');
        }
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          final rgba = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
          final picture = KernelPicture(frame.image.width, frame.image.height,
              rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes));
          frame.image.dispose();
          return picture;
        } finally {
          codec.dispose();
        }
      });

  @override
  Future<void> showPicture(MediaFacts media) async {
    if (adapter.prefersPlatformVideoSurface) return;
    // The texture exists once the first frame has been rendered.
    if (adapter.textureId.value == null) {
      final made = Completer<void>();
      void changed() {
        if (adapter.textureId.value != null && !made.isCompleted) made.complete();
      }

      adapter.textureId.addListener(changed);
      try {
        await made.future.timeout(const Duration(seconds: 5), onTimeout: () {});
      } finally {
        adapter.textureId.removeListener(changed);
      }
      queue.live();
    }
    _texture();
  }

  /// The texture id changes with the video's size; the picture follows it.
  void _texture() {
    final id = adapter.textureId.value;
    final facts = media;
    if (fenced || adapter.prefersPlatformVideoSurface || id == null || facts == null) {
      return;
    }
    picture = TextureSurface(id, width: facts.width, height: facts.height);
  }

  @override
  Future<JsonMap> kernelFacts() async {
    final read = await adapter.readMpvPropertiesChecked([
      'hwdec-current',
      'video-codec',
      'audio-codec',
      'demuxer-cache-time',
      'time-pos',
      'container-fps',
      'file-format',
      'file-size',
    ]);
    String? value(String name) => read[name]?.value;
    final cache = double.tryParse(value('demuxer-cache-time') ?? '');
    final position = double.tryParse(value('time-pos') ?? '');
    return {
      'version': await _version(),
      'decoders': {
        'video': value('hwdec-current') ?? value('video-codec'),
        'audio': value('audio-codec'),
        'requested': config.videoDecoders,
      },
      'bufferedAheadMs':
          cache == null || position == null ? null : ((cache - position) * 1000).round(),
    };
  }

  @override
  Future<void> disposeKernel() => adapter.disposeAsync();

  // ---- MpvNative: the handle kernel control gets ----

  @override
  Future<Object?> version() => queue.run(_version);

  Future<Object?> _version() async {
    final read = await adapter.readMpvPropertiesChecked(['mpv-version', 'ffmpeg-version']);
    return {
      'mpv': read['mpv-version']?.value,
      'ffmpeg': read['ffmpeg-version']?.value,
    };
  }

  @override
  Future<Map<String, NativeRead>> read(List<String> names) =>
      queue.run(() => adapter.readMpvPropertiesChecked(names));

  @override
  Future<String?> write(String name, String value) =>
      queue.run(() => adapter.writeMpvProperty(name, value));

  @override
  Future<NativeReply> command(List<String> args,
          {Duration timeout = const Duration(seconds: 10)}) =>
      queue.alongside(() => adapter.runMpvCommand(args, timeout: timeout));

  @override
  Future<void> logFile(String path) =>
      queue.run(() => adapter.setNativeLogFile(path));
}

extension on ValueListenable<int?> {
  /// Its changes as a stream, for the driver's fenced [listen].
  Stream<int?> toStream() {
    late final StreamController<int?> controller;
    void changed() => controller.add(value);
    controller = StreamController<int?>(
      onListen: () => addListener(changed),
      onCancel: () => removeListener(changed),
    );
    return controller.stream;
  }
}
