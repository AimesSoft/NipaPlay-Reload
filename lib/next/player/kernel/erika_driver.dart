import 'dart:async';
import 'dart:io';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/player_abstraction/player_enums.dart';
import 'package:nipaplay/utils/danmaku/style.dart' show DanmakuShadowStyle;

import '../core/arbiter.dart';
import '../danmaku/native_sink.dart';
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

/// `setSubtitleStyle`'s arguments for the shared subtitle look (the keys of
/// `SubtitleLook.kernelProperties`): colours as Erika's 0xRRGGBBAA, the ASS
/// numpad alignment, margins, outline, shadow, weight, the font (a file of
/// the font library when one is named so), and how far it replaces an ASS
/// file's own style.
Future<JsonMap> erikaSubtitleStyle(Map<String, String> look) async {
  int? rgba(String? v) =>
      v == null ? null : int.tryParse(v.replaceFirst('0x', ''), radix: 16);
  double? number(String? v) => v == null ? null : double.tryParse(v);
  int? whole(String? v) => v == null ? null : int.tryParse(v);
  final row = switch (look['subtitle.align.y']) {
    'top' => 6,
    'center' => 3,
    _ => 0,
  };
  final column = switch (look['subtitle.align.x']) {
    'left' => 1,
    'right' => 3,
    _ => 2,
  };
  final font = look['subtitle.font'] ?? '';
  final fontsDir = look['subtitle.fonts.dir'] ?? '';
  var fontFile = '';
  if (font.isNotEmpty && fontsDir.isNotEmpty) {
    for (final ext in const ['ttf', 'otf', 'ttc']) {
      final file = File('$fontsDir${Platform.pathSeparator}$font.$ext');
      if (await file.exists()) {
        fontFile = file.path;
        break;
      }
    }
  }
  final margin = whole(look['subtitle.margin.x']);
  return {
    if (rgba(look['subtitle.color']) case final c?) 'primaryColorRgba': c,
    if (rgba(look['subtitle.color.outline']) case final c?)
      'outlineColorRgba': c,
    if (number(look['subtitle.border.size']) case final w?) 'outlineWidth': w,
    if (number(look['subtitle.shadow.offset']) case final d?) 'shadowDepth': d,
    'bold': look['subtitle.bold'] == '1',
    'italic': look['subtitle.italic'] == '1',
    'alignment': row + column,
    if (margin != null) ...{'marginLeft': margin, 'marginRight': margin},
    if (whole(look['subtitle.margin.y']) case final m?) 'marginVertical': m,
    'fontFamily': fontFile.isEmpty ? font : '',
    'fontFilePath': fontFile,
    'overrideMask': look['subtitle.override'] == 'force'
        ? kErikaSubtitleOverrideAll
        : 0,
  };
}

