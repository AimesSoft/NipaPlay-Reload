import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import './abstract_player.dart';
import './player_data_models.dart';
import './player_enums.dart';
import 'package:nipaplay/utils/player_event_log.dart';

class _ErikaDanmakuConfigPatch {
  _ErikaDanmakuConfigPatch({
    this.enabled,
    this.fontSize,
    this.opacity,
    this.displayArea,
    this.scrollDurationSeconds,
    this.scrollSpeedFactor,
    this.trackGapRatio,
    this.outlineWidth,
    this.shadowStyle,
    this.customFontFamily,
    this.customFontFilePath,
    this.mergeDuplicates,
    this.allowStacking,
    this.maxQuantity,
    this.maxLinesPerMode,
    this.blockTop,
    this.blockBottom,
    this.blockScroll,
    List<String>? blockWords,
  }) : blockWords =
            blockWords == null ? null : List<String>.unmodifiable(blockWords);

  final bool? enabled;
  final double? fontSize;
  final double? opacity;
  final double? displayArea;
  final double? scrollDurationSeconds;
  final double? scrollSpeedFactor;
  final double? trackGapRatio;
  final double? outlineWidth;
  final int? shadowStyle;
  final String? customFontFamily;
  final String? customFontFilePath;
  final bool? mergeDuplicates;
  final bool? allowStacking;
  final int? maxQuantity;
  final int? maxLinesPerMode;
  final bool? blockTop;
  final bool? blockBottom;
  final bool? blockScroll;
  final List<String>? blockWords;

  bool get isEmpty =>
      enabled == null &&
      fontSize == null &&
      opacity == null &&
      displayArea == null &&
      scrollDurationSeconds == null &&
      scrollSpeedFactor == null &&
      trackGapRatio == null &&
      outlineWidth == null &&
      shadowStyle == null &&
      customFontFamily == null &&
      customFontFilePath == null &&
      mergeDuplicates == null &&
      allowStacking == null &&
      maxQuantity == null &&
      maxLinesPerMode == null &&
      blockTop == null &&
      blockBottom == null &&
      blockScroll == null &&
      blockWords == null;

  _ErikaDanmakuConfigPatch merge(_ErikaDanmakuConfigPatch other) {
    return _ErikaDanmakuConfigPatch(
      enabled: other.enabled ?? enabled,
      fontSize: other.fontSize ?? fontSize,
      opacity: other.opacity ?? opacity,
      displayArea: other.displayArea ?? displayArea,
      scrollDurationSeconds:
          other.scrollDurationSeconds ?? scrollDurationSeconds,
      scrollSpeedFactor: other.scrollSpeedFactor ?? scrollSpeedFactor,
      trackGapRatio: other.trackGapRatio ?? trackGapRatio,
      outlineWidth: other.outlineWidth ?? outlineWidth,
      shadowStyle: other.shadowStyle ?? shadowStyle,
      customFontFamily: other.customFontFamily ?? customFontFamily,
      customFontFilePath: other.customFontFilePath ?? customFontFilePath,
      mergeDuplicates: other.mergeDuplicates ?? mergeDuplicates,
      allowStacking: other.allowStacking ?? allowStacking,
      maxQuantity: other.maxQuantity ?? maxQuantity,
      maxLinesPerMode: other.maxLinesPerMode ?? maxLinesPerMode,
      blockTop: other.blockTop ?? blockTop,
      blockBottom: other.blockBottom ?? blockBottom,
      blockScroll: other.blockScroll ?? blockScroll,
      blockWords: other.blockWords ?? blockWords,
    );
  }

  _ErikaDanmakuConfigPatch differenceFrom(_ErikaDanmakuConfigPatch? previous) {
    return _ErikaDanmakuConfigPatch(
      enabled: _changed(enabled, previous?.enabled) ? enabled : null,
      fontSize: _changed(fontSize, previous?.fontSize) ? fontSize : null,
      opacity: _changed(opacity, previous?.opacity) ? opacity : null,
      displayArea:
          _changed(displayArea, previous?.displayArea) ? displayArea : null,
      scrollDurationSeconds:
          _changed(scrollDurationSeconds, previous?.scrollDurationSeconds)
              ? scrollDurationSeconds
              : null,
      scrollSpeedFactor:
          _changed(scrollSpeedFactor, previous?.scrollSpeedFactor)
              ? scrollSpeedFactor
              : null,
      trackGapRatio: _changed(trackGapRatio, previous?.trackGapRatio)
          ? trackGapRatio
          : null,
      outlineWidth:
          _changed(outlineWidth, previous?.outlineWidth) ? outlineWidth : null,
      shadowStyle:
          _changed(shadowStyle, previous?.shadowStyle) ? shadowStyle : null,
      customFontFamily: _changed(customFontFamily, previous?.customFontFamily)
          ? customFontFamily
          : null,
      customFontFilePath:
          _changed(customFontFilePath, previous?.customFontFilePath)
              ? customFontFilePath
              : null,
      mergeDuplicates: _changed(mergeDuplicates, previous?.mergeDuplicates)
          ? mergeDuplicates
          : null,
      allowStacking: _changed(allowStacking, previous?.allowStacking)
          ? allowStacking
          : null,
      maxQuantity:
          _changed(maxQuantity, previous?.maxQuantity) ? maxQuantity : null,
      maxLinesPerMode: _changed(maxLinesPerMode, previous?.maxLinesPerMode)
          ? maxLinesPerMode
          : null,
      blockTop: _changed(blockTop, previous?.blockTop) ? blockTop : null,
      blockBottom:
          _changed(blockBottom, previous?.blockBottom) ? blockBottom : null,
      blockScroll:
          _changed(blockScroll, previous?.blockScroll) ? blockScroll : null,
      blockWords:
          _changedList(blockWords, previous?.blockWords) ? blockWords : null,
    );
  }

  static bool _changed<T>(T? value, T? previous) =>
      value != null && value != previous;

  static bool _changedList(List<String>? value, List<String>? previous) =>
      value != null && !listEquals(value, previous);
}

bool get _erikaWindowOverlayTraceEnabled =>
    !kIsWeb && Platform.environment['ERIKA_WINDOW_OVERLAY_TRACE'] == '1';

void _traceErikaWindowOverlay(String message) {
  if (_erikaWindowOverlayTraceEnabled) {
    debugPrint('[NipaPlayErikaWindowOverlay] $message');
  }
}

Rect _transformedGlobalRectOf(RenderBox box) {
  final topLeft = box.localToGlobal(Offset.zero);
  final topRight = box.localToGlobal(Offset(box.size.width, 0));
  final bottomLeft = box.localToGlobal(Offset(0, box.size.height));
  final bottomRight = box.localToGlobal(
    Offset(box.size.width, box.size.height),
  );

  final left = math.min(
    math.min(topLeft.dx, topRight.dx),
    math.min(bottomLeft.dx, bottomRight.dx),
  );
  final top = math.min(
    math.min(topLeft.dy, topRight.dy),
    math.min(bottomLeft.dy, bottomRight.dy),
  );
  final right = math.max(
    math.max(topLeft.dx, topRight.dx),
    math.max(bottomLeft.dx, bottomRight.dx),
  );
  final bottom = math.max(
    math.max(topLeft.dy, topRight.dy),
    math.max(bottomLeft.dy, bottomRight.dy),
  );

  return Rect.fromLTRB(left, top, right, bottom);
}

Rect _screenRectToScaledFlutterRect(BuildContext context, Rect rect) {
  final view = View.maybeOf(context);
  if (view == null) {
    return rect;
  }
  final mediaSize = MediaQuery.maybeSizeOf(context);
  if (mediaSize == null || mediaSize.isEmpty) {
    return rect;
  }
  final screenSize = view.physicalSize / view.devicePixelRatio;
  final scaleX = screenSize.width / mediaSize.width;
  final scaleY = screenSize.height / mediaSize.height;
  if (!scaleX.isFinite || !scaleY.isFinite || scaleX <= 0 || scaleY <= 0) {
    return rect;
  }
  return Rect.fromLTRB(
    rect.left / scaleX,
    rect.top / scaleY,
    rect.right / scaleX,
    rect.bottom / scaleY,
  );
}

class _NipaplayErikaWindowOverlayVideoView extends StatefulWidget {
  const _NipaplayErikaWindowOverlayVideoView({
    required this.player,
    this.debugLabel,
    this.onPlatformViewIdChanged,
    this.onFrameRectChanged,
  });

  final ErikaPlayer player;
  final String? debugLabel;
  final ValueChanged<int?>? onPlatformViewIdChanged;
  final ValueChanged<Rect?>? onFrameRectChanged;

  @override
  State<_NipaplayErikaWindowOverlayVideoView> createState() =>
      _NipaplayErikaWindowOverlayVideoViewState();
}

