import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../capabilities/media_models.dart';
import '../../capabilities/player_facts.dart';
import '../../harness_redaction.dart';
import '../../settings/registry.dart';
import '../core/clock.dart';
import '../core/host.dart';
import '../core/session.dart';
import '../kernel/driver.dart';
import '../next_playback.dart';
import '../perf/budget.dart';
import '../../danmaku/service.dart';
import '../danmaku/controller.dart';
import '../danmaku/native_sink.dart';
import '../danmaku/session_port.dart';
import '../danmaku/settings.dart';
import '../subtitles/controller.dart';
import '../subtitles/look.dart';
import '../track_labels.dart';
import 'session_ports.dart';

/// Makes Next's local operations (window, levels…) for this playback; the
/// runtime supplies it (they are Classic's, told what plays here).
typedef LocalOperationsFactory = Capability Function(SettingsRegistry settings,
    BuildContext Function() context, SessionPlayback playback);

/// [NextPlayback] over Next's own playback layer ([NextPlayerHost]): what
/// the controls over the video, the capabilities and the rest of Next read
/// and drive from P1 on (D5). Nothing here reads the kernel: the session's
/// listenables and its clock only (I3).
///
/// [frame] tells the controls over the video to redraw: when what plays,
/// its transport, the volume, the speed or full screen change, and, only
/// while the controls show, when the clock jumps and once a second as it
/// runs. With the controls hidden nothing over the video is rebuilt.
final class SessionPlayback implements NextPlayback, VideoStageHost {
  SessionPlayback(this.host,
      {LocalOperationsFactory? localOperations,
      this.hideAfter = const Duration(seconds: 3)})
      : _localOperations = localOperations {
    _frame = _Frame(this);
    danmaku.addListener(_danmakuChanged);
    unawaited(danmaku.loadSettings());
    _fullscreen.addListener(_frame.poke);
    host.current.addListener(_bind);
    _bind();
    unawaited(_readLevels());
    if (_desktop) {
      _window = _FullscreenWatch(_fullscreen);
      windowManager.addListener(_window!);
    }
  }

  final NextPlayerHost host;
  final Duration hideAfter;
  final LocalOperationsFactory? _localOperations;

  static bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  PlaybackSession? _session;
  int _generation = 0;
  final _media = ValueNotifier(PlaybackMedia.none);
  final _transport = ValueNotifier(PlaybackTransport.idle);
  final _surface = ValueNotifier<VideoSurface?>(null);
  final _controls = ValueNotifier(false);
  final _fullscreen = ValueNotifier(false);
  final _danmaku = ValueNotifier(0);
  late final _Frame _frame;
  _FullscreenWatch? _window;
  Timer? _hide;
  bool _hovered = false;
  bool _held = false;
  double _volume = 1;
  double _rate = 1;
  Timer? _persistVolume;

  PlaybackSession? get session => _session;
  final danmaku = SessionDanmakuController();
  SessionDanmakuPort? _danmakuPort;
  Future<bool> Function(String path)? _localDanmakuLoader;
  String? _sidecarSession;

  void _danmakuChanged() {
    _danmaku.value = danmaku.version;
    _frame.poke();
  }

  JsonMap get danmakuRendererFacts => {
    'id': danmaku.native ? 'player_native' : switch (DanmakuKernelFactory.getKernelType()) {
      DanmakuRenderEngine.dfmPlus => 'dfm_plus',
      DanmakuRenderEngine.nipaplayNext => 'nipaplay_next',
      final engine => engine.name,
    },
    if (danmaku.native) 'kernel': _session?.driver?.kernel.id,
    ...danmaku.facts(),
  };

  // ---- following the host's session ----

