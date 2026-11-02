import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'erika_player.dart';

bool get _supportsWindowOverlayVideoView =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows);

bool get _usesAndroidTextureView =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _usesOhosTextureView =>
    !kIsWeb && (defaultTargetPlatform.name == 'ohos' ||
        defaultTargetPlatform == TargetPlatform.linux);

bool get _supportsFlutterTextureVideoView =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        _usesOhosTextureView);

/// Native video surface backed by AppKit/UIKit or a Windows HWND.
///
/// Windows keeps video outside Flutter's texture compositor so opaque playback
/// can negotiate HDR10. Use [ErikaTextureVideoView] explicitly for SDR content
/// that needs Flutter clipping or color filters.
///
/// This is the compatibility surface. Full-player Apple hosts should usually
/// prefer [ErikaWindowOverlayVideoView] so liberika owns the native Metal video
/// plane outside Flutter's platform-view compositor.
/// Linux uses an SDR texture here. On Wayland, explicitly use
/// [ErikaWindowOverlayVideoView] for a native plane below transparent Flutter UI.
class ErikaVideoView extends StatefulWidget {
  const ErikaVideoView({
    super.key,
    required this.player,
    this.debugLabel,
    this.onPlatformViewIdChanged,
    this.blendMode = BlendMode.srcOver,
    this.opacity = 1.0,
  }) : assert(opacity >= 0.0 && opacity <= 1.0);

  final ErikaPlayer player;
  final String? debugLabel;
  final ValueChanged<int?>? onPlatformViewIdChanged;
  final BlendMode blendMode;
  final double opacity;

  @override
  State<ErikaVideoView> createState() => _ErikaVideoViewState();
}

/// Video surface composited as a Flutter [Texture].
///
/// On macOS this uses an IOSurface-backed Metal texture, and on Windows it uses
/// a shareable D3D11 texture. Regular Flutter effects such as opacity, clipping
/// and color filters therefore apply to the video on both desktop platforms.
/// Windows textures are SDR; use [ErikaVideoView] for native HDR playback.
/// Windows supports [BlendMode.srcOver] and native [BlendMode.overlay] only.
class ErikaTextureVideoView extends StatelessWidget {
  const ErikaTextureVideoView({
    super.key,
    required this.player,
    this.debugLabel,
    this.onTextureIdChanged,
    this.blendMode = BlendMode.srcOver,
    this.opacity = 1.0,
  }) : assert(opacity >= 0.0 && opacity <= 1.0);

  final ErikaPlayer player;
  final String? debugLabel;
  final ValueChanged<int?>? onTextureIdChanged;
  final BlendMode blendMode;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        blendMode != BlendMode.srcOver) {
      return ErikaVideoView(
        player: player,
        debugLabel: debugLabel,
        onPlatformViewIdChanged: onTextureIdChanged,
        blendMode: blendMode,
        opacity: opacity,
      );
    }
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        blendMode != BlendMode.srcOver) {
      if (blendMode != BlendMode.overlay) {
        throw UnsupportedError(
          'Windows ErikaTextureVideoView supports only srcOver and overlay.',
        );
      }
      return ErikaWindowOverlayVideoView(
        player: player,
        debugLabel: debugLabel,
        onPlatformViewIdChanged: onTextureIdChanged,
        blendMode: blendMode,
        opacity: opacity,
      );
    }
    if (_supportsFlutterTextureVideoView) {
      return Opacity(
        opacity: opacity,
        child: _ErikaOhosVideoView(
          player: player,
          onPlatformViewIdChanged: onTextureIdChanged,
        ),
      );
    }
    return ErikaVideoView(
      player: player,
      debugLabel: debugLabel,
      onPlatformViewIdChanged: onTextureIdChanged,
      blendMode: blendMode,
      opacity: opacity,
    );
  }
}

class _ErikaVideoViewState extends State<ErikaVideoView> {
  int? _viewId;

