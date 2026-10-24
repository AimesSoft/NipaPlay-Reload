import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:nipa_harness/nipa_harness.dart';

import '../../harness_redaction.dart';
import '../features/kernel_features.dart' show ChapterFacts;
import 'native.dart';

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
    this.settings = const {},
  });

  final KernelId kernel;

  /// The ordered video decoders asked of the kernel.
  final List<String> videoDecoders;
  final bool hardwareDecoding;

  /// How far ahead the kernel may read, when the setting says.
  final int? bufferMaxMs;

  /// Kernel properties set before the media opens.
  final Map<String, String> properties;
  final Map<String, Object?> settings;

  JsonMap toJson() => {
        'kernel': kernel.id,
        'videoDecoders': videoDecoders,
        'hardwareDecoding': hardwareDecoding,
        'bufferMaxMs': bufferMaxMs,
        'properties': properties,
        'settings': settings,
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
    this.trackConfirm = false,
    this.subtitleFiles = const {},
    this.subtitleScale = false,
    this.subtitleDelay = false,
    this.subtitleText = false,
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

  /// A track change answers once the kernel reports it (a decoder opened
  /// for it, a property read back).
  final bool trackConfirm;

  /// The subtitle file formats (lowercase extensions) the kernel draws
  /// itself when mounted; any other file is drawn over the video.
  final Set<String> subtitleFiles;

  /// The kernel scales the subtitles it draws.
  final bool subtitleScale;

  /// The kernel shifts the subtitles it draws in time.
  final bool subtitleDelay;

  /// The kernel tells the text of the subtitle it draws now.
  final bool subtitleText;

  JsonMap toJson() => {
        'transportEvents': transportEvents,
        'seekConfirm': seekConfirm,
        'bufferingTelemetry': bufferingTelemetry,
        'endEvent': endEvent,
        'openAtPosition': openAtPosition,
        'trackConfirm': trackConfirm,
        'subtitleFiles': subtitleFiles.toList()..sort(),
        'subtitleScale': subtitleScale,
        'subtitleDelay': subtitleDelay,
        'subtitleText': subtitleText,
      };
}

/// The subtitle a kernel draws: none, one of the media's own tracks, or a
/// subtitle file mounted in the kernel.
sealed class KernelSubtitle {
  const KernelSubtitle();
  static const none = NoKernelSubtitle();

  bool get drawn => this is! NoKernelSubtitle;
  JsonMap toJson();
}

final class NoKernelSubtitle extends KernelSubtitle {
  const NoKernelSubtitle();
  @override
  JsonMap toJson() => const {'kind': 'none'};
  @override
  bool operator ==(Object other) => other is NoKernelSubtitle;
  @override
  int get hashCode => 0;
  @override
  String toString() => 'none';
}

final class EmbeddedKernelSubtitle extends KernelSubtitle {
  const EmbeddedKernelSubtitle(this.index);

  /// Among the media's subtitle tracks, from 0.
  final int index;
  @override
  JsonMap toJson() => {'kind': 'embedded', 'index': index};
  @override
  bool operator ==(Object other) =>
      other is EmbeddedKernelSubtitle && other.index == index;
  @override
  int get hashCode => Object.hash('embedded', index);
  @override
  String toString() => 'embedded $index';
}

final class FileKernelSubtitle extends KernelSubtitle {
  const FileKernelSubtitle(this.path);
  final String path;
  @override
  JsonMap toJson() => {'kind': 'file', 'path': redactHarnessText(path)};
  @override
  bool operator ==(Object other) =>
      other is FileKernelSubtitle && other.path == path;
  @override
  int get hashCode => Object.hash('file', path);
  @override
  String toString() => 'file $path';
}

/// The tracks a kernel instance opens with, set before the media opens so
/// that nothing has to switch afterwards (player-core design §2.3).
@immutable
final class KernelTrackPlan {
  const KernelTrackPlan({
    this.audio,
    this.subtitle = KernelSubtitle.none,
    this.subtitleProperties = const {},
    this.subtitleProbe,
  });

  /// The audio track, from 0; null: the kernel's own (the first).
  final int? audio;
  final KernelSubtitle subtitle;

  /// For a subtitle file: a time one of its lines is on, to confirm the
  /// kernel has it (see [KernelDriver.selectSubtitle]).
  final Duration? subtitleProbe;