  void _bind() {
    final next = host.current.value;
    if (identical(next, _session)) return;
    final old = _session;
    if (old != null) {
      old.phase.removeListener(_sync);
      old.transport.removeListener(_transportChanged);
      old.media.removeListener(_sync);
      old.surface.removeListener(_sync);
      old.clock.removeListener(_frame.clockChanged);
      old.subtitles.state.removeListener(_frame.poke);
      old.audio.removeListener(_frame.poke);
      old.subtitles.overlay.removeListener(_overlayChanged);
    }
    _session = next;
    final driver = next?.driver;
    danmaku.bind(next?.id, sink: driver is SessionNativeDanmakuDriver
        ? (driver as SessionNativeDanmakuDriver).danmakuSink : null);
    if (next != null) {
      _generation++;
      next.phase.addListener(_sync);
      next.transport.addListener(_transportChanged);
      next.media.addListener(_sync);
      next.surface.addListener(_sync);
      next.clock.addListener(_frame.clockChanged);
      // The menus' ticks follow the choices; the overlay its lines.
      next.subtitles.state.addListener(_frame.poke);
      next.audio.addListener(_frame.poke);
      next.subtitles.overlay.addListener(_overlayChanged);
      unawaited(readSeekStep());
      _show();
    }
    _overlayChanged();
    _sync();
  }

  final _subtitleOverlay = ValueNotifier<OverlayFrame?>(null);
  void _overlayChanged() =>
      _subtitleOverlay.value = _session?.subtitles.overlay.value;

  @override
  ValueListenable<OverlayFrame?> get subtitleOverlay => _subtitleOverlay;

  /// What the controls show of the transport, last told.
  (bool, KernelTransport, double, double)? _shownTransport;

  void _transportChanged() => PlayerPerf.span('facade.transport', () {
        final t = _session?.transport.value;
        if (t != null) {
          _volume = t.volume;
          _rate = t.rate;
          // Paused, the controls stay.
          if (!t.playIntent) {
            _hide?.cancel();
            _controls.value = true;
          } else if (_controls.value && _hide == null) {
            _scheduleHide();
          }
        }
        _sync();
        final shown =
            t == null ? null : (t.playIntent, t.observed, t.rate, t.volume);
        if (shown == _shownTransport) return;
        _shownTransport = shown;
        _frame.poke();
      });

  void _sync() => PlayerPerf.span('facade.sync', () {
        final s = _session;
        final phase = s?.phase.value;
        if (phase?.done ?? true) {
          danmaku.fence();
        } else {
          final driver = s?.driver;
          if (driver is SessionNativeDanmakuDriver && !danmaku.native) {
            danmaku.attachNative((driver as SessionNativeDanmakuDriver).danmakuSink);
          }
          danmaku.inputs(duration: s?.duration.inMilliseconds ?? 0,
              chapterFacts: s?.media.value?.chapters);
          if (s != null && phase!.open && _sidecarSession != s.id && _localDanmakuLoader != null) {
            _sidecarSession = s.id;
            unawaited(_loadSidecar(s.path));
          }
        }
        _surface.value = s?.surface.value;
        _media.value = s == null || phase == SessionPhase.closed
            ? PlaybackMedia.none
            : PlaybackMedia(
                path: s.path,
                generation: _generation,
                requestGeneration: _generation,
                request: s.request,
                durationKnown: s.duration > Duration.zero,
                kernel: s.driver,
              );
        _transport.value = _transportOf(s);
        _frame.sync();
      });

  static PlaybackTransport _transportOf(PlaybackSession? s) {
    final phase = s?.phase.value;
    if (s == null || phase == null) return PlaybackTransport.idle;
    PlaybackTransport t(String status, PlaybackPhase phase, bool video) =>
        PlaybackTransport(
            status: status, phase: phase, hasVideo: video, systemDrawn: false);
    return switch (phase) {
      SessionPhase.resolving ||
      SessionPhase.starting ||
      SessionPhase.loading =>
        t('loading', PlaybackPhase.opening, false),
      SessionPhase.preparing => t('ready', PlaybackPhase.ready, true),
      SessionPhase.active => s.transport.value.observed ==
              KernelTransport.playing
          ? t('playing', PlaybackPhase.playing, true)
          : t('paused', PlaybackPhase.paused, true),
      SessionPhase.failed => t('error', PlaybackPhase.failed, false),
      SessionPhase.closing ||
      SessionPhase.closed =>
        PlaybackTransport.idle,
    };
  }

  // ---- pushed, low frequency ----