  @override
  void didUpdateWidget(covariant ErikaVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      final viewId = _viewId;
      if (viewId != null) {
        unawaited(oldWidget.player.detachView(viewId));
        unawaited(widget.player.attachView(viewId));
      }
    }
  }

  @override
  void dispose() {
    final viewId = _viewId;
    widget.onPlatformViewIdChanged?.call(null);
    if (viewId != null) {
      unawaited(widget.player.detachView(viewId));
    }
    super.dispose();
  }

  void _handlePlatformViewCreated(int id) {
    if (!mounted) {
      return;
    }
    _viewId = id;
    widget.onPlatformViewIdChanged?.call(id);
    unawaited(widget.player.attachView(id));
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }
    final creationParams = <String, Object?>{
      if (widget.debugLabel case final label?) 'debugLabel': label,
      if (widget.player.videoAlphaMode != ErikaVideoAlphaMode.opaque)
        'videoAlphaMode': widget.player.videoAlphaMode.nativeValue,
      if (widget.blendMode != BlendMode.srcOver)
        'blendMode': widget.blendMode.name,
      if (widget.opacity != 1.0) 'opacity': widget.opacity,
    };
    if (_usesOhosTextureView) {
      return _ErikaOhosVideoView(
        player: widget.player,
        onPlatformViewIdChanged: widget.onPlatformViewIdChanged,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return AppKitView(
          key: ValueKey<Object>((
            widget.player.videoAlphaMode,
            widget.blendMode,
            widget.opacity,
          )),
          viewType: 'erika_flutter/video_view',
          layoutDirection: TextDirection.ltr,
          creationParamsCodec: const StandardMessageCodec(),
          creationParams: creationParams,
          onPlatformViewCreated: _handlePlatformViewCreated,
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: 'erika_flutter/video_view',
          layoutDirection: TextDirection.ltr,
          creationParamsCodec: const StandardMessageCodec(),
          creationParams: creationParams,
          onPlatformViewCreated: _handlePlatformViewCreated,
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        );
      case TargetPlatform.windows:
        return ErikaWindowOverlayVideoView(
          player: widget.player,
          debugLabel: widget.debugLabel,
          onPlatformViewIdChanged: widget.onPlatformViewIdChanged,
          blendMode: widget.blendMode,
          opacity: widget.opacity,
        );
      case TargetPlatform.android:
        return _ErikaAndroidVideoView(
          player: widget.player,
          debugLabel: widget.debugLabel,
          onPlatformViewIdChanged: widget.onPlatformViewIdChanged,
        );
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
        return const SizedBox.shrink();
      // The HarmonyOS Flutter fork adds TargetPlatform.ohos. Stock Flutter
      // considers the cases above exhaustive, while the fork needs this
      // fallback after the name-based OHOS branch at the top of this method.
      // ignore: unreachable_switch_default
      default:
        return const SizedBox.shrink();
    }
  }
}

class _OhosSurfaceMetrics {
  const _OhosSurfaceMetrics(this.width, this.height, this.scale);

  final int width;
  final int height;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is _OhosSurfaceMetrics &&
      width == other.width &&
      height == other.height &&
      scale == other.scale;

  @override
  int get hashCode => Object.hash(width, height, scale);
}

class _ErikaOhosVideoView extends StatefulWidget {
  const _ErikaOhosVideoView({
    required this.player,
    this.onPlatformViewIdChanged,
  });

  final ErikaPlayer player;
  final ValueChanged<int?>? onPlatformViewIdChanged;

  @override
  State<_ErikaOhosVideoView> createState() => _ErikaOhosVideoViewState();
}

class _ErikaOhosVideoViewState extends State<_ErikaOhosVideoView> {
  int? _textureId;
  int _generation = 0;
  bool _updateInFlight = false;
  _OhosSurfaceMetrics? _activeMetrics;
  _OhosSurfaceMetrics? _pendingMetrics;

