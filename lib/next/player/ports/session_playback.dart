import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
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
import '../features/capture.dart';
import '../features/external_handoff.dart';
import '../features/navigation.dart';
import '../features/timeline_preview.dart';
import '../features/windows.dart';
import '../../ui/player/detached_stage.dart';
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
      this.externalHandoff,
      PlaybackWindows? windows,
      this.hideAfter = const Duration(seconds: 3)})
      : _localOperations = localOperations,
        windows = windows ?? PlaybackWindows() {
    _frame = _Frame(this);
    _fullscreen.addListener(_frame.poke);
    host.current.addListener(_bind);
    _bind();
    externalHandoff?.addListener(_externalChanged);
    unawaited(_readLevels());
    if (_desktop) {
      _window = _FullscreenWatch(_fullscreen);
      windowManager.addListener(_window!);
    }
  }

  final NextPlayerHost host;
  final Duration hideAfter;
  final LocalOperationsFactory? _localOperations;
  final ExternalHandoff? externalHandoff;
  final PlaybackWindows windows;
  final capture = PlaybackCapture();
  final preview = TimelinePreview();
  final navigation = const PlaybackNavigation();
  final aspectMode = ValueNotifier(VideoAspectMode.contain);

  double get videoAspect => _session?.media.value?.aspect ?? 16 / 9;

  void _externalChanged() {
    if (externalHandoff?.active == true) {
      _transport.value = const PlaybackTransport(status: 'external',
          phase: PlaybackPhase.playing, hasVideo: false, systemDrawn: false);
    } else {
      _sync();
    }
    _frame.poke();
  }

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
    }
    _session = next;
    unawaited(preview.reset());
    if (next != null) {
      _generation++;
      next.phase.addListener(_sync);
      next.transport.addListener(_transportChanged);
      next.media.addListener(_sync);
      next.surface.addListener(_sync);
      next.clock.addListener(_frame.clockChanged);
      unawaited(readSeekStep());
      _show();
    }
    _sync();
  }

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
  bool get danmakuVisible => false;
  @override
  bool get fullscreen => _fullscreen.value;
  @override
  double get volume => _session?.transport.value.volume ?? _volume;
  @override
  bool get canPlayNext => false;
  @override
  bool get playIntent => _session?.transport.value.playIntent ?? false;
  @override
  bool get offersDanmaku => false;
  @override
  bool get offersSubtitles => false;
  @override
  bool get offersScreenshot => hasVideo;

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
      SessionDanmakuPort();

  @override
  set localDanmakuLoader(Future<bool> Function(String path)? loader) {}

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
    externalHandoff?.clear();
    await windows.returnToMain();
    await preview.reset();
  }

  /// Plays [item] in Next's layer: what playback.open, the library, the
  /// downloads and Classic's own opens (handed over) start with. Completes
  /// once the open plan ended; a failed open shows in the state's error.
  /// What the layer cannot play yet is unavailable, with the reason (D5).
  Future<bool> openItem(PlayableItem item,
      {Duration? start, String? origin}) async {
    final history = item.historyItem;
    final external = externalHandoff;
    if (external != null && external.enabled()) {
      await host.close(reason: 'external_handoff');
      await windows.returnToMain();
      try {
        final resume = start ?? Duration(milliseconds: history?.lastPosition ??
            await host.records.resumeAt(item.videoPath));
        await external.open(item, start: resume);
      } on ProcessException catch (error) {
        throw Failure(FailureCode.unavailable, '外部播放器启动失败：${error.message}',
            details: {'reason': 'external_player_launch_failed'});
      }
      return true;
    }
    external?.clear();
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
  void toggleDanmaku() {}

  @override
  Future<void> toggleFullscreen() => _setFullscreen(!_fullscreen.value);

  Future<void> _setFullscreen(bool on) async {
    if (!_desktop) return;
    final window = windows.nativeWindow;
    if (window != null) {
      await window.setFullscreen(on);
      _fullscreen.value = window.isFullscreen;
      return;
    }
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
  SkipSegmentKind? get skippable => null;
  @override
  Future<void> skip() async {}

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
    if (key == LogicalKeyboardKey.comma || key == LogicalKeyboardKey.period) {
      unawaited(inspection.inspect('playback.navigate',
          {'frameDelta': key == LogicalKeyboardKey.comma ? -1 : 1})
          .catchError((Object error) => <String, Object?>{'error': '$error'}));
      _show();
      return true;
    }
    if (key == LogicalKeyboardKey.keyF && event is KeyDownEvent) {
      unawaited(toggleFullscreen());
      return true;
    }
    if (key == LogicalKeyboardKey.keyM && event is KeyDownEvent) {
      unawaited(setVolume(volume > 0 ? 0 : 1));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      unawaited(setVolume(volume + (key == LogicalKeyboardKey.arrowUp ? 0.05 : -0.05)));
      _show();
      return true;
    }
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
      final prefs = await SharedPreferences.getInstance();
      preview.enabled = prefs.getBool('timeline_preview_enabled') ?? false;
      aspectMode.value = VideoAspectMode.values.where((m) =>
          m.name == prefs.getString('video_aspect_mode')).firstOrNull ?? VideoAspectMode.contain;
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
  List<double>? heat() => null;
  @override
  Future<List<SubtitleChoice>> subtitles() async => const [];
  @override
  Future<void> choose(SubtitleChoice choice) async {}
  @override
  Future<bool> addSubtitleFile() async => false;
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

  @override
  List<AudioChoice> audio() => const [];
  @override
  Future<void> chooseAudio(AudioChoice choice) async {}
  @override
  bool get canFit => hasVideo;
  @override
  VideoAspectMode get fit => aspectMode.value;
  @override
  Future<void> setFit(VideoAspectMode mode) async {
    aspectMode.value = mode;
    _frame.poke();
    await SettingsAccess.persist('video_aspect_mode', () async =>
        (await SharedPreferences.getInstance()).setString('video_aspect_mode', mode.name));
  }
  @override
  Future<String?> screenshot() async {
    final s = _session;
    if (s == null) return null;
    final prefs = await SharedPreferences.getInstance();
    String? output;
    if (prefs.getInt('screenshot_save_target') == 0) {
      final extension = prefs.getString('screenshot_format') == 'png' ? 'png' : 'jpg';
      final location = await getSaveLocation(
          suggestedName: 'NipaPlay_${DateTime.now().millisecondsSinceEpoch}.$extension',
          acceptedTypeGroups: [XTypeGroup(label: '图片', extensions: [extension])]);
      if (location == null) return null;
      output = location.path;
    }
    return (await controls.capture({'kind': 'screenshot',
      if (output != null) 'outputPath': output}))['path'] as String;
  }
  @override
  Future<void> open(String path) =>
      launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
  @override
  bool get canPictureInPicture => hasVideo && PlaybackWindows.supported;
  @override
  Future<void> pictureInPicture(BuildContext context) async {
    await detach();
    await windows.setPictureInPicture(!windows.pictureInPicture, videoAspect);
  }

  Future<void> detach() => windows.detach(
      (_) => NextDetachedPlayer(playback: this), videoAspect);

  Future<void> featureSettingChanged(String key, Object? value) async {
    if (key == 'player.timelinePreviewEnabled') {
      preview.enabled = value == true;
      if (!preview.enabled) await preview.reset();
      _frame.poke();
    } else if (key == 'player.videoAspectMode' && value is String) {
      aspectMode.value = VideoAspectMode.values.byName(value);
      _frame.poke();
    }
  }

  static const _dial = PlayerDial(0, 0, 1, 1, DialUnit.percent);
  @override
  PlayerDial get danmakuOpacity => _dial;
  @override
  Future<void> setDanmakuOpacity(double value) async {}
  @override
  PlayerDial get danmakuSize => _dial;
  @override
  Future<void> setDanmakuSize(double value, {bool done = false}) async {}
  @override
  double get danmakuArea => 1;
  @override
  Future<void> setDanmakuArea(double area) async {}
  @override
  bool blocked(DanmakuLane lane) => false;
  @override
  Future<void> block(DanmakuLane lane, bool on) async {}
  @override
  PlayerDial get danmakuOffset => _dial;
  @override
  void setDanmakuOffset(double seconds) {}
  @override
  String? drawnOver(SubtitleChoice? on) => null;
  @override
  PlayerDial subtitleDelay(SubtitleChoice? on) => _dial;
  @override
  Future<void> setSubtitleDelay(SubtitleChoice? on, double seconds) async {}
  @override
  bool canScaleSubtitles(SubtitleChoice? on) => false;
  @override
  PlayerDial subtitleScale(SubtitleChoice? on) => _dial;
  @override
  Future<void> setSubtitleScale(SubtitleChoice? on, double scale) async {}

  Future<void> dispose() async {
    host.current.removeListener(_bind);
    _hide?.cancel();
    _persistVolume?.cancel();
    if (_window case final watch?) windowManager.removeListener(watch);
    _frame.stop();
    await preview.dispose();
    await windows.shutdown();
    externalHandoff?.removeListener(_externalChanged);
    externalHandoff?.dispose();
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