  @override
  ValueListenable<PlaybackMedia> get media => _media;
  @override
  ValueListenable<PlaybackTransport> get transport => _transport;
  @override
  ValueListenable<int> get danmakuVersion => _danmaku;
  @override
  Listenable get frame => _frame;
  @override
  ValueListenable<VideoSurface?> get surface => _surface;

  // ---- what the controls show ----

  @override
  bool get hasVideo => _transport.value.hasVideo;
  @override
  bool get showControls => _controls.value;
  @override
  String? get path => _media.value.path;
  @override
  String? get workTitle =>
      _session?.record?.animeName ?? _session?.request.title;
  @override
  String? get episodeTitle =>
      _session?.record?.episodeTitle ?? _session?.request.episodeTitle;
  @override
  Duration get position => _session?.position ?? Duration.zero;
  @override
  Duration get duration => _session?.duration ?? Duration.zero;
  @override
  Duration get buffered => Duration.zero;
  @override
  bool get danmakuVisible => danmaku.visible;
  @override
  bool get fullscreen => _fullscreen.value;
  @override
  double get volume => _session?.transport.value.volume ?? _volume;
  @override
  bool get canPlayNext => false;
  @override
  bool get playIntent => _session?.transport.value.playIntent ?? false;
  @override
  bool get offersDanmaku => true;
  @override
  bool get offersSubtitles => _session?.phase.value.open ?? false;
  @override
  bool get offersScreenshot => false;

  // ---- for capabilities and the rest of Next ----

  @override
  late final SessionPlayerPort port = SessionPlayerPort(this);
  late final SessionControls _controlsPort = SessionControls(this);
  @override
  SessionControls get controls => _controlsPort;
  @override
  SessionControls get inspection => _controlsPort;
  @override
  late final KernelHost kernelHost = SessionKernelHost(this);
  @override
  late final SubtitleTarget subtitleTarget = SessionSubtitleTarget(this);

  @override
  PlaybackDanmakuPort danmakuPort(
          {Future<void> Function(
                  String bindingId, String operation, Object? value)?
              requestChange}) =>
      _danmakuPort ??= SessionDanmakuPort(danmaku, () {
        final s = _session;
        if (s == null || s.phase.value.done) return null;
        return DanmakuPlaybackTarget(s.path, _generation,
            durationMs: s.duration.inMilliseconds);
      }, requestChange: requestChange);

  @override
  set localDanmakuLoader(Future<bool> Function(String path)? loader) {
    _localDanmakuLoader = loader;
    final s = _session;
    if (loader != null && s != null && s.phase.value.open) {
      _sidecarSession = s.id;
      unawaited(_loadSidecar(s.path));
    }
  }

  Future<void> _loadSidecar(String path) async {
    try { await _localDanmakuLoader?.call(path); }
    catch (error) { debugPrint('[NextDanmaku] sidecar: $error'); }
  }

  @override
  Capability localOperations(
          SettingsRegistry settings, BuildContext Function() context) =>
      (_localOperations ??
          (throw StateError('No local operations for Next\'s playback.')))(
          settings, context, this);

  @override
  PlaybackSnapshot snapshot() => PlayerPerf.span('session.snapshot', port.snapshot);

  @override
  Future<JsonMap> diagnostics() async => {
        'available': true,
        'layer': 'next_core',
        ...host.facts(),
        'perf': PlayerPerf.read(),
        'danmaku': danmaku.facts(),
      };

  @override
  JsonMap errorContext() {
    final s = _session;
    return {
      'status': _transport.value.status,
      'path': s == null ? null : redactHarnessText(s.path),
      'kernel': KernelId.mdk.id,
      'positionMs': position.inMilliseconds,
    };
  }

  @override
  JsonMap captureFailure() {
    final s = _session;
    final fault = s?.fault.value;
    return {
      'at': DateTime.now().toUtc().toIso8601String(),
      'sessionId': s?.id,
      'path': s == null ? null : redactHarnessText(s.path),
      'kernel': KernelId.mdk.id,
      'stage': fault?.stage,
      'kernelRetryable': fault?.retryable,
      'messages': {
        'player': null,
        'kernel': safePlayerText(fault?.message),
        'media': null,
      },
      '_localPath': PlaybackFailures.localPathOf(s?.path),
    };
  }