  @override
  void didUpdateWidget(covariant _ErikaOhosVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player == widget.player) {
      return;
    }
    final textureId = _textureId;
    if (textureId != null) {
      final generation = ++_generation;
      unawaited(
        _switchPlayer(oldWidget.player, widget.player, textureId, generation),
      );
    }
  }

  @override
  void dispose() {
    final generation = ++_generation;
    final textureId = _textureId;
    _textureId = null;
    widget.onPlatformViewIdChanged?.call(null);
    if (textureId != null) {
      unawaited(_disposeTexture(widget.player, textureId, generation));
    }
    super.dispose();
  }

  Future<void> _switchPlayer(
    ErikaPlayer oldPlayer,
    ErikaPlayer newPlayer,
    int textureId,
    int generation,
  ) async {
    try {
      await oldPlayer.detachView(textureId);
      if (!mounted ||
          generation != _generation ||
          !identical(widget.player, newPlayer) ||
          _textureId != textureId) {
        return;
      }
      await newPlayer.attachView(textureId);
    } catch (error) {
      debugPrint('ErikaOhosVideoView: player switch failed: $error');
    }
  }

  Future<void> _disposeTexture(
    ErikaPlayer player,
    int textureId,
    int generation,
  ) async {
    try {
      await player.detachView(textureId);
    } catch (_) {
      // releaseTexture is authoritative and detaches any remaining binding.
    }
    try {
      await player.releaseTextureSurface(textureId);
    } catch (error) {
      debugPrint(
        'ErikaOhosVideoView: texture release failed '
        '(generation $generation): $error',
      );
    }
  }

  void _queueMetrics(_OhosSurfaceMetrics metrics) {
    if (metrics == _activeMetrics && _pendingMetrics == null) {
      return;
    }
    _pendingMetrics = metrics;
    if (_updateInFlight) {
      return;
    }
    _updateInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_flushMetrics());
    });
  }

  Future<void> _flushMetrics() async {
    try {
      while (mounted) {
        final metrics = _pendingMetrics;
        _pendingMetrics = null;
        if (metrics == null) {
          return;
        }
        final textureId = _textureId;
        if (textureId == null) {
          final generation = _generation;
          try {
            final created = await widget.player.createTextureSurface(
              width: metrics.width,
              height: metrics.height,
              scale: metrics.scale,
            );
            if (!mounted || generation != _generation) {
              await widget.player.releaseTextureSurface(created);
              return;
            }
            _textureId = created;
            _activeMetrics = metrics;
            widget.onPlatformViewIdChanged?.call(created);
            await widget.player.attachView(created);
            if (mounted) {
              setState(() {});
            }
          } catch (error) {
            debugPrint('ErikaOhosVideoView: texture creation failed: $error');
          }
        } else if (metrics != _activeMetrics) {
          try {
            await widget.player.resizeTextureSurface(
              textureId,
              width: metrics.width,
              height: metrics.height,
              scale: metrics.scale,
            );
            _activeMetrics = metrics;
          } catch (error) {
            debugPrint('ErikaOhosVideoView: texture resize failed: $error');
          }
        }
      }
    } finally {
      _updateInFlight = false;
      if (mounted && _pendingMetrics != null) {
        _queueMetrics(_pendingMetrics!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final scale = MediaQuery.devicePixelRatioOf(context);
        final logicalWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : constraints.minWidth;
        final logicalHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : constraints.minHeight;
        final metrics = _OhosSurfaceMetrics(
          (logicalWidth * scale).round().clamp(1, 16384),
          (logicalHeight * scale).round().clamp(1, 16384),
          scale,
        );
        _queueMetrics(metrics);
        final textureId = _textureId;
        if (textureId == null) {
          return const SizedBox.expand();
        }
        return Texture(textureId: textureId);
      },
    );
  }
}

class _ErikaAndroidVideoView extends StatefulWidget {
  const _ErikaAndroidVideoView({
    required this.player,
    this.debugLabel,
    this.onPlatformViewIdChanged,
  });

  final ErikaPlayer player;
  final String? debugLabel;
  final ValueChanged<int?>? onPlatformViewIdChanged;

