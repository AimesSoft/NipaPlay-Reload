import 'dart:async';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/player_abstraction/player_enums.dart';

import '../core/arbiter.dart';
import '../features/kernel_features.dart';
import 'adapter_driver.dart';
import 'driver.dart';
import 'native.dart';
import 'versions.dart';

/// Reads container chapters from an Erika presenter that has just opened a
/// media. `null` is "this Erika cannot tell us": an older method table, an
/// unsupported library, or a failed read. An empty list is the kernel's own
/// answer that the file has no chapters.
Future<List<ChapterFacts>?> readErikaChapters(
    Future<NativeInvokeReply> Function(String, JsonMap) invokeJson) async {
  final reply = await invokeJson('chapters', const {});
  if (!reply.supported || reply.error != null) return null;
  final result = reply.result;
  if (result is! Map) return null;
  final raw = result['chapters'];
  if (raw is! List) return null;
  final chapters = <ChapterFacts>[];
  for (final item in raw) {
    if (item is! Map) return null;
    final title = item['title'];
    final startMs = item['startMs'];
    final endMs = item['endMs'];
    if (title is! String ||
        startMs is! num ||
        (endMs != null && endMs is! num)) {
      return null;
    }
    chapters.add(
        ChapterFacts(title, startMs.toInt(), endMs: (endMs as num?)?.toInt()));
  }
  return chapters;
}

/// Reads chapters when Erika reports media information. A duration report can
/// arrive before the presenter exposes the complete opened media, so an empty
/// answer before [tracksReported] is provisional. [known] completes only with
/// an answer made against the full tracks report (or after an already-full
/// read). [onResolved] receives every answer kept as a fact.
final class ErikaChapterReader {
  ErikaChapterReader(this._invokeJson, {this.onResolved});

  final Future<NativeInvokeReply> Function(String, JsonMap) _invokeJson;
  final void Function(List<ChapterFacts>? chapters)? onResolved;
  final _known = Completer<void>();
  Future<void>? _read;
  bool _completeReport = false;
  bool _readWasComplete = false;
  bool _readAgain = false;
  bool _closed = false;
  List<ChapterFacts>? _chapters;

  /// The answer kept as a fact, or null when Erika cannot report chapters.
  List<ChapterFacts>? get chapters => _chapters;

  /// Completes when the first authoritative answer arrives.
  Future<void> get known => _known.future;

  /// Erika reported duration before its complete media report.
  void durationReported() => _report();

  /// Erika reported its complete opened-media tracks.
  void tracksReported() {
    _completeReport = true;
    _report();
  }

  void _report() {
    if (_closed || _known.isCompleted) return;
    if (_read != null) {
      // Only a report that became complete during a provisional read needs
      // another read. A later duplicate event does not.
      if (_completeReport && !_readWasComplete) _readAgain = true;
      return;
    }
    _readWasComplete = _completeReport;
    _read = _readOnce().whenComplete(() {
      _read = null;
      if (_readAgain && !_closed && !_known.isCompleted) {
        _readAgain = false;
        _report();
      }
    });
  }

  Future<void> _readOnce() async {
    final completeReport = _completeReport;
    List<ChapterFacts>? chapters;
    try {
      chapters = await readErikaChapters(_invokeJson);
    } catch (error) {
      debugPrint('[ErikaDriver] chapters: $error');
      if (!completeReport) return;
    }
    if (_closed || _known.isCompleted) return;
    if (chapters == null && !completeReport) return;
    // Keep the presenter's early empty answer provisional until the report
    // that carries the complete media has been seen.
    if (chapters != null && chapters.isEmpty && !completeReport) return;
    _chapters = chapters;
    if (!_known.isCompleted) _known.complete();
    onResolved?.call(chapters);
  }

  void close() {
    _closed = true;
    _readAgain = false;
  }
}