  @override
  Future<void> spoilerKeyChanged(String key) async {}

  @override
  void installDebug() {}

  @override
  Future<void> close({required String reason}) async {
    _hide?.cancel();
    if (_fullscreen.value) await _setFullscreen(false);
    await host.close(reason: reason);
  }

  /// Plays [item] in Next's layer: what playback.open, the library, the
  /// downloads and Classic's own opens (handed over) start with. Completes
  /// once the open plan ended; a failed open shows in the state's error.
  /// What the layer cannot play yet is unavailable, with the reason (D5).
  Future<bool> openItem(PlayableItem item,
      {Duration? start, String? origin}) async {
    final history = item.historyItem;
    try {
      await host.open(MediaRequest(
        locator: item.videoPath,
        origin: origin ?? commandOrigin(),
        title: item.title ?? history?.animeName,
        episodeTitle: item.subtitle ?? history?.episodeTitle,
        animeId: item.animeId ?? history?.animeId,
        episodeId: item.episodeId ?? history?.episodeId,
        start: start,
      ));
    } on OpenRefused catch (refused) {
      throw Failure(FailureCode.unavailable, refused.message,
          details: {'reason': refused.reason, ...refused.facts});
    }
    return true;
  }

  // ---- the player's own controls ----

  @override
  void togglePlay() {
    _session?.togglePlay(origin: 'gui');
    _show();
  }

  @override
  void seek(Duration position) =>
      unawaited(_session?.seek(position, origin: 'gui'));

  @override
  void toggleDanmaku() => unawaited(danmaku.writeSetting('danmaku.visible', !danmaku.visible));

  @override
  Future<void> toggleFullscreen() => _setFullscreen(!_fullscreen.value);

  Future<void> _setFullscreen(bool on) async {
    if (!_desktop) return;
    await windowManager.setFullScreen(on);
    _fullscreen.value = await windowManager.isFullScreen();
    _frame.poke();
  }

  /// Full screen as a window command asks it (window.control).
  Future<void> setFullscreen(bool on) => _setFullscreen(on);

  @override
  Future<void> nextEpisode() async {}

  @override
  Future<void> setVolume(double value) async {
    final volume = value.clamp(0.0, 1.0);
    _volume = volume;
    await _session?.setVolume(volume, origin: 'gui');
    // Kept as Classic keeps it, once the slider rests.
    _persistVolume?.cancel();
    _persistVolume = Timer(const Duration(milliseconds: 400), () {
      unawaited(SettingsAccess.persist('player_volume',
          () async => (await SharedPreferences.getInstance())
              .setDouble('player_volume', volume)));
    });
  }

  @override
  void hover(bool over) {
    _hovered = over;
    over ? _show() : _scheduleHide();
  }

  @override
  void pointerMoved() => _show();

  void _show() {
    if (!_controls.value) {
      _controls.value = true;
      _frame.poke();
    }
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = null;
    final s = _session;
    // Not while the pointer is on them, a menu is open or it is paused.
    if (_hovered || _held || s == null || !s.transport.value.playIntent) {
      return;
    }
    _hide = Timer(hideAfter, () {
      _hide = null;
      if (_hovered || _held) return;
      if (_controls.value) {
        _controls.value = false;
        _frame.poke();
      }
    });
  }

  @override
  SkipSegmentKind? get skippable => activeSkipSegment?.kind;
  SkipSegment? get activeSkipSegment {
    if (danmaku.settings['player.introSkipEnabled'] != true) return null;
    final seconds = position.inMicroseconds / 1e6;
    return danmaku.timeline.segments.where((s) => s.containsSeconds(seconds)).firstOrNull;
  }
  @override
  Future<void> skip() async {
    final segment = activeSkipSegment;
    if (segment != null) await _session?.seek(segment.end, origin: 'gui');
  }

  /// Back to where the video was opened from, out of full screen; the
  /// position kept.
  @override
  Future<void> leave() async {
    if (_fullscreen.value) {
      await _setFullscreen(false);
      return;
    }
    await close(reason: 'left');
  }