  @override
  State<_ErikaAndroidVideoView> createState() => _ErikaAndroidVideoViewState();
}

class _ErikaAndroidVideoViewState extends State<_ErikaAndroidVideoView> {
  static const _attachRetryDelays = <Duration>[
    Duration(milliseconds: 16),
    Duration(milliseconds: 32),
    Duration(milliseconds: 64),
    Duration(milliseconds: 128),
    Duration(milliseconds: 256),
    Duration(milliseconds: 512),
    Duration(seconds: 1),
  ];

  int? _viewId;
  int _attachmentGeneration = 0;
  int _surfaceGeneration = 0;

  bool _usesExtendedLinearSurface(ErikaPlayer player) =>
      player.outputMode == ErikaOutputMode.extendedLinear;

  Object _surfaceConfigurationKey(ErikaPlayer player) {
    if (!_usesExtendedLinearSurface(player)) {
      return 'sdr';
    }
    final headroom = player.edrHeadroom;
    return headroom == null
        ? 'extended-linear:auto'
        : 'extended-linear:$headroom';
  }

  @override
  void didUpdateWidget(covariant _ErikaAndroidVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player == widget.player) {
      return;
    }
    final surfaceConfigurationChanged =
        _surfaceConfigurationKey(oldWidget.player) !=
            _surfaceConfigurationKey(widget.player);
    if (surfaceConfigurationChanged) {
      // Invalidate callbacks from a PlatformView whose asynchronous create
      // has not completed yet; in that state _viewId is still null.
      _surfaceGeneration += 1;
    }
    final viewId = _viewId;
    if (viewId != null) {
      final generation = ++_attachmentGeneration;
      if (!surfaceConfigurationChanged) {
        unawaited(
          _switchPlayer(
            oldPlayer: oldWidget.player,
            newPlayer: widget.player,
            viewId: viewId,
            generation: generation,
          ),
        );
      } else {
        unawaited(
          _detachIgnoringFailure(oldWidget.player, viewId, 'view rebuild'),
        );
        _viewId = null;
        widget.onPlatformViewIdChanged?.call(null);
      }
    }
  }

  @override
  void dispose() {
    _attachmentGeneration += 1;
    _surfaceGeneration += 1;
    final viewId = _viewId;
    widget.onPlatformViewIdChanged?.call(null);
    if (viewId != null) {
      unawaited(_detachIgnoringFailure(widget.player, viewId, 'dispose'));
    }
    super.dispose();
  }

  void _handlePlatformViewCreated(int viewId, int surfaceGeneration) {
    if (!mounted || surfaceGeneration != _surfaceGeneration) {
      return;
    }
    final generation = ++_attachmentGeneration;
    _viewId = viewId;
    widget.onPlatformViewIdChanged?.call(viewId);
    unawaited(_attachWithRetry(widget.player, viewId, generation));
  }

  bool _attachmentIsCurrent(ErikaPlayer player, int viewId, int generation) =>
      mounted &&
      generation == _attachmentGeneration &&
      identical(widget.player, player) &&
      _viewId == viewId;

  Future<void> _switchPlayer({
    required ErikaPlayer oldPlayer,
    required ErikaPlayer newPlayer,
    required int viewId,
    required int generation,
  }) async {
    await _detachIgnoringFailure(oldPlayer, viewId, 'player switch');
    if (!_attachmentIsCurrent(newPlayer, viewId, generation)) {
      return;
    }
    await _attachWithRetry(newPlayer, viewId, generation);
  }

  Future<void> _attachWithRetry(
    ErikaPlayer player,
    int viewId,
    int generation,
  ) async {
    Object? lastError;
    for (var attempt = 0;; attempt += 1) {
      if (!_attachmentIsCurrent(player, viewId, generation)) {
        return;
      }
      try {
        await player.attachView(viewId);
        return;
      } catch (error) {
        lastError = error;
      }
      if (attempt >= _attachRetryDelays.length) {
        debugPrint(
          'ErikaAndroidVideoView: attach failed after '
          '${attempt + 1} attempts for view $viewId: $lastError',
        );
        return;
      }
      await Future<void>.delayed(_attachRetryDelays[attempt]);
    }
  }

  Future<void> _detachIgnoringFailure(
    ErikaPlayer player,
    int viewId,
    String reason,
  ) async {
    try {
      await player.detachView(viewId);
    } catch (error) {
      debugPrint(
        'ErikaAndroidVideoView: detach failed during $reason for '
        'view $viewId; native recovery remains active: $error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final extendedLinear = _usesExtendedLinearSurface(widget.player);
    final surfaceGeneration = _surfaceGeneration;
    final creationParams = <String, Object?>{
      if (widget.debugLabel case final label?) 'debugLabel': label,
      'outputMode': extendedLinear
          ? ErikaOutputMode.extendedLinear.nativeValue
          : ErikaOutputMode.sdr.nativeValue,
      if (extendedLinear)
        'requestedHdrHeadroom': widget.player.edrHeadroom ?? 0.0,
      if (extendedLinear) 'composition': 'hybrid',
      if (widget.player.videoAlphaMode != ErikaVideoAlphaMode.opaque)
        'videoAlphaMode': widget.player.videoAlphaMode.nativeValue,
    };
    if (!extendedLinear) {
      return AndroidView(
        key: const ValueKey<String>('erika-android-sdr-texture-view'),
        viewType: 'erika_flutter/video_view',
        layoutDirection: TextDirection.ltr,
        creationParamsCodec: const StandardMessageCodec(),
        creationParams: creationParams,
        onPlatformViewCreated: (int viewId) =>
            _handlePlatformViewCreated(viewId, surfaceGeneration),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      );
    }

    return PlatformViewLink(
      key: ValueKey<Object>(_surfaceConfigurationKey(widget.player)),
      viewType: 'erika_flutter/hdr_video_view',
      surfaceFactory:
          (BuildContext context, PlatformViewController controller) =>
              AndroidViewSurface(
        controller: controller as AndroidViewController,
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      ),
      onCreatePlatformView: (PlatformViewCreationParams params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: 'erika_flutter/hdr_video_view',
          layoutDirection: TextDirection.ltr,
          creationParamsCodec: const StandardMessageCodec(),
          creationParams: creationParams,
          onFocus: () => params.onFocusChanged(true),
        );
        controller
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(
            (int viewId) =>
                _handlePlatformViewCreated(viewId, surfaceGeneration),
          )
          ..create();
        return controller;
      },
    );
  }
}