class _NipaplayErikaWindowOverlayVideoViewState
    extends State<_NipaplayErikaWindowOverlayVideoView>
    with WidgetsBindingObserver {
  static final Expando<Object> _cutoutOwners =
      Expando<Object>('Erika overlay cutout owners');

  final Object _cutoutOwner = Object();
  Timer? _retryTimer;
  Timer? _frameTimer;
  int _bindAttempts = 0;
  bool _isBound = false;
  bool _bindInFlight = false;
  late final int _surfaceGeneration;
  String? _lastFrameSignature;
  int? _flutterViewId;
  bool _secondaryWindow = false;
  int _targetRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _surfaceGeneration = identityHashCode(this);
    widget.onPlatformViewIdChanged?.call(ErikaPlayer.windowOverlayViewId);
    _startFrameTimer();
    _scheduleAttach();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS 回前台后原生 overlay 视图可能已被系统回收，而 Flutter 侧矩形没变、
    // 帧签名相同 -> 轮询早退从不重发，画面黑屏（音频/字幕仍在跑）。
    // 强制清签名 + 重绑 surface + 强制发一帧。
    if (state == AppLifecycleState.resumed && mounted) {
      _isBound = false;
      _lastFrameSignature = null;
      _scheduleAttach();
      _scheduleFrameUpdate(force: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_captureWindowTarget()) {
      _handleWindowTargetChanged();
    }
  }

  @override
  void didUpdateWidget(
      covariant _NipaplayErikaWindowOverlayVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      _retryTimer?.cancel();
      _bindAttempts = 0;
      _isBound = false;
      _lastFrameSignature = null;
      unawaited(
        oldWidget.player.detachWindowOverlay(generation: _surfaceGeneration),
      );
      widget.onPlatformViewIdChanged?.call(ErikaPlayer.windowOverlayViewId);
      _scheduleAttach();
    }
  }

  @override
  void didChangeMetrics() {
    _scheduleFrameUpdate(force: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _frameTimer?.cancel();
    widget.onPlatformViewIdChanged?.call(null);
    // Removing this surface can happen while Flutter has locked the widget
    // tree for a rebuild. Clearing the shared cutout synchronously would call
    // notifyListeners() from dispose(), so defer it until that frame finishes.
    final onFrameRectChanged = widget.onFrameRectChanged;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (onFrameRectChanged != null &&
          identical(_cutoutOwners[onFrameRectChanged], _cutoutOwner)) {
        _cutoutOwners[onFrameRectChanged] = null;
        onFrameRectChanged(null);
      }
    });
    unawaited(_releaseOverlaySurface());
    super.dispose();
  }

  Future<void> _releaseOverlaySurface() async {
    await _hideOverlayFrame();
    try {
      await widget.player.detachWindowOverlay(
        generation: _surfaceGeneration,
      );
    } catch (error) {
      debugPrint(
        'NipaplayErikaWindowOverlayVideoView: detach overlay failed: $error',
      );
    }
  }

  void _startFrameTimer() {
    _frameTimer?.cancel();
    // The Windows plugin follows WM_MOVE/WM_SIZE natively. This timer is only a
    // fallback for Flutter-only layout changes; polling at display refresh rate
    // duplicates native window movement work and makes live dragging stutter.
    const interval = Duration(milliseconds: 250);
    _frameTimer = Timer.periodic(
      interval,
      (_) => _scheduleFrameUpdate(),
    );
  }

  void _scheduleAttach() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_attachOverlaySurface());
      _scheduleFrameUpdate(force: true);
    });
  }

  Future<void> _attachOverlaySurface() async {
    if (!mounted || _isBound || _bindInFlight || kIsWeb) {
      return;
    }

    final targetChanged = _captureWindowTarget();
    if (targetChanged) {
      _handleWindowTargetChanged();
    }
    final player = widget.player;
    final targetRevision = _targetRevision;
    final flutterViewId = _flutterViewId;
    final secondaryWindow = _secondaryWindow;
    var attachCurrentTargetAgain = false;
    _bindInFlight = true;
    try {
      _traceErikaWindowOverlay(
        'attach generation=$_surfaceGeneration revision=$targetRevision '
        'flutterView=$flutterViewId secondary=$secondaryWindow',
      );
      await player.attachWindowOverlay(
        flutterViewId: flutterViewId,
        secondaryWindow: secondaryWindow,
      );
      if (!mounted ||
          widget.player != player ||
          _targetRevision != targetRevision ||
          _flutterViewId != flutterViewId ||
          _secondaryWindow != secondaryWindow) {
        attachCurrentTargetAgain = mounted;
        return;
      }
      _bindAttempts = 0;
      _isBound = true;
      _traceErikaWindowOverlay(
        'attached generation=$_surfaceGeneration revision=$targetRevision '
        'flutterView=$flutterViewId secondary=$secondaryWindow',
      );
    } catch (error) {
      debugPrint('NipaplayErikaWindowOverlayVideoView: bind failed: $error');
      if (mounted && _targetRevision == targetRevision) {
        _scheduleRetry();
      } else {
        attachCurrentTargetAgain = mounted;
      }
    } finally {
      _bindInFlight = false;
      if (attachCurrentTargetAgain) {
        _scheduleAttach();
      } else if (_isBound) {
        _scheduleFrameUpdate(force: true);
      }
    }
  }

  void _scheduleRetry() {
    if (_isBound || !mounted) {
      return;
    }
    final attempt = _bindAttempts;
    _bindAttempts += 1;
    final delay = switch (attempt) {
      0 => const Duration(milliseconds: 150),
      1 => const Duration(milliseconds: 300),
      2 => const Duration(milliseconds: 600),
      3 => const Duration(milliseconds: 1200),
      _ => const Duration(seconds: 2),
    };
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(_attachOverlaySurface()));
  }

  void _scheduleFrameUpdate({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_sendOverlayFrame(visible: true, force: force));
    });
  }

  Future<void> _sendOverlayFrame({
    required bool visible,
    bool force = false,
  }) async {
    if (kIsWeb) {
      return;
    }

    final Rect nativeFrame;
    Rect? flutterCutout;
    if (visible) {
      if (!mounted) {
        return;
      }
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox) {
        return;
      }
      final box = renderObject;
      if (!box.hasSize || box.size.isEmpty) {
        return;
      }
      if (_captureWindowTarget()) {
        _handleWindowTargetChanged();
      }
      nativeFrame = _transformedGlobalRectOf(box);
      flutterCutout = _screenRectToScaledFlutterRect(context, nativeFrame);
    } else {
      nativeFrame = Rect.zero;
    }

    final signature = <Object>[
      visible,
      nativeFrame.left.toStringAsFixed(2),
      nativeFrame.top.toStringAsFixed(2),
      nativeFrame.width.toStringAsFixed(2),
      nativeFrame.height.toStringAsFixed(2),
      _flutterViewId ?? -1,
      _secondaryWindow,
    ].join('|');
    if (!force && signature == _lastFrameSignature) {
      return;
    }
    _lastFrameSignature = signature;
    final flutterViewId = _flutterViewId;
    final secondaryWindow = _secondaryWindow;
    final targetRevision = _targetRevision;
    _traceErikaWindowOverlay(
      'frame generation=$_surfaceGeneration flutterView=$flutterViewId '
      'secondary=$secondaryWindow visible=$visible rect=$nativeFrame',
    );

    try {
      await widget.player.setWindowOverlayFrame(
        frame: nativeFrame,
        visible: visible,
        generation: _surfaceGeneration,
        flutterViewId: flutterViewId,
        secondaryWindow: secondaryWindow,
        debugLabel: widget.debugLabel,
      );
      if (!mounted ||
          _targetRevision != targetRevision ||
          _flutterViewId != flutterViewId ||
          _secondaryWindow != secondaryWindow) {
        return;
      }
      final onFrameRectChanged = widget.onFrameRectChanged;
      if (onFrameRectChanged != null) {
        if (visible) {
          _cutoutOwners[onFrameRectChanged] = _cutoutOwner;
          onFrameRectChanged(flutterCutout);
        } else if (identical(
            _cutoutOwners[onFrameRectChanged], _cutoutOwner)) {
          _cutoutOwners[onFrameRectChanged] = null;
          onFrameRectChanged(null);
        }
      }
    } catch (error) {
      _lastFrameSignature = null;
      debugPrint(
        'NipaplayErikaWindowOverlayVideoView: frame update failed: $error',
      );
    }
  }

  Future<void> _hideOverlayFrame() async {
    try {
      await widget.player.setWindowOverlayFrame(
        frame: Rect.zero,
        visible: false,
        generation: _surfaceGeneration,
        flutterViewId: _flutterViewId,
        secondaryWindow: _secondaryWindow,
        debugLabel: widget.debugLabel,
      );
    } catch (error) {
      debugPrint(
        'NipaplayErikaWindowOverlayVideoView: hide overlay failed: $error',
      );
    }
  }

  bool _captureWindowTarget() {
    final flutterViewId = View.maybeOf(context)?.viewId;
    final secondaryWindow = DesktopMultiWindow.isSecondaryWindow(context);
    if (_flutterViewId == flutterViewId &&
        _secondaryWindow == secondaryWindow) {
      return false;
    }
    _flutterViewId = flutterViewId;
    _secondaryWindow = secondaryWindow;
    _targetRevision += 1;
    _traceErikaWindowOverlay(
      'target generation=$_surfaceGeneration revision=$_targetRevision '
      'flutterView=$_flutterViewId secondary=$_secondaryWindow',
    );
    return true;
  }

  void _handleWindowTargetChanged() {
    _retryTimer?.cancel();
    _bindAttempts = 0;
    _isBound = false;
    _lastFrameSignature = null;
    _scheduleAttach();
    _scheduleFrameUpdate(force: true);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }
    _scheduleFrameUpdate();
    return const SizedBox.expand();
  }
}