/// Erika, our own kernel, as a [KernelDriver]. The media opens through
/// Erika's adapter, paused, and seeks to its start position; Erika paints
/// into a native view under the window (the picture is a
/// [PlatformVideoSurface], which the stage leaves a hole for) and says its
/// state, position, buffering, tracks and errors by events. Erika does not
/// say that the media ended: the driver tells it, marked inferred, when
/// Erika stops at the end.
///
/// Tracks: Erika has no media to set them on before it opens, so the plan
/// goes on right after, while the media is paused at its start; Erika
/// reports each selection (`trackSelectionChanged`), which confirms it.
/// Subtitles Erika draws itself are ASS and SSA files.
final class ErikaDriver extends AdapterDriver
    implements ErikaNative, KernelPictureSnapshot {
  factory ErikaDriver(KernelLease lease, KernelConfig config) {
    requireLease(lease, 'Erika');
    return ErikaDriver._(
        config,
        ErikaPlayerAdapter(
            sessionOwned: true,
            androidOutputMode: PlayerErikaAndroidOutputMode.values
                    .where((m) =>
                        m.name ==
                        config.settings['player.erikaAndroidOutputMode'])
                    .firstOrNull ??
                PlayerErikaAndroidOutputMode.sdr));
  }

  ErikaDriver._(KernelConfig config, this.adapter) : super(config) {
    adapter.onSessionEvent = _event;
    _chapterReader =
        ErikaChapterReader(adapter.invokeNative, onResolved: (chapters) {
      if (fenced || !opened) return;
      confirmMedia(readMedia());
    });
  }

  final ErikaPlayerAdapter adapter;

  @override
  KernelId get kernel => KernelId.erika;
  @override
  KernelNative get native => this;
  @override
  final KernelCapabilities capabilities = const KernelCapabilities(
    transportEvents: true,
    seekConfirm: true,
    bufferingTelemetry: true,
    endEvent: false,
    openAtPosition: false,
    trackConfirm: true,
    subtitleFiles: {'ass', 'ssa'},
    subtitleScale: true,
  );

  final _tracksKnown = Completer<void>();
  final _durationKnown = Completer<void>();
  final _mediaInfoKnown = Completer<void>();
  final _selectionWaiters = <(bool Function(), Completer<void>)>[];
  final _stateWaiters = <(bool Function(), Completer<void>)>[];

  late final ErikaChapterReader _chapterReader;

  /// The state Erika last reported.
  ErikaPlaybackState? _erikaState;

  /// A play Erika took whose Playing report has not come yet. Erika is
  /// playing by then, but what it has reported still says otherwise; a
  /// second play in that gap is refused by Erika for already playing.
  bool _playTaken = false;

  bool _canPlay() => const {
        ErikaPlaybackState.ready,
        ErikaPlaybackState.paused,
        ErikaPlaybackState.stopped
      }.contains(_erikaState);

  // ---- what Erika says ----

  void _event(ErikaPlayerEvent event) {
    if (fenced) return;
    switch (event.kind) {
      case ErikaEventKind.stateChanged:
        _erikaState = event.state;
        if (event.state == ErikaPlaybackState.playing ||
            event.state == ErikaPlaybackState.stopped) {
          _playTaken = false;
        }
        for (final (state, waiter) in [..._stateWaiters]) {
          if (!waiter.isCompleted && state()) waiter.complete();
        }
        _stateWaiters.removeWhere((w) => w.$2.isCompleted);
        final transport = switch (event.state) {
          ErikaPlaybackState.playing => KernelTransport.playing,
          ErikaPlaybackState.paused ||
          ErikaPlaybackState.ready ||
          ErikaPlaybackState.opening =>
            KernelTransport.paused,
          _ => KernelTransport.stopped,
        };
        final was = observed;
        transportChanged(transport);
        // Erika has no end event: it stops where the media ends.
        if (transport == KernelTransport.stopped &&
            was == KernelTransport.playing &&
            opened &&
            duration > Duration.zero &&
            lastKnownPosition >= duration - const Duration(seconds: 2)) {
          ended(inferred: true);
        }
      case ErikaEventKind.positionChanged:
        if (event.position >= Duration.zero) positionChanged(event.position);
      case ErikaEventKind.bufferingChanged:
        bufferingChanged(event.buffering);
      case ErikaEventKind.error:
        failed(event.error ?? event.message ?? 'Erika reported an error.');
      default:
        break;
    }
    if (event.trackList.isNotEmpty && !_tracksKnown.isCompleted) {
      _tracksKnown.complete();
    }
    if (adapter.mediaInfo.duration > 0 && !_durationKnown.isCompleted) {
      _durationKnown.complete();
    }
    switch (event.kind) {
      case ErikaEventKind.durationChanged:
        _chapterReader.durationReported();
      case ErikaEventKind.tracksChanged:
        if (!_mediaInfoKnown.isCompleted) _mediaInfoKnown.complete();
        _chapterReader.tracksReported();
      default:
        break;
    }
    if (event.kind == ErikaEventKind.tracksChanged ||
        event.kind == ErikaEventKind.trackSelectionChanged) {
      for (final (done, waiter) in [..._selectionWaiters]) {
        if (!waiter.isCompleted && done()) waiter.complete();
      }
      _selectionWaiters.removeWhere((w) => w.$2.isCompleted);
    }
  }

  bool _subtitleDrawn() => adapter.activeSubtitleTracks.isNotEmpty;

  /// Completes once [done] holds on what Erika reported, or after the wait.
  Future<bool> _reportedThat(bool Function() done) async {
    if (done()) return true;
    final waiter = Completer<void>();
    _selectionWaiters.add((done, waiter));
    try {
      await waiter.future.timeout(AdapterDriver.trackConfirmWait);
      return true;
    } on TimeoutException {
      return done();
    } finally {
      _selectionWaiters.removeWhere((w) => identical(w.$2, waiter));
    }
  }

  // ---- the kernel's part ----

  @override
  void applyVolume(double volume) => adapter.volume = volume;

  @override
  void applyRate(double rate) => adapter.playbackRate = rate;

  @override
  Future<void> configure() async {
    final mode = PlayerUpscalerMode.values
        .where((m) => m.name == config.settings['player.erikaUpscalerMode'])
        .firstOrNull;
    if (mode != null && mode != PlayerUpscalerMode.off) {
      await adapter.setUpscaler(mode);
    }
  }

  @override
  Future<void> applyPlan(KernelTrackPlan plan) =>
      applySubtitleProperties(plan.subtitleProperties);

  @override
  Future<Duration> openMedia(ResolvedSource source, Duration start) async {
    adapter.setMedia(source.uri, PlayerMediaType.video);
    await adapter.prepare();
    queue.live();
    // Duration and the tracks arrive as events once Erika has opened it.
    await _durationKnown.future;
    queue.live();
    // Chapters are part of the full media report. The duration event can be
    // delivered first; the tracks event is the complete report and schedules
    // the authoritative read. No timer and no polling are involved.
    await _mediaInfoKnown.future
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    queue.live();
    await _tracksKnown.future
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    queue.live();
    await _chapterReader.known
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    queue.live();
    if (start <= Duration.zero) return Duration.zero;
    final sample = expectSample(start);
    try {
      await adapter.seekAndWait(position: start.inMilliseconds);
      queue.live();
      return await sample.landed ?? start;
    } finally {
      sample.cancel();
    }
  }

  @override
  Future<KernelTracks> planOpened(
      KernelTrackPlan plan, MediaFacts media) async {
    // The plan, exactly: Erika's own default audio is the first, and it
    // draws no subtitle until one is chosen.
    final audio = plan.audio;
    if (audio != null && adapter.activeAudioTracks.firstOrNull != audio) {
      await adapter.selectTracksForSession(audio: audio);
      queue.live();
      await _reportedThat(() => adapter.activeAudioTracks.firstOrNull == audio);
      queue.live();
    }
    var basis = 'opened';
    var subtitleConfirmed = true;
    switch (plan.subtitle) {
      case NoKernelSubtitle():
        if (_subtitleDrawn()) {
          await adapter.selectTracksForSession(subtitles: const []);
          queue.live();
          subtitleConfirmed = await _reportedThat(() => !_subtitleDrawn());
          queue.live();
          basis = subtitleConfirmed ? 'event' : 'not_reported';
        }
      case EmbeddedKernelSubtitle(:final index):
        if (adapter.activeSubtitleTracks.firstOrNull != index) {
          await adapter.selectTracksForSession(subtitles: [index]);
          queue.live();
          subtitleConfirmed = await _reportedThat(
              () => adapter.activeSubtitleTracks.firstOrNull == index);
          queue.live();
          basis = subtitleConfirmed ? 'event' : 'not_reported';
        }
      case FileKernelSubtitle(:final path):
        await adapter.setExternalSubtitleAsync(path);
        queue.live();
        subtitleConfirmed = await _reportedThat(_subtitleDrawn);
        queue.live();
        basis = subtitleConfirmed ? 'event' : 'not_reported';
    }
    final audioNow = adapter.activeAudioTracks.firstOrNull;
    return KernelTracks(
        audio: plan.audio,
        subtitle: plan.subtitle,
        audioConfirmed: plan.audio == null || audioNow == plan.audio,
        subtitleConfirmed: subtitleConfirmed,
        basis: basis);
  }

  @override
  Future<TrackReport> switchAudio(int index) async {
    await adapter.selectTracksForSession(audio: index);
    queue.live();
    final reported = await _reportedThat(
        () => adapter.activeAudioTracks.firstOrNull == index);
    return (confirmed: reported, basis: reported ? 'event' : 'not_reported');
  }

  @override
  Future<TrackReport> switchSubtitle(
      KernelSubtitle subtitle, Duration? probe) async {
    switch (subtitle) {
      case NoKernelSubtitle():
        await adapter.selectTracksForSession(subtitles: const []);
        queue.live();
        final off = await _reportedThat(() => !_subtitleDrawn());
        return (confirmed: off, basis: off ? 'event' : 'not_reported');
      case EmbeddedKernelSubtitle(:final index):
        await adapter.selectTracksForSession(subtitles: [index]);
        queue.live();
        final on = await _reportedThat(
            () => adapter.activeSubtitleTracks.firstOrNull == index);
        return (confirmed: on, basis: on ? 'event' : 'not_reported');
      case FileKernelSubtitle(:final path):
        await adapter.setExternalSubtitleAsync(path);
        queue.live();
        final on = await _reportedThat(_subtitleDrawn);
        return (confirmed: on, basis: on ? 'event' : 'not_reported');
    }
  }

  @override
  Future<void> applySubtitleProperties(Map<String, String> properties) async {
    // Erika scales what it draws; its other styles are not mapped.
    final scale = double.tryParse(properties['subtitle.scale'] ?? '');
    if (scale != null) adapter.setProperty('sub-scale', '$scale');
  }

  @override
  Future<void> seekMedia(Duration target, {required bool exact}) =>
      adapter.seekAndWait(position: target.inMilliseconds);

  @override
  Future<void> pauseMedia(bool paused) async {
    if (paused) {
      _playTaken = false;
      return adapter.pauseDirectly();
    }
    try {
      await adapter.playDirectly();
      _playTaken = true;
    } on PlatformException catch (refused) {
      // Taken a moment ago, not reported yet: what was asked for is so.
      if (_playTaken) return;
      // Erika takes play from ready, paused or stopped only. A state it
      // has not reported yet (the open still settling) is waited for, once;
      // otherwise the state it is in is the answer.
      if (_canPlay()) rethrow;
      // Already playing: what was asked for is so.
      if (_erikaState == ErikaPlaybackState.playing) return;
      debugPrint(
          '[ErikaDriver] play refused in ${_erikaState?.name ?? 'no reported state'}; waiting for a state it can play from');
      final waiter = Completer<void>();
      _stateWaiters.add((_canPlay, waiter));
      try {
        await waiter.future.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        throw StateError(
            'Erika did not take play while ${_erikaState?.name ?? 'in no reported state'}: ${refused.message}');
      } finally {
        _stateWaiters.removeWhere((w) => identical(w.$2, waiter));
      }
      queue.live();
      await adapter.playDirectly();
      _playTaken = true;
    }
  }

  @override
  Future<Duration?> readPosition() async => null;

  @override
  MediaFacts readMedia() => mediaFromInfo(adapter.mediaInfo,
      activeAudio: adapter.activeAudioTracks,
      activeSubtitles: adapter.activeSubtitleTracks,
      frameRate: adapter.videoFrameRate,
      chapters: _chapterReader.chapters);

  /// Erika's own picture, with the subtitles it draws in it. It has no
  /// frame step of its own: stepping a frame is a seek by the declared
  /// frame interval, which the navigation says it is.
  @override
  Future<KernelPicture> snapshotPicture() => queue.run(() async {
        final facts = media!;
        final frame =
            await adapter.snapshot(width: facts.width, height: facts.height);
        queue.live();
        if (frame == null ||
            frame.bytes.length != facts.width * facts.height * 4) {
          throw StateError('Erika returned no complete RGBA picture.');
        }
        return KernelPicture(frame.width, frame.height, frame.bytes);
      });

  @override
  Future<void> showPicture(MediaFacts media) async {
    picture = PlatformVideoSurface(
        adapter.buildPlatformVideoSurface(debugLabel: 'next-erika-$instance'),
        aspect: media.aspect);
  }

  @override
  Future<JsonMap> kernelFacts() async => {
        'version': await _version(),
        'decoders': {
          'video': adapter.getProperty('decoder.video'),
          'audio': null,
          'requested': config.videoDecoders,
        },
      };

  @override
  Future<void> disposeKernel() {
    _chapterReader.close();
    return adapter.disposeAsync();
  }

  // ---- ErikaNative: the handle kernel control gets ----

  @override
  Future<Object?> version() => queue.run(_version);

  Future<Object?> _version() async => erikaVersion();

  @override
  Future<Map<String, NativeRead>> read(List<String> names) async => {
        for (final name in names)
          name: (value: null, error: 'Erika has no named properties.')
      };

  @override
  Future<JsonMap> status() => queue.run(adapter.readKernelStatus);

  @override
  Future<NativeInvokeReply> invoke(String method, JsonMap arguments) =>
      queue.alongside(() => adapter.invokeNative(method, arguments));

  @override
  Future<PlayerUpscalerMode> upscaler() =>
      queue.run(() async => (await adapter.getUpscalerStatus()).requestedMode);

  @override
  Future<void> setUpscaler(PlayerUpscalerMode mode) =>
      queue.run(() => adapter.setUpscaler(mode));

  @override
  Future<bool> debugHud() async => adapter.debugHudEnabled;

  @override
  Future<void> setDebugHud(bool enabled) =>
      queue.run(() => adapter.setDebugHud(enabled));

  @override
  Future<Map<String, Object?>?> engineLog({int? sinceSeq}) =>
      queue.run(() => adapter.readEngineLog(sinceSeq: sinceSeq));
}
