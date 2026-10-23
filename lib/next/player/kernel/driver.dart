import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';

import '../../harness_redaction.dart';
import '../features/kernel_features.dart' show ChapterFacts;

/// The playback kernels, by the ids facts use.
enum KernelId {
  mdk('mdk', 'MDK'),
  mediaKit('media_kit', 'Media Kit'),
  erika('erika', 'Erika'),
  videoPlayer('video_player', 'Video Player');

  const KernelId(this.id, this.label);
  final String id;
  final String label;

  static KernelId? byId(String? id) =>
      values.where((k) => k.id == id).firstOrNull;
}

/// What a kernel instance was created with, kept as a fact: it does not
/// change while the instance lives (I6); another value means another
/// instance.
@immutable
final class KernelConfig {
  const KernelConfig({
    required this.kernel,
    this.videoDecoders = const [],
    this.hardwareDecoding = true,
    this.bufferMaxMs,
    this.properties = const {},
  });

  final KernelId kernel;

  /// The ordered video decoders asked of the kernel.
  final List<String> videoDecoders;
  final bool hardwareDecoding;

  /// How far ahead the kernel may read, when the setting says.
  final int? bufferMaxMs;

  /// Kernel properties set before the media opens.
  final Map<String, String> properties;

  JsonMap toJson() => {
        'kernel': kernel.id,
        'videoDecoders': videoDecoders,
        'hardwareDecoding': hardwareDecoding,
        'bufferMaxMs': bufferMaxMs,
        'properties': properties,
      };
}

/// What a kernel tells and confirms, fixed per kernel.
@immutable
final class KernelCapabilities {
  const KernelCapabilities({
    required this.transportEvents,
    required this.seekConfirm,
    required this.bufferingTelemetry,
    required this.endEvent,
    required this.openAtPosition,
  });

  /// Play and pause are told by the kernel (not inferred from the clock).
  final bool transportEvents;

  /// A seek answers with where it landed, or that it was superseded or
  /// turned away.
  final bool seekConfirm;
  final bool bufferingTelemetry;

  /// The kernel says when the media ended.
  final bool endEvent;

  /// The media opens at a position, the first frame there.
  final bool openAtPosition;

  JsonMap toJson() => {
        'transportEvents': transportEvents,
        'seekConfirm': seekConfirm,
        'bufferingTelemetry': bufferingTelemetry,
        'endEvent': endEvent,
        'openAtPosition': openAtPosition,
      };
}

/// What the kernel opens: [uri] is what it is given, [locator] what was
/// asked for.
@immutable
final class ResolvedSource {
  const ResolvedSource(
      {required this.locator, required this.uri, required this.kind});
  final String locator;
  final String uri;

  /// local (P1); network kinds arrive with the sources.
  final String kind;

  JsonMap toJson() => {'kind': kind, 'path': redactHarnessText(locator)};
}

/// One stream of the media, as the kernel lists it.
@immutable
final class TrackFacts {
  const TrackFacts({
    required this.index,
    this.codec,
    this.title,
    this.language,
    this.channels,
    this.sampleRate,
  });
  final int index;
  final String? codec;
  final String? title;
  final String? language;
  final int? channels;
  final int? sampleRate;

  JsonMap toJson() => {
        'index': index,
        'codec': codec,
        'title': title,
        'language': language,
        if (channels != null) 'channels': channels,
        if (sampleRate != null) 'sampleRate': sampleRate,
      };
}

/// The media, as the kernel reported it when it opened.
@immutable
final class MediaFacts {
  const MediaFacts({
    required this.duration,
    this.width = 0,
    this.height = 0,
    this.videoCodec,
    this.frameRate,
    this.format,
    this.bitRate,
    this.audio = const [],
    this.subtitles = const [],
    this.activeAudio = const [],
    this.activeSubtitles = const [],
    this.chapters = const [],
  });

  final Duration duration;
  final int width;
  final int height;
  final String? videoCodec;
  final double? frameRate;
  final String? format;
  final int? bitRate;
  final List<TrackFacts> audio;
  final List<TrackFacts> subtitles;

  /// The tracks the kernel has on (its own default until a choice is made).
  final List<int> activeAudio;
  final List<int> activeSubtitles;
  final List<ChapterFacts> chapters;

  bool get hasVideo => width > 0 && height > 0;
  double get aspect => hasVideo ? width / height : 16 / 9;

  JsonMap toJson() => {
        'durationMs': duration.inMilliseconds,
        'width': width,
        'height': height,
        'videoCodec': videoCodec,
        'frameRate': frameRate,
        'format': format,
        'bitRate': bitRate,
        'audio': [for (final t in audio) t.toJson()],
        'subtitles': [for (final t in subtitles) t.toJson()],
        'activeAudio': activeAudio,
        'activeSubtitles': activeSubtitles,
        'chapters': [for (final c in chapters) c.toJson()],
      };
}