/// Erika, our own kernel, as a [KernelDriver]. The media opens through
/// Erika's adapter, paused, at its start position; Erika paints into a
/// native view under the window (the picture is a [PlatformVideoSurface],
/// which the stage leaves a hole for) and says its state, position,
/// buffering, tracks, errors and the media's end by events.
///
/// What a library newer than the published one has (opening at a
/// position, the end said, a subtitle delay, what the subtitles say) is
/// read from its JSON method table as the media opens and used only when
/// it is there; an older Erika opens at the start and seeks, and the end is
/// inferred when it stops there.
///
/// Tracks: Erika has no media to set them on before it opens, so the plan
/// goes on right after, while the media is paused at its start; Erika
/// reports each selection (`trackSelectionChanged`), which confirms it.
/// Subtitles Erika draws itself are ASS and SSA files.
///
/// Danmaku, as in Classic: Erika draws them into its own picture, so the
/// list the worker built (the rules applied) and the danmaku settings go to
/// Erika ([danmakuSink]) and NipaPlay draws none over it.
final class ErikaDriver extends AdapterDriver
    implements ErikaNative, KernelPictureSnapshot, SessionNativeDanmakuDriver {
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
  }

  final ErikaPlayerAdapter adapter;

  @override
  KernelId get kernel => KernelId.erika;
  @override
  KernelNative get native => this;

  @override
  late final SessionNativeDanmakuSink danmakuSink = _ErikaDanmaku(this);

  /// Danmaku calls run alongside the transport: a long list does not hold
  /// up a seek. Once the instance is fenced there is no Erika to tell.
  Future<void> _danmaku(Future<void> Function() op) async {
    if (fenced) return;
    try {
      await queue.alongside(op);
    } on KernelFenced {
      return;
    }
  }
  /// The methods of Erika's JSON table, read as the media opens.
  Set<String> _methods = const {};
  bool _has(String method) => _methods.contains(method);

  /// Opening at a position and the end said came in the same library.
  bool get _opensAtPosition => _has('setOpenStartPosition');

  @override
  KernelCapabilities get capabilities => KernelCapabilities(
        transportEvents: true,
        seekConfirm: true,
        bufferingTelemetry: true,
        endEvent: _opensAtPosition,
        openAtPosition: _opensAtPosition,
        trackConfirm: true,
        subtitleFiles: const {'ass', 'ssa'},
        subtitleScale: true,
        subtitleDelay: _has('setSubtitleDelay'),
        subtitleText: _has('subtitleText'),
        subtitleStyle: _has('setSubtitleStyle') ? _styleKeys : const {},
      );

  /// What Erika's `setSubtitleStyle` takes of the shared subtitle style. It
  /// has no subtitle height of its own (`subtitle.position`) nor a shadow
  /// colour.
  static const _styleKeys = {
    'subtitle.color',
    'subtitle.borderColor',
    'subtitle.bold',
    'subtitle.italic',
    'subtitle.opacity',
    'subtitle.borderSize',
    'subtitle.shadowOffset',
    'subtitle.alignX',
    'subtitle.alignY',
    'subtitle.marginX',
    'subtitle.marginY',
    'subtitle.fontName',
    'subtitle.fontDir',
    'subtitle.overrideMode',
  };

  final _tracksKnown = Completer<void>();
  final _durationKnown = Completer<void>();
  final _selectionWaiters = <(bool Function(), Completer<void>)>[];
  final _stateWaiters = <(bool Function(), Completer<void>)>[];

  /// The state Erika last reported.
  ErikaPlaybackState? _erikaState;

  /// Container chapters read once when the media opened.
  List<ChapterFacts>? _chapters;

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
        // An Erika that does not say the end stops where the media ends.
        if (!_opensAtPosition &&
            transport == KernelTransport.stopped &&
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
      // By name: the published library's enum has no `ended` yet.
      case final kind when kind.name == 'ended':
        if (opened) ended();
      default:
        break;
    }
    if (event.trackList.isNotEmpty && !_tracksKnown.isCompleted) {
      _tracksKnown.complete();
    }
    if (adapter.mediaInfo.duration > 0 && !_durationKnown.isCompleted) {
      _durationKnown.complete();
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
    final listed = await adapter.invokeNative('listMethods', const {});
    final methods = (listed.result as Map?)?['methods'];
    if (methods is List) {
      _methods = {
        for (final m in methods)
          if (m is Map && m['name'] is String) m['name'] as String
      };
    }
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
    // An Erika that opens at a position presents the frame there first; an
    // older one opens at the start and seeks once it has.
    final openedThere = start > Duration.zero &&
        _opensAtPosition &&
        (await adapter.invokeNative('setOpenStartPosition',
                {'positionMicros': start.inMicroseconds}))
            .error ==
            null;
    queue.live();
    adapter.setMedia(source.uri, PlayerMediaType.video);
    await adapter.prepare();
    queue.live();
    _chapters = await readErikaChapters(adapter.invokeNative);
    queue.live();
    // Duration and the tracks arrive as events once Erika has opened it.
    await _durationKnown.future;
    queue.live();
    await _tracksKnown.future
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    queue.live();
    if (start <= Duration.zero) return Duration.zero;
    if (openedThere) return start;
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

  /// The subtitle look as Erika was last told it, each key of
  /// `SubtitleLook.kernelProperties`: its `setSubtitleStyle` takes the whole
  /// style each time.
  final _look = <String, String>{};

  @override
  Future<void> applySubtitleProperties(Map<String, String> properties) async {
    _look.addAll(properties);
    final scale = double.tryParse(properties['subtitle.scale'] ?? '');
    if (scale != null) adapter.setProperty('sub-scale', '$scale');
    final delay = double.tryParse(properties['subtitle.delay'] ?? '');
    if (delay != null && _has('setSubtitleDelay')) {
      await _invokeOrLog('setSubtitleDelay',
          {'delayMicros': (delay * Duration.microsecondsPerSecond).round()});
    }
    if (_has('setSubtitleStyle') &&
        properties.keys.any((k) => k != 'subtitle.scale' && k != 'subtitle.delay')) {
      await _invokeOrLog('setSubtitleStyle', await erikaSubtitleStyle(_look));
    }
  }

  Future<void> _invokeOrLog(String method, JsonMap arguments) async {
    final reply = await adapter.invokeNative(method, arguments);
    if (reply.error != null) {
      debugPrint('[ErikaDriver] $method: ${reply.error}');
    }
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
  Future<String?> readSubtitleText(Duration? at) async {
    if (at != null || !_has('subtitleText')) return null;
    final reply = await adapter.invokeNative('subtitleText', const {});
    final result = reply.result;
    return result is Map ? result['text'] as String? : null;
  }

  @override
  Future<Duration?> readPosition() async => null;

  @override
  MediaFacts readMedia() => mediaFromInfo(adapter.mediaInfo,
      activeAudio: adapter.activeAudioTracks,
      activeSubtitles: adapter.activeSubtitleTracks,
      frameRate: adapter.videoFrameRate,
      chapters: _chapters);

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
            frame.bytes.length != frame.width * frame.height * 4) {
          throw StateError('Erika returned no complete RGBA picture.');
        }
        return KernelPicture(frame.width, frame.height, frame.bytes,
            subtitlesDrawn: !Platform.isWindows);
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
  Future<void> disposeKernel() => adapter.disposeAsync();

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

/// Erika's own danmaku, told what Classic tells it
/// (`_syncErikaDanmakuConfig`): the blocks and block words are already
/// applied to the list, so they are not passed again.
final class _ErikaDanmaku implements SessionNativeDanmakuSink {
  _ErikaDanmaku(this.driver);

  final ErikaDriver driver;

  ErikaPlayerAdapter get _adapter => driver.adapter;

  Future<void> _tell(Future<void> Function() op) => driver._danmaku(op);

  @override
  Future<void> replaceDanmaku(String timelineJson) =>
      _tell(() => _adapter.loadDanmakuJson(timelineJson));

  @override
  Future<void> configureDanmaku(Map<String, Object?> settings) =>
      _tell(() async {
        double number(String key) => (settings[key] as num).toDouble();
        final size = number('danmaku.fontSize');
        final font = settings['danmaku.fontFamily'] as String? ?? '';
        final file = settings['danmaku.fontFilePath'] as String? ?? '';
        // Visibility apart from the coalesced style, as Classic keeps it.
        await _adapter.setDanmakuEnabled(settings['danmaku.visible'] == true);
        await _adapter.setDanmakuConfig(
          opacity: number('danmaku.opacity'),
          fontSize: size <= 0 ? 30 : size,
          displayArea: number('danmaku.displayArea'),
          mergeDuplicates: settings['danmaku.merge'] == true,
          allowStacking: settings['danmaku.stacking'] == true,
          // The speed folded into the duration, as Classic passes it.
          scrollDurationSeconds: 10 / number('danmaku.speedMultiplier'),
          trackGapRatio: number('danmaku.trackGap'),
          outlineWidth: number('danmaku.outlineWidth'),
          shadowStyle: DanmakuShadowStyle.values
              .where((style) => style.name == settings['danmaku.shadowStyle'])
              .firstOrNull
              ?.index,
          customFontFamily: font.isEmpty ? null : font,
          customFontFilePath: file.isEmpty ? null : file,
        );
        await _adapter.setDanmakuGlobalOffset(Duration(
            microseconds: (number('danmaku.manualOffset') *
                    Duration.microsecondsPerSecond)
                .round()));
      });
}
