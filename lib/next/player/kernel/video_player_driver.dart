import 'dart:async';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:video_player/video_player.dart';

import '../core/arbiter.dart';
import 'adapter_driver.dart';
import 'driver.dart';
import 'native.dart';

/// video_player as a [KernelDriver], on the controller itself: a texture,
/// a state the platform reports through the controller's value, no list of
/// tracks and no choice among them, and no subtitles. It says that plainly
/// ([listsTracks], [UnsupportedError]) rather than making the facts up.
///
/// The controller's disposal is awaited: the instance is gone when
/// [release] completes.
final class VideoPlayerDriver extends AdapterDriver {
  factory VideoPlayerDriver(KernelLease lease, KernelConfig config) {
    requireLease(lease, 'video_player');
    return VideoPlayerDriver._(config);
  }

  VideoPlayerDriver._(super.config);

  VideoPlayerController? _controller;
  bool _completed = false;

  @override
  KernelId get kernel => KernelId.videoPlayer;
  @override
  KernelNative get native => const PlainNative(null);
  @override
  final KernelCapabilities capabilities = const KernelCapabilities(
    transportEvents: true,
    seekConfirm: true,
    bufferingTelemetry: true,
    endEvent: true,
    openAtPosition: false,
  );
  @override
  bool get listsTracks => false;

  double _volume = 1;
  double _speed = 1;

  void _changed() {
    final controller = _controller;
    if (fenced || controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      failed(value.errorDescription ?? 'video_player reported an error.');
      return;
    }
    transportChanged(
        value.isPlaying ? KernelTransport.playing : KernelTransport.paused);
    positionChanged(value.position);
    bufferingChanged(value.isBuffering);
    if (value.isCompleted && !_completed) {
      _completed = true;
      ended();
    } else if (!value.isCompleted) {
      _completed = false;
    }
  }

  // ---- the kernel's part ----

  @override
  void applyVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _controller?.setVolume(_volume);
  }

  @override
  void applyRate(double rate) {
    _speed = rate;
    _controller?.setPlaybackSpeed(rate);
  }

  @override
  Future<void> configure() async {}

  @override
  Future<Duration> openMedia(ResolvedSource source, Duration start) async {
    final uri = Uri.tryParse(source.uri);
    final controller = _controller = uri != null &&
            uri.hasScheme &&
            uri.scheme != 'file' &&
            uri.scheme.length > 1
        ? VideoPlayerController.networkUrl(uri)
        : VideoPlayerController.file(
            File(uri != null && uri.scheme == 'file' ? uri.toFilePath() : source.uri));
    await controller.initialize();
    queue.live();
    await controller.setVolume(_volume);
    await controller.setPlaybackSpeed(_speed);
    queue.live();
    if (start > Duration.zero) {
      await controller.seekTo(start);
      queue.live();
    }
    controller.addListener(_changed);
    return await controller.position ?? start;
  }

  @override
  Future<void> seekMedia(Duration target, {required bool exact}) async {
    _completed = false;
    await _controller?.seekTo(target);
  }

  @override
  Future<void> pauseMedia(bool paused) async {
    final controller = _controller;
    if (controller == null) return;
    await (paused ? controller.pause() : controller.play());
  }

  @override
  Future<Duration?> readPosition() async => _controller?.position;

  @override
  MediaFacts readMedia() {
    final value = _controller!.value;
    return MediaFacts(
      duration: value.duration,
      width: value.size.width.round(),
      height: value.size.height.round(),
    );
  }

  @override
  Future<void> showPicture(MediaFacts media) async {
    // video_player gives the id its own VideoPlayer widget draws and no
    // other way to reach it.
    // ignore: invalid_use_of_visible_for_testing_member
    final id = _controller!.textureId;
    picture = TextureSurface(id, width: media.width, height: media.height);
  }

  // ---- tracks: video_player lists none and draws no subtitle ----

  @override
  Future<KernelTracks> planOpened(KernelTrackPlan plan, MediaFacts media) async =>
      KernelTracks(
          audio: plan.audio,
          subtitle: KernelSubtitle.none,
          // It cannot select an audio track; it draws no subtitle, which is
          // what none is.
          audioConfirmed: plan.audio == null,
          subtitleConfirmed: !plan.subtitle.drawn,
          basis: 'unsupported');

  @override
  Future<TrackReport> switchAudio(int index) =>
      throw UnsupportedError('video_player lists and selects no audio tracks.');

  @override
  Future<TrackReport> switchSubtitle(KernelSubtitle subtitle, Duration? probe) {
    if (!subtitle.drawn) {
      return Future.value((confirmed: true, basis: 'unsupported'));
    }
    throw UnsupportedError('video_player draws no subtitles.');
  }

  @override
  Future<void> applySubtitleProperties(Map<String, String> properties) async {}

  @override
  Future<JsonMap> kernelFacts() async => {
        'version': null,
        'decoders': {'video': null, 'audio': null, 'requested': config.videoDecoders},
        'bufferedAheadMs': _bufferedAhead(),
      };

  int? _bufferedAhead() {
    final value = _controller?.value;
    if (value == null || value.buffered.isEmpty) return null;
    final end = value.buffered
        .map((range) => range.end)
        .reduce((a, b) => a > b ? a : b);
    return (end - value.position).inMilliseconds;
  }

  @override
  Future<void> disposeKernel() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    controller.removeListener(_changed);
    await controller.dispose();
  }
}