/// Window-hosted native video surface for macOS, iOS, and Windows.
///
/// The widget reserves a Flutter layout rect while the platform plugin hosts a
/// sibling native view and keeps its frame in sync.
class ErikaWindowOverlayVideoView extends StatefulWidget {
  const ErikaWindowOverlayVideoView({
    super.key,
    required this.player,
    this.debugLabel,
    this.onPlatformViewIdChanged,
    this.onFrameRectChanged,
    this.blendMode = BlendMode.srcOver,
    this.opacity = 1.0,
  }) : assert(opacity >= 0.0 && opacity <= 1.0);

  final ErikaPlayer player;
  final String? debugLabel;
  final ValueChanged<int?>? onPlatformViewIdChanged;
  final ValueChanged<Rect?>? onFrameRectChanged;
  final BlendMode blendMode;
  final double opacity;

  @override
  State<ErikaWindowOverlayVideoView> createState() =>
      _ErikaWindowOverlayVideoViewState();
}

class _ErikaWindowOverlayVideoViewState
    extends State<ErikaWindowOverlayVideoView> with WidgetsBindingObserver {
  Timer? _retryTimer;
  Timer? _frameTimer;
  int _bindAttempts = 0;
  bool _isBound = false;
  late final int _surfaceGeneration;
  String? _lastFrameSignature;

  @override
  void initState() {
    super.initState();
    if (_usesAndroidTextureView) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _surfaceGeneration = identityHashCode(this);
    widget.onPlatformViewIdChanged?.call(ErikaPlayer.windowOverlayViewId);
    _startFrameTimer();
    _scheduleAttach();
  }

  @override
  void didUpdateWidget(covariant ErikaWindowOverlayVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_usesAndroidTextureView) {
      return;
    }
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
    } else if (oldWidget.blendMode != widget.blendMode ||
        oldWidget.opacity != widget.opacity) {
      _scheduleFrameUpdate(force: true);
    }
  }

  @override
  void didChangeMetrics() {
    if (_usesAndroidTextureView) {
      return;
    }
    _scheduleFrameUpdate(force: true);
  }

  @override
  void dispose() {
    if (_usesAndroidTextureView) {
      widget.onFrameRectChanged?.call(null);
      super.dispose();
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _frameTimer?.cancel();
    widget.onPlatformViewIdChanged?.call(null);
    unawaited(_hideOverlayFrame());
    unawaited(
      widget.player.detachWindowOverlay(generation: _surfaceGeneration),
    );
    super.dispose();
  }

  void _startFrameTimer() {
    _frameTimer?.cancel();
    final interval = defaultTargetPlatform == TargetPlatform.windows
        ? const Duration(milliseconds: 16)
        : const Duration(milliseconds: 250);
    _frameTimer = Timer.periodic(interval, (_) => _scheduleFrameUpdate());
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
    if (!mounted || _isBound || !_supportsWindowOverlayVideoView) {
      return;
    }

    try {
      await widget.player.attachWindowOverlay(
        flutterViewId: View.of(context).viewId,
        blendMode: widget.blendMode.name,
        opacity: widget.opacity,
      );
      _isBound = true;
      _scheduleFrameUpdate(force: true);
    } catch (error) {
      debugPrint('ErikaWindowOverlayVideoView: bind failed: $error');
      _scheduleRetry();
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
    if (!_supportsWindowOverlayVideoView) {
      return;
    }

    final Rect rect;
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
      rect = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
    } else {
      rect = Rect.zero;
    }

    final signature = <Object>[
      visible,
      rect.left.toStringAsFixed(2),
      rect.top.toStringAsFixed(2),
      rect.width.toStringAsFixed(2),
      rect.height.toStringAsFixed(2),
      widget.blendMode.name,
      widget.opacity.toStringAsFixed(4),
    ].join('|');
    if (!force && signature == _lastFrameSignature) {
      return;
    }
    _lastFrameSignature = signature;
    widget.onFrameRectChanged?.call(visible ? rect : null);

    try {
      await widget.player.setWindowOverlayFrame(
        frame: rect,
        visible: visible,
        generation: _surfaceGeneration,
        flutterViewId: View.of(context).viewId,
        debugLabel: widget.debugLabel,
        blendMode: widget.blendMode.name,
        opacity: widget.opacity,
      );
    } catch (error) {
      debugPrint('ErikaWindowOverlayVideoView: frame update failed: $error');
    }
  }

  Future<void> _hideOverlayFrame() async {
    try {
      await widget.player.setWindowOverlayFrame(
        frame: Rect.zero,
        visible: false,
        generation: _surfaceGeneration,
        debugLabel: widget.debugLabel,
        blendMode: widget.blendMode.name,
        opacity: widget.opacity,
      );
    } catch (error) {
      debugPrint('ErikaWindowOverlayVideoView: hide overlay failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_usesAndroidTextureView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final renderObject = context.findRenderObject();
        if (renderObject is RenderBox && renderObject.hasSize) {
          final origin = renderObject.localToGlobal(Offset.zero);
          widget.onFrameRectChanged?.call(origin & renderObject.size);
        }
      });
      return _ErikaAndroidVideoView(
        player: widget.player,
        debugLabel: widget.debugLabel,
        onPlatformViewIdChanged: widget.onPlatformViewIdChanged,
      );
    }
    if (!_supportsWindowOverlayVideoView) {
      return const SizedBox.shrink();
    }
    _scheduleFrameUpdate();
    return const SizedBox.expand();
  }
}
