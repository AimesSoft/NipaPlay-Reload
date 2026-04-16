import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/platform_utils.dart';

const int _windowHostedPlatformSurfaceId = -1;
const MethodChannel _macOSNativeVideoChannel =
    MethodChannel('nipaplay/macos_native_video');
final bool _macOSHdrExitTraceEnabled = !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.macOS &&
    Platform.environment['NIPAPLAY_MACOS_HDR_EXIT_TRACE'] == '1';

void _logMacOSHdrExitTrace(String message) {
  if (_macOSHdrExitTraceEnabled) {
    debugPrint('[HDRExit][OverlaySurface] $message');
  }
}

class MacOSNativeVideoView extends StatefulWidget {
  const MacOSNativeVideoView({
    super.key,
    required this.player,
    this.debugLabel,
    this.onPlatformViewIdChanged,
  });

  final Player player;
  final String? debugLabel;
  final ValueChanged<int?>? onPlatformViewIdChanged;

  @override
  State<MacOSNativeVideoView> createState() => _MacOSNativeVideoViewState();
}

class _MacOSNativeVideoViewState extends State<MacOSNativeVideoView>
    with WidgetsBindingObserver {
  Timer? _retryTimer;
  int _bindAttempts = 0;
  bool _isBound = false;
  int? _platformViewId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant MacOSNativeVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      _retryTimer?.cancel();
      _bindAttempts = 0;
      _isBound = false;
      unawaited(
        oldWidget.player.detachPlatformVideoSurface(
          platformViewId: _platformViewId,
        ),
      );
      unawaited(_bindPlatformVideoSurface());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    final platformViewId = _platformViewId;
    widget.onPlatformViewIdChanged?.call(null);
    unawaited(
      widget.player.detachPlatformVideoSurface(
        platformViewId: platformViewId,
      ),
    );
    super.dispose();
  }

  Future<void> _bindPlatformVideoSurface() async {
    final platformViewId = _platformViewId;
    if (!mounted ||
        !widget.player.prefersPlatformVideoSurface ||
        platformViewId == null) {
      return;
    }

    try {
      await widget.player.attachPlatformVideoSurface(
        platformViewId: platformViewId,
        viewHandle: 0,
      );
      _isBound = true;
    } catch (error) {
      debugPrint('MacOSNativeVideoView: bind failed: $error');
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_isBound || !mounted || _bindAttempts >= 20) {
      return;
    }
    _bindAttempts += 1;
    _retryTimer?.cancel();
    _retryTimer = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(_bindPlatformVideoSurface()),
    );
  }

  void _handlePlatformViewCreated(int id) {
    if (!mounted) {
      return;
    }
    if (_platformViewId == id) {
      return;
    }
    final previousViewId = _platformViewId;
    _platformViewId = id;
    widget.onPlatformViewIdChanged?.call(id);
    if (previousViewId != null && previousViewId != id) {
      unawaited(
        widget.player.detachPlatformVideoSurface(
          platformViewId: previousViewId,
        ),
      );
    }
    _retryTimer?.cancel();
    _bindAttempts = 0;
    _isBound = false;
    unawaited(_bindPlatformVideoSurface());
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.macOS ||
        !widget.player.prefersPlatformVideoSurface) {
      return const SizedBox.shrink();
    }

    return AppKitView(
      viewType: 'nipaplay/macos_native_video_view',
      layoutDirection: TextDirection.ltr,
      creationParamsCodec: const StandardMessageCodec(),
      creationParams: <String, dynamic>{
        if (widget.debugLabel != null) 'debugLabel': widget.debugLabel,
      },
      onPlatformViewCreated: _handlePlatformViewCreated,
    );
  }
}

class MacOSWindowNativeVideoOverlaySurface extends StatefulWidget {
  const MacOSWindowNativeVideoOverlaySurface({
    super.key,
    required this.player,
    this.debugLabel,
    this.onPlatformViewIdChanged,
    this.onFrameRectChanged,
  });

  final Player player;
  final String? debugLabel;
  final ValueChanged<int?>? onPlatformViewIdChanged;
  final ValueChanged<Rect?>? onFrameRectChanged;

  @override
  State<MacOSWindowNativeVideoOverlaySurface> createState() =>
      _MacOSWindowNativeVideoOverlaySurfaceState();
}