  /// How the kernel draws subtitles (scale, font size, colours…), set
  /// before the media opens.
  final Map<String, String> subtitleProperties;

  JsonMap toJson() => {
        'audio': audio,
        'subtitle': subtitle.toJson(),
        'subtitleProperties': subtitleProperties,
      };
}

/// The tracks a kernel has on, as it reported them.
@immutable
final class KernelTracks {
  const KernelTracks({
    this.audio,
    this.subtitle = KernelSubtitle.none,
    this.audioConfirmed = false,
    this.subtitleConfirmed = false,
    this.basis,
  });

  /// The audio track the kernel was told; null: its own default.
  final int? audio;

  /// What the kernel draws.
  final KernelSubtitle subtitle;

  /// The kernel reported the change: a decoder opened for the track, or
  /// the property read back. False: told, not reported within the wait.
  final bool audioConfirmed;
  final bool subtitleConfirmed;

  /// What the last report was: decoder_open, property, opened, timeout…
  final String? basis;

  KernelTracks copyWith({
    int? Function()? audio,
    KernelSubtitle? subtitle,
    bool? audioConfirmed,
    bool? subtitleConfirmed,
    String? basis,
  }) =>
      KernelTracks(
        audio: audio == null ? this.audio : audio(),
        subtitle: subtitle ?? this.subtitle,
        audioConfirmed: audioConfirmed ?? this.audioConfirmed,
        subtitleConfirmed: subtitleConfirmed ?? this.subtitleConfirmed,
        basis: basis ?? this.basis,
      );

  JsonMap toJson() => {
        'audio': audio,
        'audioConfirmed': audioConfirmed,
        'subtitle': subtitle.toJson(),
        'subtitleConfirmed': subtitleConfirmed,
        'basis': basis,
      };

  @override
  bool operator ==(Object other) =>
      other is KernelTracks &&
      other.audio == audio &&
      other.subtitle == subtitle &&
      other.audioConfirmed == audioConfirmed &&
      other.subtitleConfirmed == subtitleConfirmed &&
      other.basis == basis;

  @override
  int get hashCode =>
      Object.hash(audio, subtitle, audioConfirmed, subtitleConfirmed, basis);
}

/// What the kernel opens: [uri] is what it is given, [locator] what was
/// asked for.
@immutable
final class ResolvedSource {
  const ResolvedSource(
      {required this.locator,
      required this.uri,
      required this.kind,
      this.direct = false,
      this.audioTrack,
      this.subtitleTrack,
      this.externalSubtitle});
  final String locator;
  final String uri;

  /// local (P1); network kinds arrive with the sources.
  final String kind;

  /// A per-open routing requirement, including mesh and local SMB proxies.
  final bool direct;

  /// Native ordinals resolved from the selected server version's streams.
  final int? audioTrack;
  final int? subtitleTrack;
  final String? externalSubtitle;

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
    this.chapters,
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
  /// Chapter metadata captured by the driver, never queried by the UI.
  /// Null: the kernel does not provide chapters (an empty list says the file
  /// has none).
  final List<ChapterFacts>? chapters;

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
        'chapters': chapters == null
            ? null
            : [for (final c in chapters!) c.toJson()],
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

/// The kernel reported the tracks it has on (after an open or a change).
final class KernelTracksChanged extends KernelEvent {
  KernelTracksChanged(super.instance, super.seq, super.at, this.tracks);
  final KernelTracks tracks;
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

/// A picture a Flutter widget of the kernel's package draws (video_player's
/// own view of its controller), fitted like a texture.
final class WidgetSurface extends VideoSurface {
  const WidgetSurface(this.view,
      {required this.width, required this.height});
  final Widget view;
  final int width;
  final int height;
  @override
  double get aspect => width > 0 && height > 0 ? width / height : 16 / 9;
}

/// A platform view with a fenced adapter behind it. No native getters in build.
final class PlatformVideoSurface extends VideoSurface {
  const PlatformVideoSurface(this.view, {required this.aspect});
  final Widget view;
  @override
  final double aspect;
}

final class KernelOpened {
  const KernelOpened(this.media, this.landed,
      [this.tracks = const KernelTracks()]);
  final MediaFacts media;

  /// Where the first frame is.
  final Duration landed;