  @override
  void holdHotkeys() {
    _held = true;
    _hide?.cancel();
    _hide = null;
  }

  @override
  void releaseHotkeys() {
    _held = false;
    _scheduleHide();
  }

  /// Space plays or pauses, ←/→ move by the seek step, Esc leaves full
  /// screen. Not while a menu or the conversation holds the keys, nor
  /// while text is being typed.
  @override
  bool key(KeyEvent event) {
    final s = _session;
    if (s == null || !hasVideo || _held) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorStateOfType<EditableTextState>() != null)) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) {
      return false;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space && event is KeyDownEvent) {
      togglePlay();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final step = _seekStep;
      final to = position +
          (key == LogicalKeyboardKey.arrowLeft ? -step : step);
      seek(to);
      _show();
      return true;
    }
    if (key == LogicalKeyboardKey.escape && _fullscreen.value) {
      unawaited(_setFullscreen(false));
      return true;
    }
    return false;
  }

  Duration _seekStep = const Duration(seconds: 10);

  /// The shared volume and speed, for what is shown with nothing playing.
  Future<void> _readLevels() async {
    try {
      final levels = await host.levels();
      _volume = levels.volume;
      _rate = levels.rate;
    } catch (error) {
      debugPrint('[NextPlayer] levels: $error');
    }
  }

  /// The shared seek step setting, read once a session opens.
  Future<void> readSeekStep() async {
    try {
      final seconds = (await SharedPreferences.getInstance())
          .getDouble('seek_step_seconds');
      if (seconds != null && seconds > 0) {
        _seekStep = Duration(microseconds: (seconds * 1e6).round());
      }
    } catch (error) {
      debugPrint('[NextPlayer] seek step: $error');
    }
  }

  @override
  List<double>? heat() => danmaku.settings['danmaku.showDensityChart'] == true
      && danmaku.timeline.heat.isNotEmpty ? danmaku.timeline.heat : null;

  // ---- subtitles and audio, as the menus show and set them ----

  /// Off, the media's own tracks, then the files known to this playback;
  /// the one chosen is ticked (the intent, as the play button shows it).
  @override
  Future<List<SubtitleChoice>> subtitles() async {
    final s = _session;
    if (s == null) return const [SubtitleChoice.off(selected: true)];
    final want = s.subtitles.want;
    return [
      SubtitleChoice.off(selected: want.off),
      for (final t in s.media.value?.subtitles ?? const <TrackFacts>[])
        SubtitleChoice.embedded(
            TrackLabels.of(t.title, t.language, t.index), t.index,
            selected: want == SubtitleWant.embedded(t.index)),
      for (final f in s.subtitles.files)
        SubtitleChoice.file(p.basenameWithoutExtension(f.title), f.path,
            selected: want == SubtitleWant.file(f.path)),
    ];
  }

  /// One subtitle at a time: the person's choice, put on alone and told to
  /// the subtitle library.
  @override
  Future<void> choose(SubtitleChoice choice) async {
    final s = _session;
    if (s == null) return;
    await s.chooseSubtitle(
        choice.path != null
            ? SubtitleWant.file(choice.path!)
            : choice.index >= 0
                ? SubtitleWant.embedded(choice.index)
                : const SubtitleWant.off(),
        origin: 'gui',
        title: choice.label);
  }

  /// A subtitle file the person picks, put on alone and kept in the shared
  /// subtitle list; false when none was picked or it could not be used.
  @override
  Future<bool> addSubtitleFile() async {
    final s = _session;
    if (s == null) return false;
    final file = await FilePickerService().pickSubtitleFile();
    if (file == null || !identical(_session, s)) return false;
    try {
      final receipt = await s.chooseSubtitle(SubtitleWant.file(file),
          origin: 'gui', title: p.basename(file));
      await SessionControls.rememberSubtitle(s.path, file, active: true);
      return receipt.outcome != 'rejected';
    } catch (e) {
      debugPrint('[NextPlayer] subtitle file: $e');
      return false;
    }
  }

  @override
  Future<List<EpisodeChoice>> episodes() async => const [];
  @override
  Future<void> play(EpisodeChoice episode) async {}
  @override
  double get rate => _session?.transport.value.rate ?? _rate;

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    await _session?.setRate(rate, origin: 'gui');
    unawaited(SettingsAccess.persist('playback_rate',
        () async => (await SharedPreferences.getInstance())
            .setDouble('playback_rate', rate)));
  }

  /// The media's audio tracks; the one asked for (or the kernel's first)
  /// ticked.
  @override
  List<AudioChoice> audio() {
    final s = _session;
    final tracks = s?.media.value?.audio ?? const <TrackFacts>[];
    if (s == null || tracks.isEmpty) return const [];
    final on = s.audio.value.want ?? s.audio.value.kernel ?? 0;
    final labels = [
      for (final t in tracks)
        TrackLabels.of(t.title, t.language, t.index, fallback: '音轨')
    ];
    return [
      for (final (i, t) in tracks.indexed)
        AudioChoice(TrackLabels.distinct(labels, i, t.codec), t.index,
            selected: t.index == on),
    ];
  }

  @override
  Future<void> chooseAudio(AudioChoice choice) async {
    if (choice.selected) return;
    await _session?.selectAudio(choice.index, origin: 'gui');
  }
  @override
  bool get canFit => false;
  @override
  VideoAspectMode get fit => VideoAspectMode.contain;
  @override
  Future<void> setFit(VideoAspectMode mode) async {}
  @override
  Future<String?> screenshot() async => null;
  @override
  Future<void> open(String path) =>
      launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
  @override
  bool get canPictureInPicture => false;
  @override
  Future<void> pictureInPicture(BuildContext context) async {}

  @override
  PlayerDial get danmakuOpacity => PlayerDial(danmaku.number('danmaku.opacity'), 0, 1, 0.01, DialUnit.percent);
  @override
  Future<void> setDanmakuOpacity(double value) => danmaku.writeSetting('danmaku.opacity', value);
  @override
  PlayerDial get danmakuSize => PlayerDial(danmaku.fontSize, 12, 60, 0.5, DialUnit.points);
  @override
  Future<void> setDanmakuSize(double value, {bool done = false}) => danmaku.writeSetting('danmaku.fontSize', value);
  @override
  double get danmakuArea => danmaku.number('danmaku.displayArea');
  @override
  Future<void> setDanmakuArea(double area) => danmaku.writeSetting('danmaku.displayArea', area);
  @override
  bool blocked(DanmakuLane lane) => danmaku.settings['danmaku.block${lane.name[0].toUpperCase()}${lane.name.substring(1)}'] == true;
  @override
  Future<void> block(DanmakuLane lane, bool on) => danmaku.writeSetting('danmaku.block${lane.name[0].toUpperCase()}${lane.name.substring(1)}', on);
  @override
  PlayerDial get danmakuOffset => PlayerDial(danmaku.offset, -30, 30, 0.1, DialUnit.seconds);
  @override
  void setDanmakuOffset(double seconds) =>
      unawaited(danmaku.writeSetting('danmaku.manualOffset', seconds));
  // The subtitle on: a file NipaPlay draws over the video keeps its own
  // delay (per file) and size; the kernel's take the player's size, and
  // its delay where the kernel shifts subtitles (MDK does not).

  /// The file of [on] when NipaPlay draws it over the video, not the kernel.
  @override
  String? drawnOver(SubtitleChoice? on) {
    final path = on?.path;
    final s = _session;
    if (path == null || s == null) return null;
    return s.subtitles.rendererOf(path) == SubtitleRenderer.overlay
        ? path
        : null;
  }

  bool get _kernelDelays =>
      _session?.driver?.capabilities.subtitleDelay ?? false;

  @override
  bool canDelaySubtitles(SubtitleChoice? on) =>
      on != null && !on.off && (drawnOver(on) != null || _kernelDelays);

  /// Seconds the subtitle comes later (earlier when negative), within the
  /// media's length.
  @override
  PlayerDial subtitleDelay(SubtitleChoice? on) {
    final seconds = duration.inMilliseconds / 1000;
    final limit = seconds > 0 ? seconds : 30.0;
    final overlay = drawnOver(on);
    final value = overlay != null
        ? host.placementOf(overlay).delaySeconds
        : host.look.kernelDelaySeconds;
    return PlayerDial(value.clamp(-limit, limit).toDouble(), -limit, limit,
        SubtitleLook.delayStep, DialUnit.seconds);
  }

  @override
  Future<void> setSubtitleDelay(SubtitleChoice? on, double seconds) async {
    final overlay = drawnOver(on);
    if (overlay != null) {
      await host.setPlacement(
          overlay, host.placementOf(overlay).withDelay(seconds));
    } else if (_kernelDelays) {
      await host.setSubtitleSetting('subtitle_delay_seconds', seconds);
    }
    _frame.poke();
  }

  @override
  bool canScaleSubtitles(SubtitleChoice? on) =>
      on != null &&
      !on.off &&
      (drawnOver(on) != null ||
          (_session?.driver?.capabilities.subtitleScale ?? false));

  @override
  PlayerDial subtitleScale(SubtitleChoice? on) => PlayerDial(
      drawnOver(on) != null ? host.look.overlayScale : host.look.kernelScale,
      SubtitleLook.minScale,
      SubtitleLook.maxScale,
      0.05,
      DialUnit.percent);

  @override
  Future<void> setSubtitleScale(SubtitleChoice? on, double scale) async {
    final value = scale.clamp(SubtitleLook.minScale, SubtitleLook.maxScale);
    await host.setSubtitleSetting(
        drawnOver(on) != null ? 'srt_subtitle_scale' : 'subtitle_scale',
        value.toDouble());
    _frame.poke();
  }

  Future<void> dispose() async {
    setDanmakuSettingsActive(false);
    danmaku.removeListener(_danmakuChanged);
    danmaku.dispose();
    host.current.removeListener(_bind);
    _hide?.cancel();
    _persistVolume?.cancel();
    if (_window case final watch?) windowManager.removeListener(watch);
    _frame.stop();
  }

  void setDanmakuSettingsActive(bool active) {
    if (active) {
      NextDanmakuSettings.active = danmaku;
    } else if (identical(NextDanmakuSettings.active, danmaku)) {
      NextDanmakuSettings.active = null;
    }
  }
}

