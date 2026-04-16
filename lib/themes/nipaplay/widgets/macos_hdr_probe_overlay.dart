import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';

class MacOSHdrProbeOverlay extends StatefulWidget {
  const MacOSHdrProbeOverlay({
    super.key,
    required this.player,
    required this.platformViewId,
  });

  final Player player;
  final int platformViewId;

  @override
  State<MacOSHdrProbeOverlay> createState() => _MacOSHdrProbeOverlayState();
}

class _MacOSHdrProbeOverlayState extends State<MacOSHdrProbeOverlay> {
  static const MethodChannel _channel = MethodChannel(
    'nipaplay/macos_native_video',
  );
  static const Duration _refreshInterval = Duration(milliseconds: 1200);

  Timer? _refreshTimer;
  bool _isRefreshing = false;
  String? _error;
  Map<String, dynamic> _nativeDiagnostics = const <String, dynamic>{};
  Map<String, dynamic> _mpvProperties = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _refreshNativeDiagnostics();
    unawaited(_loadMpvSnapshot());
    _refreshTimer = Timer.periodic(
      _refreshInterval,
      (_) => _refreshNativeDiagnostics(),
    );
  }

  @override
  void didUpdateWidget(covariant MacOSHdrProbeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.platformViewId != widget.platformViewId ||
        oldWidget.player != widget.player) {
      _refreshNativeDiagnostics();
      unawaited(_loadMpvSnapshot());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshNativeDiagnostics() async {
    if (!mounted ||
        _isRefreshing ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }

    _isRefreshing = true;
    try {
      final native = Map<String, dynamic>.from(
        (await _channel.invokeMapMethod<String, dynamic>(
              'getViewDiagnostics',
              <String, dynamic>{'viewId': widget.platformViewId},
            ) ??
            const <dynamic, dynamic>{}),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _error = null;
        _nativeDiagnostics = native;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _loadMpvSnapshot() async {
    if (!mounted) {
      return;
    }

    try {
      final detailed = await widget.player.getDetailedMediaInfoAsync();
      final mpvProperties = Map<String, dynamic>.from(
        (detailed['mpvProperties'] as Map<dynamic, dynamic>? ??
            const <dynamic, dynamic>{}),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _mpvProperties = mpvProperties;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = _mapAt(_nativeDiagnostics, 'screen');
    final window = _mapAt(_nativeDiagnostics, 'window');
    final videoLayer = _mapAt(_nativeDiagnostics, 'videoLayer');

    final lines = <String>[
      'HDR Probe',
      if (_error != null) 'error: $_error',
      'screen EDR: ${_formatNumber(_readNumber(screen, 'maximumExtendedDynamicRangeColorComponentValue'))}'
          ' / ${_formatNumber(_readNumber(screen, 'maximumPotentialExtendedDynamicRangeColorComponentValue'))}'
          ' / ref ${_formatNumber(_readNumber(screen, 'maximumReferenceExtendedDynamicRangeColorComponentValue'))}',
      'screen: ${_readString(screen, 'localizedName')}'
          ' · scale ${_formatNumber(_readNumber(window, 'backingScaleFactor'))}',
      'layer: ${_readString(videoLayer, 'className')}'
          ' · wantsEDR ${_readBool(videoLayer, 'wantsExtendedDynamicRangeContent')}'
          ' · opaque ${_readBool(videoLayer, 'isOpaque')}',
      'layer CS: ${_shorten(_readString(videoLayer, 'colorspace'))}',
      'layer px: ${_readString(videoLayer, 'pixelFormat') ?? _readString(videoLayer, 'contentsFormat')}'
          ' · ${_formatSize(_mapAt(videoLayer, 'drawableSize').isNotEmpty ? _mapAt(videoLayer, 'drawableSize') : _mapAt(videoLayer, 'bounds'))}',
      if (_readString(videoLayer, 'edrMetadata') case final metadata?)
        'layer meta: ${_shorten(metadata, maxLength: 96)}',
      'mpv: vo=${_readMpv('current-vo')}'
          ' · hwdec=${_readMpv('hwdec-current')}'
          ' · gpu=${_readMpv('gpu-api')}/${_readMpv('gpu-context')}',
      'src: ${_readMpv('video-codec')}'
          ' · ${_readMpv('video-params/colorprimaries')}'
          ' / ${_readMpv('video-params/transfer')}'
          ' · ${_readMpv('video-format')}',
      'out: ${_readMpv('video-out-params/colorprimaries')}'
          ' / ${_readMpv('video-out-params/transfer')}'
          ' · ${_readMpv('video-out-params/pixelformat')}',
      'target: prim=${_readMpv('target-prim')}'
          ' · trc=${_readMpv('target-trc')}'
          ' · peak=${_readMpv('target-peak')}',
      'tone: ${_readMpv('tone-mapping')}'
          ' · hint=${_readMpv('target-colorspace-hint')}'
          ' · mode=${_readMpv('target-colorspace-hint-mode')}',
    ];

    return IgnorePointer(
      ignoring: true,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Container(
            width: 360,
            margin: const EdgeInsets.only(top: 18, right: 18),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                height: 1.35,
                fontFamily: 'Menlo',
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _mapAt(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  double? _readNumber(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  String? _readString(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value == null) {
      return null;
    }
    return value.toString();
  }

  String _readBool(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is bool) {
      return value ? 'yes' : 'no';
    }
    if (value is num) {
      return value != 0 ? 'yes' : 'no';
    }
    return '--';
  }

  String _readMpv(String key) {
    final value = _mpvProperties[key];
    if (value == null || value.toString().trim().isEmpty) {
      return '--';
    }
    return value.toString();
  }

  String _formatNumber(double? value) {
    if (value == null) {
      return '--';
    }
    return value.toStringAsFixed(2);
  }

  String _formatSize(Map<String, dynamic> size) {
    final width = _readNumber(size, 'width');
    final height = _readNumber(size, 'height');
    if (width == null || height == null) {
      return '--';
    }
    return '${width.toStringAsFixed(0)}x${height.toStringAsFixed(0)}';
  }

  String _shorten(String? value, {int maxLength = 72}) {
    if (value == null || value.isEmpty) {
      return '--';
    }
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength - 1)}…';
  }
}