class ErikaPlayerAdapter
    implements
        AbstractPlayer,
        AsyncDisposablePlayer,
        AsyncSeekPlayer,
        AsyncExternalSubtitlePlayer,
        MediaLoadAwarePlayer {
  ErikaPlayerAdapter({
    PlayerErikaAndroidOutputMode androidOutputMode =
        PlayerErikaAndroidOutputMode.sdr,
  }) : _player = ErikaPlayer(
          outputMode: _resolveNativeOutputMode(androidOutputMode),
        ) {
    if (_isSupported) {
      _eventSubscription = _player.events.listen(
        _handleEvent,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('ErikaPlayerAdapter event error: $error');
        },
      );
    }
  }

  final ErikaPlayer _player;
  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  final Map<PlayerMediaType, List<String>> _decoders = {
    PlayerMediaType.video: const <String>[],
    PlayerMediaType.audio: const <String>[],
    PlayerMediaType.subtitle: const <String>[],
    PlayerMediaType.unknown: const <String>[],
  };
  final Map<String, String> _properties = <String, String>{};

  StreamSubscription<ErikaPlayerEvent>? _eventSubscription;
  Future<void>? _disposeFuture;
  PlayerPlaybackState _state = PlayerPlaybackState.stopped;
  PlayerMediaInfo _mediaInfo = PlayerMediaInfo(duration: 0);
  String _media = '';
  double _volume = 1.0;
  double _playbackRate = 1.0;
  PlayerUpscalerStatus _lastUpscalerStatus = const PlayerUpscalerStatus.off();
  Map<String, dynamic> _lastPresenterStats = const <String, dynamic>{};
  Map<String, dynamic> _lastOutputStatus = const <String, dynamic>{};
  Map<String, dynamic> _lastDecoderStatus = const <String, dynamic>{};
  Map<String, dynamic> _lastAudioOutputStatus = const <String, dynamic>{};
  String? _lastNativeError;
  int _lastPositionMs = 0;
  DateTime _lastPositionUpdate = DateTime.now();
  Future<void>? _inFlightPlay;
  int? _pendingSeekTargetMs;
  DateTime? _seekFenceUntil;
  bool _disposed = false;

  // ---- 回前台播放停滞自愈 ----
  //
  // Erika 内核（Rust；iOS/tvOS/macOS 走 Metal、Windows 走 D3D11、Android 走
  // wgpu）在移动端退后台后，回前台的 Play 可能被内核静默忽略或时钟停摆：
  // seek 能同步出帧，但播放管线不再推进。原生内核无法在 Dart 侧直接修复，
  // 这里用“原生位置事件是否仍在流动”作为活性信号，检测到停滞就重开当前
  // 媒体并续播（retryCurrentMediaLoad）。
  static bool get _isMobileKernelPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          _isHarmonyOS);

  static const Duration _playbackWatchdogDelay = Duration(seconds: 3);
  // 原生位置事件静默多久视为停摆。内核停摆时 seek 仍可能产生零星事件
  // （拖动能出帧），但事件流会停止；因此按“最近一次事件距今”判断，
  // 而不是与布防时刻的事件计数比较——否则布防后发生的 seek 事件会把
  // 停摆误判为正常播放。
  static const Duration _stallEventSilenceThreshold = Duration(
    milliseconds: 2500,
  );
  static const int _maxConsecutiveStallRecoveries = 3;

  Timer? _playbackWatchdogTimer;
  // 仅由原生 positionChanged 事件递增/刷新，seek/play 的本地时间戳不影响它。
  int _positionEventCount = 0;
  DateTime? _lastNativePositionEventAt;
  int _stallRecoveryCount = 0;
  bool _stallNudgeAttempted = false;
  bool _stallRecoveryInFlight = false;
  // 渲染帧活性监控：内核停摆的一种形态是“位置事件仍在发、画面帧已停”
  // （回前台黑屏但字幕在播），位置静默检测对它失明。改用 presenter 统计
  // 的 renderedVideoFrames 是否推进作为视频管线的真活性信号。
  Timer? _frameActivityTimer;
  int? _lastRenderedFramesSample;

  // 重开媒体后需要恢复的会话级状态（弹幕/外挂字幕/字幕缩放等）。
  String? _lastExternalSubtitlePath;
  String? _lastDanmakuJson;
  bool? _lastDanmakuEnabled;
  Duration? _lastDanmakuGlobalOffset;
  double? _lastSubtitleScale;

  static const Duration _danmakuConfigCoalesceDelay = Duration(
    milliseconds: 50,
  );
  Timer? _danmakuConfigTimer;
  bool _danmakuConfigInFlight = false;
  _ErikaDanmakuConfigPatch? _pendingDanmakuConfig;
  _ErikaDanmakuConfigPatch? _lastAppliedDanmakuConfig;
  final List<Completer<void>> _pendingDanmakuConfigCompleters =
      <Completer<void>>[];

  // Real Erika track descriptors, kept so the UI's index-based
  // activeAudioTracks/activeSubtitleTracks can be mapped back to native ids.
  List<ErikaTrackInfo> _videoTrackInfos = const <ErikaTrackInfo>[];
  List<ErikaTrackInfo> _audioTrackInfos = const <ErikaTrackInfo>[];
  List<ErikaTrackInfo> _subtitleTrackInfos = const <ErikaTrackInfo>[];
  List<int> _activeAudioTracks = const <int>[];
  List<int> _activeSubtitleTracks = const <int>[];
  final Set<int> _externalSubtitleTrackIds = <int>{};
  int _externalSubtitleGeneration = 0;
  Future<void> _externalSubtitleOperation = Future<void>.value();

  static const bool _subtitleTraceEnabled = bool.fromEnvironment(
    'NIPAPLAY_ERIKA_SUBTITLE_TRACE',
  );

  static ErikaOutputMode? _resolveNativeOutputMode(
    PlayerErikaAndroidOutputMode mode,
  ) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    return switch (mode) {
      PlayerErikaAndroidOutputMode.sdr => ErikaOutputMode.sdr,
      PlayerErikaAndroidOutputMode.extendedLinearHdr =>
        ErikaOutputMode.extendedLinear,
    };
  }

  static bool get _isHarmonyOS =>
      !kIsWeb && defaultTargetPlatform.name == 'ohos';

  static bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.android ||
          _isHarmonyOS);

  bool get prefersPlatformVideoSurface => _isSupported;

  bool get usesWindowOverlayVideoSurface =>
      _isSupported &&
      defaultTargetPlatform != TargetPlatform.android &&
      !_isHarmonyOS;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value.clamp(0.0, 1.0).toDouble();
    if (_isSupported) {
      unawaited(_player.setVolume(_volume));
    }
  }

  @override
  double get playbackRate => _playbackRate;

  @override
  set playbackRate(double value) {
    setPlaybackRate(value);
  }

  @override
  PlayerPlaybackState get state => _state;

  @override
  set state(PlayerPlaybackState value) {
    if (value == _state) {
      return;
    }
    switch (value) {
      case PlayerPlaybackState.playing:
        // 同步置位表达意图：后续的 pauseDirectly 不再被旧状态门拦下，
        // 而是通过在途 play 等待 + 原生命令顺序保证最终暂停生效。
        _state = PlayerPlaybackState.playing;
        _dispatchStateCommand('play', playDirectly);
        break;
      case PlayerPlaybackState.paused:
        _dispatchStateCommand('pause', pauseDirectly);
        break;
      case PlayerPlaybackState.stopped:
        _state = PlayerPlaybackState.stopped;
        _lastPositionMs = 0;
        _playbackWatchdogTimer?.cancel();
        _stopFrameActivityMonitor();
        _positionEventCount = 0;
        _lastNativePositionEventAt = null;
        _dispatchStateCommand('stop', _player.stop);
        break;
    }
  }

  void _dispatchStateCommand(
    String operation,
    Future<void> Function() command,
  ) {
    unawaited(
      command().catchError((Object error, StackTrace stackTrace) {
        final message = '$operation failed: $error';
        _lastNativeError = message;
        debugPrint('[Erika] $message');
      }),
    );
  }

  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;

  @override
  String get media => _media;

  @override
  set media(String value) {
    setMedia(value, PlayerMediaType.video);
  }

  @override
  PlayerMediaInfo get mediaInfo => _mediaInfo;

  @override
  List<int> get activeSubtitleTracks => _activeSubtitleTracks;

  @override
  set activeSubtitleTracks(List<int> value) {
    _activeSubtitleTracks = List<int>.from(value);
    _subtitleTrace(
      'activeSubtitleTracks set value=$value '
      'known=${_subtitleTrackInfos.map(_subtitleTrackLabel).join(', ')}',
    );
    if (!_isSupported) {
      return;
    }
    // Empty selection means "no subtitle".
    if (value.isEmpty) {
      unawaited(_selectSubtitleTrack(null, reason: 'activeSubtitleTracks=off'));
      return;
    }
    final index = value.first;
    if (index >= 0 && index < _subtitleTrackInfos.length) {
      unawaited(
        _selectSubtitleTrack(
          _subtitleTrackInfos[index].id,
          reason: 'activeSubtitleTracks index=$index',
        ),
      );
    } else {
      _subtitleTrace(
        'activeSubtitleTracks ignored out-of-range index=$index '
        'known_count=${_subtitleTrackInfos.length}',
      );
    }
  }

  @override
  List<int> get activeAudioTracks => _activeAudioTracks;

  @override
  set activeAudioTracks(List<int> value) {
    _activeAudioTracks = List<int>.from(value);
    if (!_isSupported) {
      return;
    }
    // Empty selection falls back to the first real audio track.
    if (value.isEmpty) {
      if (_audioTrackInfos.isNotEmpty) {
        unawaited(_player.selectAudioTrack(_audioTrackInfos.first.id));
      }
      return;
    }
    final index = value.first;
    if (index >= 0 && index < _audioTrackInfos.length) {
      unawaited(_player.selectAudioTrack(_audioTrackInfos[index].id));
    }
  }

  @override
  int get position {
    if (_state != PlayerPlaybackState.playing) {
      return _lastPositionMs;
    }
    final elapsedMs =
        DateTime.now().difference(_lastPositionUpdate).inMilliseconds;
    return _lastPositionMs + (elapsedMs * _playbackRate).round();
  }

  @override
  int get bufferedPosition => position;

  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) {}

  @override
  bool get supportsExternalSubtitles => _isSupported;

  @override
  Future<int?> updateTexture() async => null;

  @override
  void setMedia(String path, PlayerMediaType type) {
    if (type == PlayerMediaType.subtitle) {
      _subtitleTrace('setMedia subtitle path=${_describeSubtitlePath(path)}');
      _setExternalSubtitle(path);
      return;
    }
    if (type == PlayerMediaType.video || type == PlayerMediaType.unknown) {
      _subtitleTrace('setMedia video path=$path clears external tracks');
      _media = path;
      _lastPositionMs = 0;
      _lastPositionUpdate = DateTime.now();
      _mediaInfo = PlayerMediaInfo(duration: 0);
      _lastPresenterStats = const <String, dynamic>{};
      _lastOutputStatus = const <String, dynamic>{};
      _lastDecoderStatus = const <String, dynamic>{};
      _lastAudioOutputStatus = const <String, dynamic>{};
      _lastNativeError = null;
      _externalSubtitleTrackIds.clear();
      _externalSubtitleGeneration++;
      // 新媒体会话：丢弃上一个媒体的弹幕/外挂字幕缓存，停掉停滞看门狗，
      // 并复位活性信号（跨媒体累计会让“每媒体设防”与静默判定失真——
      // 换集后新媒体起播缓冲超过静默阈值会被误判为停滞）。
      _playbackWatchdogTimer?.cancel();
      _stopFrameActivityMonitor();
      _stallRecoveryCount = 0;
      _stallNudgeAttempted = false;
      _positionEventCount = 0;
      _lastNativePositionEventAt = null;
      _lastExternalSubtitlePath = null;
      _lastDanmakuJson = null;
      _lastDanmakuEnabled = null;
      _lastDanmakuGlobalOffset = null;
      // open() 会重置内核侧弹幕配置：清掉去重快照，让下一次配置全量下发，
      // 否则切集后设置未变时配置被差量去重为空补丁，新媒体样式回退内核默认。
      _lastAppliedDanmakuConfig = null;
    }
  }

  @override
  Future<void> prepare() async {
    _ensureSupported();
    if (_media.isEmpty) {
      return;
    }
    _playbackWatchdogTimer?.cancel();
    _stopFrameActivityMonitor();
    await _player.ensureCreated();
    await _player.open(_media);
    _subtitleTrace('prepare open complete media=$_media');
    _state = PlayerPlaybackState.paused;
  }

  @override
  void seek({required int position}) {
    unawaited(
      seekAndWait(position: position).catchError(
        (Object error, StackTrace stackTrace) {
          _lastNativeError = 'seek failed: $error';
          debugPrint('[Erika] seek failed: $error');
        },
      ),
    );
  }

  @override
  Future<void> seekAndWait({required int position}) async {
    final clamped = position < 0 ? 0 : position;
    _lastPositionMs = clamped;
    _lastPositionUpdate = DateTime.now();
    _pendingSeekTargetMs = clamped;
    _seekFenceUntil = DateTime.now().add(const Duration(milliseconds: 1500));
    await _player.seek(Duration(milliseconds: clamped));
  }

  @override
  void dispose() {
    unawaited(
      disposeAsync().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Erika: asynchronous dispose failed: $error');
      }),
    );
  }

  @override
  Future<void> disposeAsync() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposed = true;
    _danmakuConfigTimer?.cancel();
    _danmakuConfigTimer = null;
    _playbackWatchdogTimer?.cancel();
    _stopFrameActivityMonitor();
    _playbackWatchdogTimer = null;
    for (final completer in _pendingDanmakuConfigCompleters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _pendingDanmakuConfigCompleters.clear();
    _pendingDanmakuConfig = null;
    final eventSubscription = _eventSubscription;
    _eventSubscription = null;
    _textureIdNotifier.dispose();
    return _disposeFuture = _finishDispose(eventSubscription);
  }

  Future<void> _finishDispose(
    StreamSubscription<ErikaPlayerEvent>? eventSubscription,
  ) async {
    try {
      await eventSubscription?.cancel();
    } finally {
      await _player.dispose();
    }
  }

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    if (!_isSupported) {
      return null;
    }
    try {
      final captureWidth = width > 0 ? width : null;
      final captureHeight = height > 0 ? height : null;
      final Uint8List? bytes = await _player.screenshot(
        width: captureWidth,
        height: captureHeight,
      );
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      if (captureWidth != null && captureHeight != null) {
        final expectedRgbaBytes = captureWidth * captureHeight * 4;
        if (bytes.length != expectedRgbaBytes) {
          debugPrint(
            'Erika: screenshot native capture unavailable '
            '(expected $expectedRgbaBytes RGBA bytes, got ${bytes.length})',
          );
          return null;
        }
      }
      final video = _mediaInfo.video;
      final codec =
          video != null && video.isNotEmpty ? video.first.codec : null;
      return PlayerFrame(
        width: width > 0 ? width : (codec?.width ?? 0),
        height: height > 0 ? height : (codec?.height ?? 0),
        bytes: bytes,
      );
    } catch (error) {
      debugPrint('Erika: screenshot failed: $error');
      return null;
    }
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    _decoders[type] = List<String>.from(decoders);
  }

  @override
  List<String> getDecoders(PlayerMediaType type) =>
      List<String>.from(_decoders[type] ?? const <String>[]);

  @override
  String? getProperty(String key) => _properties[key];

  @override
  void setProperty(String key, String value) {
    _properties[key] = value;
    if (!_isSupported || _disposed) {
      return;
    }
    switch (key) {
      case 'sub-scale':
        final scale = double.tryParse(value);
        if (scale != null && scale.isFinite) {
          _lastSubtitleScale = scale;
          unawaited(
            _player.setSubtitleScale(scale).catchError((Object error) {
              debugPrint('Erika: set subtitle scale failed: $error');
            }),
          );
        }
    }
  }

  @override
  void setUserAgent(String ua) {
    // erika_flutter 暂未暴露设置 HTTP User-Agent 的接口，留空实现。
  }

  @override
  Future<void> setVideoSurfaceSize({int? width, int? height}) async {}

  @override
  Future<void> setChapter(int index) async {
    // Erika 内核不支持 MKV 章节标识。
  }

  @override
  Future<void> playDirectly() async {
    _ensureSupported();
    final playFuture = _executePlay();
    _inFlightPlay = playFuture;
    try {
      await playFuture;
    } finally {
      if (identical(_inFlightPlay, playFuture)) {
        _inFlightPlay = null;
      }
    }
  }

  Future<void> _executePlay() async {
    await _player.ensureCreated();
    await _player.play();
    _state = PlayerPlaybackState.playing;
    _lastPositionUpdate = DateTime.now();
    _armPlaybackWatchdog();
  }

  @override
  Future<void> pauseDirectly() async {
    _ensureSupported();
    _playbackWatchdogTimer?.cancel();
    _stopFrameActivityMonitor();
    // 等待在途 play 完成后再下发原生 pause：暂停态 seek 的
    // play→(延迟)→pause 序列必须保证原生命令顺序（方法通道按调用序
    // 投递），否则 pause 会先于 play 到达内核、被随后完成的 play 覆盖，
    // 视频意外转为播放。
    final inFlight = _inFlightPlay;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
      if (_disposed) {
        return;
      }
    }
    if (_state == PlayerPlaybackState.stopped) {
      return;
    }
    await _player.ensureCreated();
    _lastPositionMs = position;
    try {
      await _player.pause();
    } catch (error) {
      if (_state == PlayerPlaybackState.stopped) {
        debugPrint(
            '[Erika] pause ignored after native playback stopped: $error');
        return;
      }
      rethrow;
    }
    _state = PlayerPlaybackState.paused;
    _lastPositionUpdate = DateTime.now();
  }

  @override
  void setPlaybackRate(double rate) {
    _playbackRate = rate <= 0 ? 1.0 : rate;
    if (_isSupported) {
      unawaited(_player.setPlaybackRate(_playbackRate));
    }
  }

  void _setExternalSubtitle(String path) {
    if (!_isSupported || _disposed) {
      return;
    }
    unawaited(
      setExternalSubtitleAsync(path).catchError(
        (Object error, StackTrace stackTrace) {
          debugPrint('Erika: set external subtitle failed: $error');
        },
      ),
    );
  }

  @override
  Future<void> setExternalSubtitleAsync(String path) {
    if (!_isSupported || _disposed) {
      return Future<void>.value();
    }
    _lastExternalSubtitlePath = path;
    final generation = ++_externalSubtitleGeneration;
    final previousOperation = _externalSubtitleOperation;
    final operation = () async {
      try {
        await previousOperation;
      } catch (_) {
        // A failed replacement must not block a newer subtitle request.
      }
      await _replaceExternalSubtitle(path, generation);
    }();
    _externalSubtitleOperation = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _replaceExternalSubtitle(String path, int generation) async {
    if (_disposed || generation != _externalSubtitleGeneration) return;
    final oldTrackIds = Set<int>.from(_externalSubtitleTrackIds);
    _subtitleTrace(
      'setExternalSubtitle generation=$generation '
      'path=${_describeSubtitlePath(path)} old_track_ids=$oldTrackIds',
    );

    for (final trackId in oldTrackIds) {
      await _player.removeSubtitleTrack(trackId);
      _externalSubtitleTrackIds.remove(trackId);
      if (_disposed || generation != _externalSubtitleGeneration) return;
    }

    if (path.trim().isEmpty) {
      _activeSubtitleTracks = const <int>[];
      await _player.selectSubtitleTrack(null);
      return;
    }

    final addWatch = Stopwatch()..start();
    _subtitleTrace(
      'addExternalSubtitle begin generation=$generation '
      'path=${_describeSubtitlePath(path)}',
    );
    final trackId = await _player.addExternalSubtitle(path);
    addWatch.stop();
    _subtitleTrace(
      'addExternalSubtitle ok generation=$generation track_id=$trackId '
      'elapsed_ms=${addWatch.elapsedMilliseconds}',
    );
    if (_disposed || generation != _externalSubtitleGeneration) {
      await _player.removeSubtitleTrack(trackId);
      _subtitleTrace(
        'addExternalSubtitle stale generation=$generation '
        'current=$_externalSubtitleGeneration removed track_id=$trackId',
      );
      return;
    }
    _externalSubtitleTrackIds.add(trackId);
    await _player.selectSubtitleTrack(trackId);
    if (_disposed || generation != _externalSubtitleGeneration) {
      await _player.removeSubtitleTrack(trackId);
      _externalSubtitleTrackIds.remove(trackId);
    }
  }

  Future<void> _selectSubtitleTrack(
    int? trackId, {
    required String reason,
  }) async {
    final watch = Stopwatch()..start();
    try {
      _subtitleTrace(
        'selectSubtitleTrack begin track_id=$trackId reason=$reason',
      );
      await _player.selectSubtitleTrack(trackId);
      watch.stop();
      _subtitleTrace(
        'selectSubtitleTrack ok track_id=$trackId '
        'elapsed_ms=${watch.elapsedMilliseconds} reason=$reason',
      );
    } catch (error) {
      watch.stop();
      debugPrint('Erika: select subtitle track failed: $error');
      _subtitleTrace(
        'selectSubtitleTrack failed track_id=$trackId '
        'elapsed_ms=${watch.elapsedMilliseconds} reason=$reason error=$error',
      );
    }
  }

  bool get supportsUpscaler => _isSupported;

  Future<void> setUpscaler(PlayerUpscalerMode mode) async {
    _lastUpscalerStatus = PlayerUpscalerStatus(
      requestedMode: mode,
      activeBackend: mode == PlayerUpscalerMode.off
          ? PlayerUpscalerBackendStatus.off
          : PlayerUpscalerBackendStatus.inactive,
      fallbackCount: _lastUpscalerStatus.fallbackCount,
      upscaledFrames: _lastUpscalerStatus.upscaledFrames,
      lastEncodeDuration: _lastUpscalerStatus.lastEncodeDuration,
      lastGpuDuration: _lastUpscalerStatus.lastGpuDuration,
    );
    if (!_isSupported) return;
    try {
      await _player.setUpscaler(_toNativeUpscalerMode(mode));
      _lastUpscalerStatus = await getUpscalerStatus();
    } catch (error) {
      debugPrint('Erika: set upscaler failed: $error');
    }
  }

  Future<PlayerUpscalerStatus> getUpscalerStatus() async {
    if (!_isSupported) {
      return _lastUpscalerStatus;
    }
    try {
      final status = await _player.getUpscalerStatus();
      _lastUpscalerStatus = _convertUpscalerStatus(status);
    } catch (error) {
      debugPrint('Erika: get upscaler status failed: $error');
    }
    return _lastUpscalerStatus;
  }

  @override
  void stepForward() {
    if (!_isSupported) return;
    const frameDuration = 42; // ~24fps
    final currentPos = position;
    seek(position: currentPos + frameDuration);
  }

  @override
  void stepBackward() {
    if (!_isSupported) return;
    const frameDuration = 42; // ~24fps
    final currentPos = position;
    seek(position: (currentPos - frameDuration).clamp(0, currentPos));
  }

  Widget buildPlatformVideoSurface({
    String? debugLabel,
    ValueChanged<int?>? onPlatformViewIdChanged,
    ValueChanged<Rect?>? onFrameRectChanged,
  }) {
    _ensureSupported();
    if (defaultTargetPlatform == TargetPlatform.android || _isHarmonyOS) {
      return ErikaVideoView(
        player: _player,
        debugLabel: debugLabel,
        onPlatformViewIdChanged: onPlatformViewIdChanged,
      );
    }
    return _NipaplayErikaWindowOverlayVideoView(
      player: _player,
      debugLabel: debugLabel,
      onPlatformViewIdChanged: onPlatformViewIdChanged,
      onFrameRectChanged: onFrameRectChanged,
    );
  }

  // ---- Erika native danmaku passthrough ----
  //
  // Erika composites danmaku into the video frame natively, so when the Erika
  // kernel is active NipaPlay feeds its danmaku list + settings here instead of
  // driving its own Flutter danmaku overlay. The list uses NipaPlay's standard
  // danmaku maps ({time, content, type, color, ...}); Erika's JSON parser
  // accepts that shape directly, so it is forwarded as-is.

  bool get supportsNativeDanmaku => _isSupported;

  Future<void> loadDanmakuList(List<Map<String, dynamic>> danmakuList) async {
    if (!_isSupported) {
      return;
    }
    _lastDanmakuJson = jsonEncode(danmakuList);
    await _player.loadDanmakuJson(_lastDanmakuJson!);
  }

  Future<void> clearDanmaku() async {
    if (!_isSupported) {
      return;
    }
    _lastDanmakuJson = null;
    await _player.clearDanmaku();
  }

  Future<void> setDanmakuEnabled(bool enabled) async {
    if (!_isSupported) {
      return;
    }
    _lastDanmakuEnabled = enabled;
    await _player.setDanmakuEnabled(enabled);
  }

  Future<void> setDanmakuGlobalOffset(Duration offset) async {
    if (!_isSupported) {
      return;
    }
    _lastDanmakuGlobalOffset = offset;
    await _player.setDanmakuGlobalOffset(offset);
  }

  /// Bridges NipaPlay's danmaku display settings onto Erika's DFM+ config.
  /// All arguments are optional; only the supplied ones are pushed down.
  Future<void> setDanmakuConfig({
    bool? enabled,
    double? fontSize,
    double? opacity,
    double? displayArea,
    double? scrollDurationSeconds,
    double? scrollSpeedFactor,
    double? trackGapRatio,
    double? outlineWidth,
    int? shadowStyle,
    String? customFontFamily,
    String? customFontFilePath,
    bool? mergeDuplicates,
    bool? allowStacking,
    int? maxQuantity,
    int? maxLinesPerMode,
    bool? blockTop,
    bool? blockBottom,
    bool? blockScroll,
    List<String>? blockWords,
  }) async {
    if (!_isSupported || _disposed) {
      return;
    }
    final patch = _ErikaDanmakuConfigPatch(
      enabled: enabled,
      fontSize: fontSize,
      opacity: opacity,
      displayArea: displayArea,
      scrollDurationSeconds: scrollDurationSeconds,
      scrollSpeedFactor: scrollSpeedFactor,
      trackGapRatio: trackGapRatio,
      outlineWidth: outlineWidth,
      shadowStyle: shadowStyle,
      customFontFamily: customFontFamily,
      customFontFilePath: customFontFilePath,
      mergeDuplicates: mergeDuplicates,
      allowStacking: allowStacking,
      maxQuantity: maxQuantity,
      maxLinesPerMode: maxLinesPerMode,
      blockTop: blockTop,
      blockBottom: blockBottom,
      blockScroll: blockScroll,
      blockWords: blockWords,
    );
    if (patch.isEmpty) {
      return;
    }

    final completer = Completer<void>();
    _pendingDanmakuConfig = _pendingDanmakuConfig?.merge(patch) ?? patch;
    _pendingDanmakuConfigCompleters.add(completer);
    _scheduleDanmakuConfigFlush();
    return completer.future;
  }

  void _scheduleDanmakuConfigFlush() {
    if (_disposed || _danmakuConfigInFlight || _danmakuConfigTimer != null) {
      return;
    }
    _danmakuConfigTimer = Timer(_danmakuConfigCoalesceDelay, () {
      _danmakuConfigTimer = null;
      unawaited(_flushDanmakuConfig());
    });
  }

  Future<void> _flushDanmakuConfig() async {
    if (_disposed || _danmakuConfigInFlight) {
      return;
    }

    final requestedPatch = _pendingDanmakuConfig;
    if (requestedPatch == null) {
      return;
    }
    final completers = List<Completer<void>>.from(
      _pendingDanmakuConfigCompleters,
    );
    _pendingDanmakuConfigCompleters.clear();
    _pendingDanmakuConfig = null;

    final outgoingPatch = requestedPatch.differenceFrom(
      _lastAppliedDanmakuConfig,
    );
    if (outgoingPatch.isEmpty) {
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      if (_pendingDanmakuConfig != null) {
        _scheduleDanmakuConfigFlush();
      }
      return;
    }

    _danmakuConfigInFlight = true;
    try {
      await _player.setDanmakuConfig(
        enabled: outgoingPatch.enabled,
        fontSize: outgoingPatch.fontSize,
        opacity: outgoingPatch.opacity,
        displayArea: outgoingPatch.displayArea,
        scrollDurationSeconds: outgoingPatch.scrollDurationSeconds,
        scrollSpeedFactor: outgoingPatch.scrollSpeedFactor,
        trackGapRatio: outgoingPatch.trackGapRatio,
        outlineWidth: outgoingPatch.outlineWidth,
        shadowStyle: outgoingPatch.shadowStyle,
        customFontFamily: outgoingPatch.customFontFamily,
        customFontFilePath: outgoingPatch.customFontFilePath,
        mergeDuplicates: outgoingPatch.mergeDuplicates,
        allowStacking: outgoingPatch.allowStacking,
        maxQuantity: outgoingPatch.maxQuantity,
        maxLinesPerMode: outgoingPatch.maxLinesPerMode,
        blockTop: outgoingPatch.blockTop,
        blockBottom: outgoingPatch.blockBottom,
        blockScroll: outgoingPatch.blockScroll,
        blockWords: outgoingPatch.blockWords,
      );
      _lastAppliedDanmakuConfig =
          _lastAppliedDanmakuConfig?.merge(requestedPatch) ?? requestedPatch;
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    } catch (error, stackTrace) {
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    } finally {
      _danmakuConfigInFlight = false;
      if (_pendingDanmakuConfig != null) {
        _scheduleDanmakuConfigFlush();
      }
    }
  }

  // ---- 回前台播放停滞自愈（MediaLoadAwarePlayer） ----

  /// Play 命令成功返回后布防：若事件静默超过 [_stallEventSilenceThreshold]
  /// 且仍处于 playing 状态，先 pauseplay 快速唤醒，无效再重开媒体自愈。
  ///
  /// 只在“本媒体曾收到过原生位置事件”的 Play 上设防，避免误伤首次起播时的
  /// 网络缓冲（首次起播没有事件是正常的）；回前台恢复、后台后手动点播等都
  /// 满足该前提。桌面端（窗口 overlay）不涉及本问题，保持关闭。
  void _armPlaybackWatchdog({bool resetNudgeAttempt = true}) {
    if (!_isMobileKernelPlatform || _disposed) {
      return;
    }
    _playbackWatchdogTimer?.cancel();
    if (resetNudgeAttempt) {
      _stallNudgeAttempted = false;
    }
    if (_positionEventCount == 0) {
      return;
    }
    _playbackWatchdogTimer = Timer(_playbackWatchdogDelay, () {
      _handlePlaybackWatchdogFired();
    });
    // 同时启动渲染帧活性监控：位置事件静默检测对“黑屏但位置事件仍在发”
    // 的停摆形态失明，渲染帧计数才是视频管线的真活性。
    _startFrameActivityMonitor();
  }

  /// 每 2.5 秒采样一次 presenter 渲染帧计数；playing 状态下连续两次采样
  /// 帧数无推进即判定视频管线停摆，走与位置静默相同的自愈路径。
  void _startFrameActivityMonitor() {
    _frameActivityTimer?.cancel();
    _lastRenderedFramesSample = null;
    _frameActivityTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) => unawaited(_checkFrameActivity()),
    );
  }

  void _stopFrameActivityMonitor() {
    _frameActivityTimer?.cancel();
    _frameActivityTimer = null;
    _lastRenderedFramesSample = null;
  }

  Future<void> _checkFrameActivity() async {
    if (_disposed || _stallRecoveryInFlight) {
      return;
    }
    if (_state != PlayerPlaybackState.playing) {
      return;
    }
    final int? rendered;
    try {
      final stats = await _player.getPresenterStats();
      rendered = stats.renderedVideoFrames;
    } catch (_) {
      return;
    }
    if (_disposed || rendered == null || rendered <= 0) {
      return;
    }
    final previous = _lastRenderedFramesSample;
    _lastRenderedFramesSample = rendered;
    if (previous == null || rendered != previous) {
      // 帧在推进 = 播放正常，清掉停滞计数。
      _stallRecoveryCount = 0;
      _stallNudgeAttempted = false;
      return;
    }
    if (_stallNudgeAttempted) {
      return; // 已唤醒过一轮，交给位置静默/重开流程处理，避免重复计数。
    }
    _stallNudgeAttempted = true;
    debugPrint(
      '[Erika] playing 状态下渲染帧数无推进($previous)，判定视频管线停摆，'
      '自动执行 pause→play 唤醒',
    );
    logPlayerEvent(
      'Erika',
      '检测到回前台画面停滞（渲染帧无推进），自动执行 pause→play 唤醒',
      level: 'WARN',
    );
    unawaited(
      _nudgeStalledPlayback().whenComplete(() {
        _armPlaybackWatchdog(resetNudgeAttempt: false);
      }),
    );
  }

  void _handlePlaybackWatchdogFired() {
    if (_disposed || _stallRecoveryInFlight) {
      return;
    }
    if (_state != PlayerPlaybackState.playing) {
      return;
    }
    final lastEventAt = _lastNativePositionEventAt;
    final silence = lastEventAt == null
        ? null
        : DateTime.now().difference(lastEventAt);
    if (silence != null && silence < _stallEventSilenceThreshold) {
      // 内核仍在产生位置事件 = 播放正常，同时清掉连续自愈计数。
      _stallRecoveryCount = 0;
      _stallNudgeAttempted = false;
      return;
    }
    final fenceUntil = _seekFenceUntil;
    if (fenceUntil != null && DateTime.now().isBefore(fenceUntil)) {
      // 用户正在拖动/强制刷新帧，等 fence 过期后再复查。
      _armPlaybackWatchdog();
      return;
    }
    if (!_stallNudgeAttempted) {
      // 第一优先：pauseplay 快速唤醒（回前台实测有效，比重开媒体快得多）。
      _stallNudgeAttempted = true;
      debugPrint(
        '[Erika] Play 后位置事件静默 ${silence?.inMilliseconds ?? -1}ms，'
        '执行 pauseplay 快速唤醒',
      );
      logPlayerEvent(
        'Erika',
        '检测到回前台播放停滞（${_playbackWatchdogDelay.inSeconds}s 无位置事件），'
        '自动执行 pauseplay 唤醒',
        level: 'WARN',
      );
      unawaited(
        _nudgeStalledPlayback().whenComplete(() {
          // 唤醒成功则下一轮看门狗判定为健康；仍无效则进入重开流程。
          _armPlaybackWatchdog(resetNudgeAttempt: false);
        }),
      );
      return;
    }
    if (_stallRecoveryCount >= _maxConsecutiveStallRecoveries) {
      debugPrint(
        '[Erika] 已连续自愈 $_stallRecoveryCount 次仍无位置事件，停止自动恢复',
      );
      return;
    }
    _stallRecoveryCount += 1;
    unawaited(_recoverStalledPlayback());
  }

  /// 轻量唤醒：原生 pauseplay。回前台后内核时钟停摆时，用户手动“暂停再
  /// 播放”能恢复，这里自动做同样的事，免去用户手动操作。
  Future<void> _nudgeStalledPlayback() async {
    if (_disposed) {
      return;
    }
    try {
      await _player.pause();
      await _player.play();
      debugPrint('[Erika] pauseplay 快速唤醒已下发');
    } catch (error) {
      debugPrint('[Erika] pauseplay 快速唤醒失败: $error');
    }
  }

  Future<void> _recoverStalledPlayback() async {
    if (_stallRecoveryInFlight || _disposed) {
      return;
    }
    _stallRecoveryInFlight = true;
    try {
      final wasPlaying = _state == PlayerPlaybackState.playing;
      debugPrint(
        '[Erika] Play 后 ${_playbackWatchdogDelay.inSeconds}s 无原生位置事件，'
        '判定播放停摆，重开媒体自愈（第 $_stallRecoveryCount 次）',
      );
      logPlayerEvent(
        'Erika',
        '快速唤醒无效，重开媒体自愈（第 $_stallRecoveryCount 次）',
        level: 'WARN',
      );
      final recovered = await retryCurrentMediaLoad();
      if (!recovered || _disposed || !wasPlaying) {
        return;
      }
      await playDirectly();
      debugPrint('[Erika] 停滞自愈完成，播放已重新拉起');
      logPlayerEvent('Erika', '停滞自愈完成，播放已自动恢复');
    } catch (error) {
      debugPrint('[Erika] 停滞自愈失败: $error');
      logPlayerEvent('Erika', '停滞自愈失败: $error', level: 'ERROR');
    } finally {
      _stallRecoveryInFlight = false;
    }
  }

  @override
  bool get isMediaReady => _mediaInfo.duration > 0;

  @override
  bool get hasReceivedRealPosition => _positionEventCount > 0;

  @override
  bool get hasMediaLoadFailed => _mediaInfo.specificErrorMessage != null;

  @override
  String? get mediaLoadError =>
      _mediaInfo.specificErrorMessage ?? _lastNativeError;

  @override
  Future<bool> waitUntilMediaReady({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (!_disposed) {
      if (_mediaInfo.duration > 0) {
        return true;
      }
      if (!DateTime.now().isBefore(deadline)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return !_disposed && _mediaInfo.duration > 0;
  }

  /// 重开当前媒体以恢复停摆的内核播放管线，并把播放位置恢复到最后已知处。
  ///
  /// 与 media_kit 的同名方法语义对齐：只负责重载，不自动播放，由调用方决定
  /// 是否续播。重开成功后会恢复音量/倍速/字幕缩放/弹幕（列表+配置）与外挂
  /// 字幕，位置通过内部 seekAndWait 恢复（含 seek fence 保护）。
  @override
  Future<bool> retryCurrentMediaLoad() async {
    if (!_isSupported || _disposed || _media.isEmpty) {
      return false;
    }
    _playbackWatchdogTimer?.cancel();
    _stopFrameActivityMonitor();
    final restorePositionMs = _lastPositionMs;
    // open() 会重置内核侧弹幕配置：先截获当前配置用于重放，同时清空去重
    // 快照，保证重放后的下一次常规配置下发也不会被差量去重吞掉。
    final configToReplay = _lastAppliedDanmakuConfig;
    _lastAppliedDanmakuConfig = null;
    debugPrint(
      '[Erika] retryCurrentMediaLoad: 重开 media=$_media '
      'restorePos=${restorePositionMs}ms',
    );
    try {
      await _player.ensureCreated();
      // 会话级媒体信息按“新一次 Open”处理，避免沿用旧 duration 导致就绪
      // 判定直接误报为已就绪。
      _mediaInfo = PlayerMediaInfo(duration: 0);
      _externalSubtitleTrackIds.clear();
      _externalSubtitleGeneration++;
      _activeSubtitleTracks = const <int>[];
      await _player.open(_media);
      final ready = await waitUntilMediaReady(timeout: const Duration(seconds: 5));
      if (_disposed) {
        return false;
      }
      if (!ready) {
        debugPrint('[Erika] 重开后媒体未在超时内就绪，仍继续尝试恢复播放');
      }
      if (restorePositionMs > 0) {
        await seekAndWait(position: restorePositionMs);
      }
      unawaited(_player.setVolume(_volume));
      unawaited(_player.setPlaybackRate(_playbackRate));
      final subtitleScale = _lastSubtitleScale;
      if (subtitleScale != null) {
        unawaited(
          _player.setSubtitleScale(subtitleScale).catchError((Object error) {
            debugPrint('[Erika] 自愈恢复字幕缩放失败: $error');
          }),
        );
      }
      final danmakuJson = _lastDanmakuJson;
      if (danmakuJson != null && danmakuJson.isNotEmpty) {
        unawaited(
          _player.loadDanmakuJson(danmakuJson).catchError((Object error) {
            debugPrint('[Erika] 自愈恢复弹幕列表失败: $error');
          }),
        );
        final danmakuOffset = _lastDanmakuGlobalOffset;
        if (danmakuOffset != null) {
          unawaited(
            _player.setDanmakuGlobalOffset(danmakuOffset).catchError((_) {}),
          );
        }
        final danmakuEnabled = _lastDanmakuEnabled;
        if (danmakuEnabled != null) {
          unawaited(
            _player.setDanmakuEnabled(danmakuEnabled).catchError((_) {}),
          );
        }
      }
      final appliedConfig = configToReplay;
      if (appliedConfig != null && !appliedConfig.isEmpty) {
        unawaited(
          _player
              .setDanmakuConfig(
                enabled: appliedConfig.enabled,
                fontSize: appliedConfig.fontSize,
                opacity: appliedConfig.opacity,
                displayArea: appliedConfig.displayArea,
                scrollDurationSeconds: appliedConfig.scrollDurationSeconds,
                scrollSpeedFactor: appliedConfig.scrollSpeedFactor,
                trackGapRatio: appliedConfig.trackGapRatio,
                outlineWidth: appliedConfig.outlineWidth,
                shadowStyle: appliedConfig.shadowStyle,
                customFontFamily: appliedConfig.customFontFamily,
                customFontFilePath: appliedConfig.customFontFilePath,
                mergeDuplicates: appliedConfig.mergeDuplicates,
                allowStacking: appliedConfig.allowStacking,
                maxQuantity: appliedConfig.maxQuantity,
                maxLinesPerMode: appliedConfig.maxLinesPerMode,
                blockTop: appliedConfig.blockTop,
                blockBottom: appliedConfig.blockBottom,
                blockScroll: appliedConfig.blockScroll,
                blockWords: appliedConfig.blockWords,
              )
              .catchError((Object error) {
                debugPrint('[Erika] 自愈恢复弹幕配置失败: $error');
              }),
        );
      }
      final subtitlePath = _lastExternalSubtitlePath;
      if (subtitlePath != null && subtitlePath.trim().isNotEmpty) {
        await setExternalSubtitleAsync(subtitlePath);
      }
      return true;
    } catch (error) {
      debugPrint('[Erika] retryCurrentMediaLoad 失败: $error');
      return false;
    }
  }

  Map<String, dynamic> getDetailedMediaInfo() {
    return <String, dynamic>{
      'kernel': 'Erika',
      'state': _state.name,
      'position': position,
      'duration': _mediaInfo.duration,
      'upscaler': _lastUpscalerStatus.toMap(),
      'presenterStats': _lastPresenterStats,
      'outputStatus': _lastOutputStatus,
      'decoder': _lastDecoderStatus,
      'audioOutput': _lastAudioOutputStatus,
      if (_lastNativeError != null) 'lastError': _lastNativeError,
      'tracks': <String, dynamic>{
        'video': _videoTrackInfos.map(_erikaTrackToDebugMap).toList(),
        'audio': _audioTrackInfos.map(_erikaTrackToDebugMap).toList(),
        'subtitle': _subtitleTrackInfos.map(_erikaTrackToDebugMap).toList(),
      },
      'videoWidth': _mediaInfo.video?.isNotEmpty == true
          ? _mediaInfo.video!.first.codec.width
          : null,
      'videoHeight': _mediaInfo.video?.isNotEmpty == true
          ? _mediaInfo.video!.first.codec.height
          : null,
    };
  }

  Future<Map<String, dynamic>> getDetailedMediaInfoAsync() async {
    await getUpscalerStatus();
    await _refreshPresenterStats();
    return getDetailedMediaInfo();
  }

  Future<void> _refreshPresenterStats() async {
    if (!_isSupported) {
      return;
    }
    try {
      final stats = await _player.getPresenterStats();
      _lastPresenterStats = Map<String, dynamic>.from(stats.toMap());
    } catch (error) {
      debugPrint('Erika: get presenter stats failed: $error');
    }
    try {
      final output = await _player.getOutputStatus();
      _lastOutputStatus = _outputStatusToMap(output);
    } catch (error) {
      debugPrint('Erika: get output status failed: $error');
    }
  }

  static Map<String, dynamic> _outputStatusToMap(ErikaOutputStatus status) {
    return <String, dynamic>{
      'requestedMode': status.requestedMode.name,
      'activeEncoding': status.activeEncoding.name,
      'surfaceFormat': status.surfaceFormat.name,
      'nativeDataSpace': status.nativeDataSpace,
      'requestedHeadroom': status.requestedHeadroom,
      'activeHeadroom': status.activeHeadroom,
      'activeHeadroomKnown': status.activeHeadroomKnown,
      'extendedLinearActive': status.extendedLinearActive,
      'fallbackReason': status.fallbackReason.label,
      'fallbackCount': status.fallbackCount,
      'dataSpaceFailures': status.dataSpaceFailures,
      'headroomUpdates': status.headroomUpdates,
      'extendedLinearFrames': status.extendedLinearFrames,
    };
  }

  ErikaUpscalerMode _toNativeUpscalerMode(PlayerUpscalerMode mode) {
    switch (mode) {
      case PlayerUpscalerMode.erikaArtCnnC4F16:
        return ErikaUpscalerMode.artCnnC4F16;
      case PlayerUpscalerMode.erikaArtCnnC4F32:
        return ErikaUpscalerMode.artCnnC4F32;
      case PlayerUpscalerMode.erikaArtCnnC4F16Ds:
        return ErikaUpscalerMode.artCnnC4F16Ds;
      case PlayerUpscalerMode.off:
        return ErikaUpscalerMode.off;
    }
  }

  PlayerUpscalerMode _fromNativeUpscalerMode(ErikaUpscalerMode mode) {
    switch (mode) {
      case ErikaUpscalerMode.artCnnC4F16:
        return PlayerUpscalerMode.erikaArtCnnC4F16;
      case ErikaUpscalerMode.artCnnC4F32:
        return PlayerUpscalerMode.erikaArtCnnC4F32;
      case ErikaUpscalerMode.artCnnC4F16Ds:
        return PlayerUpscalerMode.erikaArtCnnC4F16Ds;
      case ErikaUpscalerMode.off:
        return PlayerUpscalerMode.off;
    }
  }

  PlayerUpscalerBackendStatus _fromNativeUpscalerBackend(
    ErikaUpscalerBackendStatus status,
  ) {
    switch (status) {
      case ErikaUpscalerBackendStatus.off:
        return PlayerUpscalerBackendStatus.off;
      case ErikaUpscalerBackendStatus.inactive:
        return PlayerUpscalerBackendStatus.inactive;
      case ErikaUpscalerBackendStatus.building:
        return PlayerUpscalerBackendStatus.building;
      case ErikaUpscalerBackendStatus.scalar:
        return PlayerUpscalerBackendStatus.scalar;
      case ErikaUpscalerBackendStatus.simdgroupMatrix:
        return PlayerUpscalerBackendStatus.simdgroupMatrix;
    }
  }

  PlayerUpscalerStatus _convertUpscalerStatus(ErikaUpscalerStatus status) {
    return PlayerUpscalerStatus(
      requestedMode: _fromNativeUpscalerMode(status.requestedMode),
      activeBackend: _fromNativeUpscalerBackend(status.activeBackend),
      fallbackCount: status.fallbackCount,
      upscaledFrames: status.upscaledFrames,
      lastEncodeDuration: status.lastEncodeDuration,
      lastGpuDuration: status.lastGpuDuration,
    );
  }

  void _handleEvent(ErikaPlayerEvent event) {
    if (_disposed) {
      return;
    }
    if (event.kind == ErikaEventKind.error) {
      final errorMessage = _formatPlaybackError(event);
      _lastNativeError = errorMessage;
      _mediaInfo = _mediaInfo.copyWith(specificErrorMessage: errorMessage);
      debugPrint(
        '[Erika] playback error '
        'player=${event.playerId} state=${event.state.name} '
        'status=${event.status} error=${event.error ?? '-'} '
        'message=${event.message ?? '-'}',
      );
    }

    final decoder = event.decoder;
    if (event.kind == ErikaEventKind.videoDecoderChanged && decoder != null) {
      _lastDecoderStatus = <String, dynamic>{
        'stage': decoder.stage,
        'requestedBackend': decoder.requestedBackend,
        'previousBackend': decoder.previousBackend,
        'activeBackend': decoder.activeBackend,
        'fallbackCount': decoder.fallbackCount,
        'codec': decoder.codec,
        'pixelFormat': decoder.pixelFormat,
        'lineSizes': decoder.lineSizes,
        'reason': decoder.reason,
      };
      debugPrint(
        '[Erika] video decoder changed '
        'stage=${decoder.stage} requested=${decoder.requestedBackend} '
        'previous=${decoder.previousBackend ?? '-'} '
        'active=${decoder.activeBackend} fallbacks=${decoder.fallbackCount} '
        'codec=${decoder.codec ?? '-'} format=${decoder.pixelFormat ?? '-'} '
        'reason=${decoder.reason ?? '-'}',
      );
    }

    final audio = event.audio;
    if (event.kind == ErikaEventKind.audioOutputChanged && audio != null) {
      _lastAudioOutputStatus = <String, dynamic>{
        'recoveryState': audio.recoveryState,
        'lastErrorCode': audio.lastErrorCode,
        'recoveryAttempts': audio.recoveryAttempts,
        'recoveryCount': audio.recoveryCount,
        'recoveryFailures': audio.recoveryFailures,
        'transitionSequence': audio.transitionSequence,
      };
      debugPrint(
        '[Erika] audio output changed '
        'state=${audio.recoveryState} errorCode=${audio.lastErrorCode} '
        'attempts=${audio.recoveryAttempts} recoveries=${audio.recoveryCount} '
        'failures=${audio.recoveryFailures} '
        'sequence=${audio.transitionSequence}',
      );
    }

    if (event.kind == ErikaEventKind.stateChanged ||
        event.kind == ErikaEventKind.error) {
      switch (event.state) {
        case ErikaPlaybackState.playing:
          _state = PlayerPlaybackState.playing;
          break;
        case ErikaPlaybackState.paused:
        case ErikaPlaybackState.ready:
        case ErikaPlaybackState.opening:
          _state = PlayerPlaybackState.paused;
          break;
        case ErikaPlaybackState.stopped:
        case ErikaPlaybackState.closed:
        case ErikaPlaybackState.idle:
        case ErikaPlaybackState.error:
          _state = PlayerPlaybackState.stopped;
          break;
      }
    }

    if (event.kind == ErikaEventKind.positionChanged &&
        event.position >= Duration.zero) {
      // 活性信号：任何原生位置事件都证明播放管线仍在推进（含 seek 回报）。
      _positionEventCount++;
      _lastNativePositionEventAt = DateTime.now();
      final eventPositionMs = event.position.inMilliseconds;
      final now = DateTime.now();
      final seekTarget = _pendingSeekTargetMs;
      final fenceUntil = _seekFenceUntil;
      if (seekTarget != null &&
          fenceUntil != null &&
          now.isBefore(fenceUntil)) {
        final distance = (eventPositionMs - seekTarget).abs();
        if (distance > 1500) {
          return;
        }
        _pendingSeekTargetMs = null;
        _seekFenceUntil = null;
      } else if (fenceUntil != null && !now.isBefore(fenceUntil)) {
        _pendingSeekTargetMs = null;
        _seekFenceUntil = null;
      }
      _lastPositionMs = eventPositionMs;
      _lastPositionUpdate = now;
    }

    var updatedInfo = _mediaInfo;
    if (event.duration > Duration.zero) {
      updatedInfo = updatedInfo.copyWith(
        duration: event.duration.inMilliseconds,
      );
    }
    if (event.video.width > 0 && event.video.height > 0) {
      updatedInfo = updatedInfo.copyWith(
        video: <PlayerVideoStreamInfo>[
          PlayerVideoStreamInfo(
            codec: PlayerVideoCodecParams(
              width: event.video.width,
              height: event.video.height,
              name: 'Erika Video',
            ),
            codecName: 'unknown',
          ),
        ],
      );
    }
    // Erika emits the full descriptor list (with native ids, titles and the
    // selected flag) on TracksChanged/TrackSelectionChanged. Use it to build
    // mediaInfo so the UI's index-based track selection maps to real ids.
    if (event.trackList.isNotEmpty) {
      final videoInfos = event.trackList
          .where((t) => t.kind == ErikaTrackKind.video)
          .toList(growable: false);
      final audioInfos = event.trackList
          .where((t) => t.kind == ErikaTrackKind.audio)
          .toList(growable: false);
      final subtitleInfos = event.trackList
          .where((t) => t.kind == ErikaTrackKind.subtitle)
          .toList(growable: false);
      _subtitleTrace(
        'event trackList kind=${event.kind} '
        'subtitles=${subtitleInfos.map(_subtitleTrackLabel).join(', ')}',
      );
      _audioTrackInfos = audioInfos;
      _videoTrackInfos = videoInfos;
      _subtitleTrackInfos = subtitleInfos;
      updatedInfo = updatedInfo.copyWith(
        video: videoInfos.isEmpty
            ? null
            : <PlayerVideoStreamInfo>[
                for (var i = 0; i < videoInfos.length; i++)
                  PlayerVideoStreamInfo(
                    codec: PlayerVideoCodecParams(
                      width: videoInfos[i].width > 0
                          ? videoInfos[i].width
                          : event.video.width,
                      height: videoInfos[i].height > 0
                          ? videoInfos[i].height
                          : event.video.height,
                      name: _formatErikaVideoCodecParams(videoInfos[i]),
                    ),
                    codecName: videoInfos[i].codec ?? 'unknown',
                  ),
              ],
        audio: <PlayerAudioStreamInfo>[
          for (var i = 0; i < audioInfos.length; i++)
            PlayerAudioStreamInfo(
              codec: PlayerAudioCodecParams(
                name: audioInfos[i].codec ?? 'unknown',
                channels:
                    audioInfos[i].channels > 0 ? audioInfos[i].channels : null,
                sampleRate: audioInfos[i].sampleRate > 0
                    ? audioInfos[i].sampleRate
                    : null,
              ),
              title: audioInfos[i].title ?? 'Audio ${i + 1}',
              language: audioInfos[i].language,
              metadata: <String, String>{
                'id': '${audioInfos[i].id}',
                if (audioInfos[i].sampleFormat != null)
                  'sampleFormat': audioInfos[i].sampleFormat!,
              },
              rawRepresentation: 'Erika Audio ${i + 1}',
            ),
        ],
        subtitle: <PlayerSubtitleStreamInfo>[
          for (var i = 0; i < subtitleInfos.length; i++)
            PlayerSubtitleStreamInfo(
              title: subtitleInfos[i].title ?? 'Subtitle ${i + 1}',
              language: subtitleInfos[i].language,
              metadata: <String, String>{'id': '${subtitleInfos[i].id}'},
              rawRepresentation: 'Erika Subtitle ${i + 1}',
            ),
        ],
      );
      _activeAudioTracks = <int>[
        for (var i = 0; i < audioInfos.length; i++)
          if (audioInfos[i].selected) i,
      ];
      _activeSubtitleTracks = <int>[
        for (var i = 0; i < subtitleInfos.length; i++)
          if (subtitleInfos[i].selected) i,
      ];
      _subtitleTrace(
        'event activeSubtitleTracks=$_activeSubtitleTracks '
        'external_track_ids=$_externalSubtitleTrackIds',
      );
    }
    _mediaInfo = updatedInfo;
  }

  static String _formatPlaybackError(ErikaPlayerEvent event) {
    final error = event.error?.trim();
    final message = event.message?.trim();
    final details = <String>[
      if (error != null && error.isNotEmpty) error,
      if (message != null && message.isNotEmpty && message != error) message,
      if (event.status != 0) 'status=${event.status}',
    ];
    return details.isEmpty
        ? 'Erika 播放失败（未返回详细原因）'
        : 'Erika 播放失败：${details.join('；')}';
  }

  static String _formatErikaVideoCodecParams(ErikaTrackInfo track) {
    final parts = <String>[
      if (track.codec != null) 'codec: ${track.codec}',
      if (track.profile != null) 'profile: ${track.profile}',
      if (track.level > 0) 'level: ${track.level}',
      if (track.width > 0 && track.height > 0) '${track.width}x${track.height}',
      if (track.pixelFormat != null) 'format: ${track.pixelFormat}',
    ];
    return parts.isEmpty ? 'Erika Video' : parts.join(', ');
  }

  static Map<String, dynamic> _erikaTrackToDebugMap(ErikaTrackInfo track) {
    return <String, dynamic>{
      'id': track.id,
      'kind': track.kind.name,
      'source': track.source.name,
      'selected': track.selected,
      'canRemove': track.canRemove,
      if (track.title != null) 'title': track.title,
      if (track.language != null) 'language': track.language,
      if (track.codec != null) 'codec': track.codec,
      if (track.width > 0) 'width': track.width,
      if (track.height > 0) 'height': track.height,
      if (track.sampleRate > 0) 'sampleRate': track.sampleRate,
      if (track.channels > 0) 'channels': track.channels,
      if (track.pixelFormat != null) 'pixelFormat': track.pixelFormat,
      if (track.sampleFormat != null) 'sampleFormat': track.sampleFormat,
      if (track.profile != null) 'profile': track.profile,
      if (track.level > 0) 'level': track.level,
    };
  }

  static void _subtitleTrace(String message) {
    if (_subtitleTraceEnabled) {
      debugPrint('[nipa-erika-subtitle-trace] $message');
    }
  }

  static String _subtitleTrackLabel(ErikaTrackInfo track) {
    return '{id=${track.id}, source=${track.source.name}, '
        'selected=${track.selected}, canRemove=${track.canRemove}, '
        'title=${track.title}, lang=${track.language}, codec=${track.codec}}';
  }

  static String _describeSubtitlePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '<empty>';
    }
    try {
      final file = File(trimmed);
      final stat = file.statSync();
      return '$trimmed exists=${stat.type != FileSystemEntityType.notFound} '
          'size=${stat.size} modified=${stat.modified.toIso8601String()}';
    } catch (error) {
      return '$trimmed stat_error=$error';
    }
  }

  void _ensureSupported() {
    if (!_isSupported) {
      throw UnsupportedError(
        'Erika is currently only wired on Android/iOS/macOS/Windows/HarmonyOS.',
      );
    }
  }
}