/// Tells the controls over the video to redraw (see [SessionPlayback]).
final class _Frame extends ChangeNotifier {
  _Frame(this._owner);
  final SessionPlayback _owner;
  Timer? _tick;
  (Object?, Object?)? _last;

  bool get _shown => _owner._controls.value;

  void poke() {
    _syncTick();
    if (hasListeners) notifyListeners();
  }

  /// What plays or its transport changed.
  void sync() {
    final now = (_owner._media.value, _owner._transport.value);
    if (now == _last) return;
    _last = now;
    poke();
  }

  /// The clock jumped (a seek, play or pause, another speed, a drift):
  /// only what shows needs it.
  void clockChanged() {
    if (!_shown) return;
    poke();
  }

  /// Once a second as the clock runs, while the controls show: at the
  /// clock's own second boundary, so the time reads whole seconds.
  void _syncTick() {
    final clock = _owner._session?.clock;
    final want = _shown && hasListeners && (clock?.advancing ?? false);
    if (!want) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    if (_tick != null) return;
    _schedule(clock!);
  }

  void _schedule(PlaybackClockView clock) {
    final ms = clock.now().inMilliseconds;
    final rate = clock.rate <= 0 ? 1.0 : clock.rate;
    final wait = ((1000 - ms % 1000) / rate).ceil().clamp(16, 1000);
    _tick = Timer(Duration(milliseconds: wait), () {
      _tick = null;
      PlayerPerf.span('facade.tick', () {
        if (hasListeners) notifyListeners();
      });
      _syncTick();
    });
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _syncTick();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _syncTick();
  }

  void stop() {
    _tick?.cancel();
    _tick = null;
  }
}

/// Full screen as the window says, whoever asked for it.
final class _FullscreenWatch with WindowListener {
  _FullscreenWatch(this._full);
  final ValueNotifier<bool> _full;
  @override
  void onWindowEnterFullScreen() => _full.value = true;
  @override
  void onWindowLeaveFullScreen() => _full.value = false;
}
