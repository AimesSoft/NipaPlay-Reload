import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';

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

class _MacOSNativeVideoViewState extends State<MacOSNativeVideoView> {
  static const _channel = MethodChannel('nipaplay/macos_native_video');

  Timer? _retryTimer;
  int? _platformViewId;
  int _bindAttempts = 0;
  bool _isBound = false;

  @override
  void dispose() {
    _retryTimer?.cancel();
    unawaited(widget.player.detachPlatformVideoSurface());
    super.dispose();
  }

  void _handlePlatformViewCreated(int viewId) {
    _platformViewId = viewId;
    widget.onPlatformViewIdChanged?.call(viewId);
    unawaited(_bindPlatformVideoSurface());
  }

  Future<void> _bindPlatformVideoSurface() async {
    final viewId = _platformViewId;
    if (!mounted ||
        viewId == null ||
        !widget.player.prefersPlatformVideoSurface) {
      return;
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getViewHandles',
        <String, dynamic>{'viewId': viewId},
      );
      if (!mounted || result == null) {
        return;
      }

      final viewHandle = _readHandle(result['viewHandle']);
      final windowHandle = _readHandle(result['windowHandle']);
      if (viewHandle <= 0 && windowHandle <= 0) {
        _scheduleRetry();
        return;
      }

      await widget.player.attachPlatformVideoSurface(
        viewHandle: viewHandle,
        windowHandle: windowHandle > 0 ? windowHandle : null,
      );
      _isBound = true;
    } catch (error) {
      debugPrint('MacOSNativeVideoView: bind failed: $error');
      _scheduleRetry();
    }
  }

  int _readHandle(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
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

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.macOS ||
        !widget.player.prefersPlatformVideoSurface) {
      return const SizedBox.shrink();
    }

    return AppKitView(
      viewType: 'nipaplay/macos_native_video_view',
      onPlatformViewCreated: _handlePlatformViewCreated,
      creationParams: <String, dynamic>{
        if (widget.debugLabel != null) 'debugLabel': widget.debugLabel,
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