class _MacOSWindowNativeVideoOverlaySurfaceState
    extends State<MacOSWindowNativeVideoOverlaySurface>
    with WidgetsBindingObserver {
  Timer? _retryTimer;
  Timer? _frameTimer;
  int _bindAttempts = 0;
  bool _isBound = false;
  String? _lastFrameSignature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.onPlatformViewIdChanged?.call(_windowHostedPlatformSurfaceId);
    _startFrameTimer();
    _scheduleAttach();
  }

  @override
  void didUpdateWidget(
      covariant MacOSWindowNativeVideoOverlaySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      _retryTimer?.cancel();
      _bindAttempts = 0;
      _isBound = false;
      _lastFrameSignature = null;
      unawaited(
        oldWidget.player.detachPlatformVideoSurface(
          platformViewId: _windowHostedPlatformSurfaceId,
        ),
      );
      widget.onPlatformViewIdChanged?.call(_windowHostedPlatformSurfaceId);
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
    _logMacOSHdrExitTrace(
      'dispose state=${identityHashCode(this)} label=${widget.debugLabel}',
    );
    widget.onPlatformViewIdChanged?.call(null);
    unawaited(_hideOverlayFrame());
    unawaited(
      widget.player.detachPlatformVideoSurface(
        platformViewId: _windowHostedPlatformSurfaceId,
      ),
    );
    super.dispose();
  }

  void _startFrameTimer() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(
      const Duration(milliseconds: 250),
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
    if (!mounted ||
        _isBound ||
        !widget.player.prefersPlatformVideoSurface ||
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }

    try {
      _logMacOSHdrExitTrace(
        'attachOverlaySurface state=${identityHashCode(this)} label=${widget.debugLabel}',
      );
      await widget.player.attachPlatformVideoSurface(
        platformViewId: _windowHostedPlatformSurfaceId,
        viewHandle: 0,
      );
      _isBound = true;
      _scheduleFrameUpdate(force: true);
    } catch (error) {
      debugPrint('MacOSWindowNativeVideoOverlaySurface: bind failed: $error');
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_isBound || !mounted || _bindAttempts >= 20) {
      return;
    }
    _bindAttempts += 1;
    _retryTimer?.cancel();
    _retryTimer = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(_attachOverlaySurface()),
    );
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
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.macOS ||
        !Platform.isMacOS) {
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
      final origin = box.localToGlobal(Offset.zero);
      rect = origin & box.size;
    } else {
      rect = Rect.zero;
    }

    final signature = [
      visible,
      rect.left.toStringAsFixed(2),
      rect.top.toStringAsFixed(2),
      rect.width.toStringAsFixed(2),
      rect.height.toStringAsFixed(2),
    ].join('|');
    if (!force && signature == _lastFrameSignature) {
      return;
    }
    _lastFrameSignature = signature;
    widget.onFrameRectChanged?.call(visible ? rect : null);
    if (!visible || force) {
      _logMacOSHdrExitTrace(
        'setOverlayFrame state=${identityHashCode(this)} visible=$visible force=$force rect=$rect label=${widget.debugLabel}',
      );
    }

    try {
      await _macOSNativeVideoChannel.invokeMethod<void>(
        'setOverlayFrame',
        <String, dynamic>{
          'viewId': _windowHostedPlatformSurfaceId,
          'x': rect.left,
          'y': rect.top,
          'width': rect.width,
          'height': rect.height,
          'visible': visible,
          if (widget.debugLabel != null) 'debugLabel': widget.debugLabel,
        },
      );
    } catch (error) {
      debugPrint(
        'MacOSWindowNativeVideoOverlaySurface: frame update failed: $error',
      );
    }
  }

  Future<void> _hideOverlayFrame() async {
    _logMacOSHdrExitTrace(
      'hideOverlayFrame state=${identityHashCode(this)} label=${widget.debugLabel}',
    );
    try {
      await _macOSNativeVideoChannel.invokeMethod<void>(
        'setOverlayFrame',
        <String, dynamic>{
          'viewId': _windowHostedPlatformSurfaceId,
          'x': 0.0,
          'y': 0.0,
          'width': 0.0,
          'height': 0.0,
          'visible': false,
          if (widget.debugLabel != null) 'debugLabel': widget.debugLabel,
        },
      );
    } catch (error) {
      debugPrint(
        'MacOSWindowNativeVideoOverlaySurface: hide overlay failed: $error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.macOS ||
        !widget.player.prefersPlatformVideoSurface) {
      return const SizedBox.shrink();
    }

    _scheduleFrameUpdate();
    return const SizedBox.expand();
  }
}