/// Whether the kernel plays, as it says.
enum KernelTransport { stopped, paused, playing }

enum SeekResult { done, superseded, rejected }

/// What a kernel instance says. Every event names its instance and comes
/// in order ([seq]); [at] is the playback layer's monotonic time.
sealed class KernelEvent {
  KernelEvent(this.instance, this.seq, this.at);
  final int instance;
  final int seq;
  final Duration at;
}

final class KernelTransportChanged extends KernelEvent {
  KernelTransportChanged(super.instance, super.seq, super.at, this.transport);
  final KernelTransport transport;
}

/// Where the kernel is: sent at a transport change, after a seek and when
/// the kernel drifts from where its own last sample runs on to.
final class KernelPositionSample extends KernelEvent {
  KernelPositionSample(super.instance, super.seq, super.at,
      {required this.position, required this.rate, required this.advancing});
  final Duration position;
  final double rate;
  final bool advancing;
}

final class KernelBuffering extends KernelEvent {
  KernelBuffering(super.instance, super.seq, super.at, this.buffering);
  final bool buffering;
}

/// The media played to its end. [inferred]: the kernel said nothing; its
/// position stood still at the end while it played.
final class KernelEnded extends KernelEvent {
  KernelEnded(super.instance, super.seq, super.at, {this.inferred = false});
  final bool inferred;
}

/// The kernel failed after the media opened.
final class KernelFailed extends KernelEvent {
  KernelFailed(super.instance, super.seq, super.at,
      {required this.stage, required this.message, this.retryable});
  final String stage;
  final String message;
  final bool? retryable;
}

/// Where the picture is. The interface only ever gets this, never the
/// kernel (I3).
sealed class VideoSurface {
  const VideoSurface();
  double get aspect;
}

/// A Flutter texture the kernel renders into.
final class TextureSurface extends VideoSurface {
  const TextureSurface(this.textureId,
      {required this.width, required this.height});
  final int textureId;
  final int width;
  final int height;
  @override
  double get aspect => width > 0 && height > 0 ? width / height : 16 / 9;
}

final class KernelOpened {
  const KernelOpened(this.media, this.landed);
  final MediaFacts media;

  /// Where the first frame is.
  final Duration landed;
}

final class SeekOutcome {
  const SeekOutcome(this.result, this.landed, {this.code});
  final SeekResult result;
  final Duration? landed;

  /// The kernel's own answer when it turned the seek away.
  final int? code;
}

/// A call on a driver that is being or has been released (I2, I5).
final class KernelFenced implements Exception {
  const KernelFenced();
  @override
  String toString() => 'KernelFenced: the kernel instance is released';
}

/// The media did not open; [stage] as playback.failures names them.
final class KernelOpenFailure implements Exception {
  const KernelOpenFailure(this.stage, this.message, {this.code});
  final String stage;
  final String message;
  final int? code;
  @override
  String toString() => 'KernelOpenFailure($stage): $message';
}

/// One kernel instance, for one session (I6). Events are its only state;
/// commands wait for the kernel to confirm; nothing here reaches the
/// interface but [surface]. [release] fences the instance at once and
/// tears it down in a fixed order (I2, I4).
abstract interface class KernelDriver {
  KernelId get kernel;

  /// This instance among all the drivers of the process.
  int get instance;
  KernelConfig get config;
  KernelCapabilities get capabilities;
  Stream<KernelEvent> get events;
  ValueListenable<VideoSurface?> get surface;
  bool get fenced;

  /// Opens [source] at [start], paused, at [volume] and [rate]. Completes
  /// once the first frame is decoded and the picture is up; throws
  /// [KernelOpenFailure] when the media does not open.
  Future<KernelOpened> open(ResolvedSource source,
      {Duration start = Duration.zero, double volume = 1, double rate = 1});

  /// Completes with the transport the kernel reports afterwards (the one
  /// it had when it did not confirm within 2 s).
  Future<KernelTransport> setPaused(bool paused);

  /// [exact]: the frame at [target]; otherwise the keyframe the kernel
  /// picks. A seek asked before an earlier one ran replaces it
  /// ([SeekResult.superseded]).
  Future<SeekOutcome> seek(Duration target, {bool exact = true});
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);

  /// What the kernel reports about the media and itself now, read in its
  /// queue (playback.info).
  Future<JsonMap> readFacts();

  /// Creation, opening and release of this instance: timings, the late
  /// callbacks dropped behind the fence, release steps that timed out.
  JsonMap get lifecycle;

  /// Idempotent. The first call fences the instance before it returns
  /// its future; the future completes once the instance is gone.
  Future<void> release();
}