  /// The tracks it opened with, as far as the kernel reported them then.
  final KernelTracks tracks;
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

  /// Opens [source] at [start], paused, at [volume] and [rate], with the
  /// [tracks] set before the media opens. Completes once the first frame is
  /// decoded and the picture is up; throws [KernelOpenFailure] when the
  /// media does not open.
  ///
  /// Tracks (every kernel): the kernel opens with exactly [tracks] — the
  /// audio track asked (its own first when null) and the subtitle asked,
  /// none meaning none (never a default track of its own). What it opened
  /// with is [KernelOpened.tracks] and a [KernelTracksChanged] event;
  /// `confirmed` there only once the kernel itself reported it (a decoder
  /// opened, its text at [KernelTrackPlan.subtitleProbe] for a file),
  /// later by another [KernelTracksChanged] when the report comes after.
  /// [KernelTrackPlan.subtitleProperties] are set before the media opens.
  /// The first subtitle line after [start] must be drawn (MDK needs a
  /// seek to the landing point for it).
  Future<KernelOpened> open(ResolvedSource source,
      {Duration start = Duration.zero,
      double volume = 1,
      double rate = 1,
      KernelTrackPlan tracks = const KernelTrackPlan()});

  /// The tracks the kernel has on, as last reported (never what was only
  /// asked and refused).
  KernelTracks get tracks;

  /// Puts on audio track [index] (from 0, among the media's own) while
  /// the media is open; in this instance's queue (I8), never while it
  /// stops. Completes with [tracks] after the kernel's report (a decoder
  /// opened for it: `audioConfirmed`, basis `decoder_open`) or, after
  /// about 1.5 s without one, as told and unconfirmed (basis
  /// `not_reported`); a [KernelTracksChanged] follows each change. If the
  /// change moved the position (MDK switches by seeking where it is), it
  /// is put back before this completes, unless a seek was asked meanwhile.
  /// Throws [KernelFenced] once released.
  Future<KernelTracks> selectAudio(int index);

  /// Draws [subtitle] and nothing else, as [selectAudio]:
  /// - [NoKernelSubtitle]: the kernel draws none. A kernel may keep
  ///   decoding what it drew (MDK only stops drawing, so that off and back
  ///   on deactivates nothing); confirmed when it reads back as off.
  /// - [EmbeddedKernelSubtitle]: the media's own subtitle track (from 0,
  ///   in the order [MediaFacts.subtitles] lists them).
  /// - [FileKernelSubtitle]: a subtitle file the kernel draws itself (only
  ///   formats in [KernelCapabilities.subtitleFiles]); one at a time, it
  ///   replaces whatever the kernel drew. A kernel that does not report
  ///   opening such a file is given [probe], a time one of its lines is
  ///   on: having text there confirms it (basis `text_at_probe`).
  /// Completes once the kernel draws [subtitle] as far as it reports; the
  /// session shows a file over the video only after the kernel reported
  /// none (the invariant: never two subtitles at once).
  Future<KernelTracks> selectSubtitle(KernelSubtitle subtitle,
      {Duration? probe});

  /// How the kernel draws subtitles from now on: the keys of
  /// `SubtitleLook.kernelProperties` (MDK's `subtitle.*` properties); a
  /// kernel maps them to its own, and reports what it cannot apply.
  Future<void> setSubtitleProperties(Map<String, String> properties);

  /// The text of the subtitle the kernel draws now, or has at [at]; null
  /// when it cannot tell ([KernelCapabilities.subtitleText]). For
  /// subtitle.cues (`kernelLine`) and to confirm a mounted file.
  Future<String?> subtitleText({Duration? at});

  /// Completes with the transport the kernel reports afterwards (the one
  /// it had when it did not confirm within 2 s).
  Future<KernelTransport> setPaused(bool paused);

  /// The media stays paused after it opened: the frame where it is goes
  /// up, if the kernel has not drawn one yet (MDK draws its first frame
  /// only once it plays). Not a transport change.
  Future<void> presentFrame();

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

  /// The kernel's own properties, commands and methods, for kernel control
  /// (playback.kernel and the rest): the one handle to the native player
  /// that leaves the driver, queued and fenced like its own calls (I3).
  KernelNative get native;

  /// Idempotent. The first call fences the instance before it returns
  /// its future; the future completes once the instance is gone.
  Future<void> release();
}
