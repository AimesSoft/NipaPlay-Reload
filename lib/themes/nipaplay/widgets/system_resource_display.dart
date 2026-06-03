import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:nipaplay/utils/system_resource_monitor.dart';
import 'package:provider/provider.dart';

/// 系统资源显示组件
/// 单行高密度 HUD：无背景容器，仅文本描边。
class SystemResourceDisplay extends StatefulWidget {
  const SystemResourceDisplay({super.key});

  @override
  State<SystemResourceDisplay> createState() => _SystemResourceDisplayState();
}

class _SystemResourceDisplayState extends State<SystemResourceDisplay> {
  Timer? _refreshTimer;
  StreamSubscription<DanmakuRenderEngine>? _danmakuKernelSubscription;
  bool _registered = false;

  double _cpuUsage = 0.0;
  double _memoryUsageMB = 0.0;
  double _fps = 0.0;
  double? _gpuUsage;
  String _activeDecoder = '未知';
  String _playerKernelType = '未知';
  String _danmakuKernelType = '未知';

  bool get _isMacOSNativeVideoActive {
    if (kIsWeb || !Platform.isMacOS) {
      return false;
    }
    return Platform.environment['NIPAPLAY_ENABLE_MACOS_NATIVE_VIDEO'] == '1';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kIsWeb) return;
    final devOptions = Provider.of<DeveloperOptionsProvider>(context);
    _updateRegistration(devOptions.showSystemResources);
  }

  void _updateRegistration(bool shouldShow) {
    if (shouldShow && !_registered) {
      SystemResourceMonitor.registerConsumer();
      _registered = true;
      _startUpdating();
    } else if (!shouldShow && _registered) {
      SystemResourceMonitor.unregisterConsumer();
      _registered = false;
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _danmakuKernelSubscription?.cancel();
      _danmakuKernelSubscription = null;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _danmakuKernelSubscription?.cancel();
    if (_registered) {
      SystemResourceMonitor.unregisterConsumer();
      _registered = false;
    }
    super.dispose();
  }

  void _startUpdating() {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    void refreshMetrics() {
      if (!mounted) return;
      setState(() {
        _cpuUsage = SystemResourceMonitor().cpuUsage;
        _memoryUsageMB = SystemResourceMonitor().memoryUsageMB;
        _fps = SystemResourceMonitor().fps;
        _gpuUsage = SystemResourceMonitor().gpuUsage;
        _activeDecoder = SystemResourceMonitor().activeDecoder;
        _playerKernelType = SystemResourceMonitor().playerKernelType;
        _danmakuKernelType = SystemResourceMonitor().danmakuKernelType;
      });
    }

    _danmakuKernelSubscription?.cancel();
    _danmakuKernelSubscription =
        DanmakuKernelFactory.onKernelChanged.listen((_) {
      SystemResourceMonitor().updateDanmakuKernelType();
      refreshMetrics();
    });

    SystemResourceMonitor().updateDanmakuKernelType();
    refreshMetrics();
    if (_isMacOSNativeVideoActive) return;

    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      refreshMetrics();
    });
  }

  String _formatPercent(double? value) {
    if (value == null) return 'N/A';
    return '${value.toStringAsFixed(1)}%';
  }

  String _formatMemory(double value) {
    if (value <= 0) return 'N/A';
    return '${value.toStringAsFixed(0)}M';
  }

  TextStyle _outlinedTextStyle({
    required TextStyle baseStyle,
    required Color color,
    required double fontSize,
    FontWeight weight = FontWeight.w900,
    double strokeWidth = 2.4,
    double letterSpacing = 0,
  }) {
    return baseStyle.copyWith(
      fontSize: fontSize,
      height: 1.0,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      shadows: [
        Shadow(
            color: Colors.black.withValues(alpha: 0.95),
            offset: const Offset(-0.7, -0.7)),
        Shadow(
            color: Colors.black.withValues(alpha: 0.95),
            offset: const Offset(0.7, -0.7)),
        Shadow(
            color: Colors.black.withValues(alpha: 0.95),
            offset: const Offset(-0.7, 0.7)),
        Shadow(
            color: Colors.black.withValues(alpha: 0.95),
            offset: const Offset(0.7, 0.7)),
        Shadow(
            color: Colors.black.withValues(alpha: 0.82),
            blurRadius: strokeWidth),
      ],
    );
  }

  Color _shade(Color base, double amount) {
    return Color.lerp(base, Colors.black, amount)!;
  }

  Widget _segment({
    required String label,
    required String value,
    required Color labelColor,
    required Color valueColor,
    required TextStyle baseStyle,
    bool compact = false,
  }) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.fade,
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: _outlinedTextStyle(
              baseStyle: baseStyle,
              color: labelColor,
              fontSize: compact ? 12 : 13,
              weight: FontWeight.w800,
              strokeWidth: 1.9,
            ),
          ),
          TextSpan(
            text: value,
            style: _outlinedTextStyle(
              baseStyle: baseStyle,
              color: valueColor,
              fontSize: compact ? 13 : 14,
              weight: FontWeight.w900,
              strokeWidth: 2.6,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }

    return Consumer<DeveloperOptionsProvider>(
      builder: (context, devOptions, child) {
        if (!devOptions.showSystemResources) {
          return const SizedBox.shrink();
        }

        final cpuText = '${_cpuUsage.toStringAsFixed(1)}%';
        final memText = _formatMemory(_memoryUsageMB);
        final gpuText = _formatPercent(_gpuUsage);
        final fpsText = _fps <= 0 ? 'N/A' : _fps.toStringAsFixed(1);

        const cpuBase = Color(0xFF22B8E6);
        const memBase = Color(0xFFD89A1C);
        const gpuBase = Color(0xFF9A67FF);
        const fpsBase = Color(0xFF46D27A);
        const decBase = Color(0xFFFF9850);
        const playerBase = Color(0xFF5E9BFF);
        const danmakuBase = Color(0xFFFF6EBF);

        Color valueFromBase(Color base, double? load,
            {double warn = 60, double danger = 85}) {
          if (load == null) return const Color(0xFFB7BEC7);
          if (load >= danger) return const Color(0xFFFF6D7A);
          if (load >= warn) {
            return Color.lerp(base, const Color(0xFFFFC35A), 0.45)!;
          }
          return base;
        }

        final cpuColor = valueFromBase(cpuBase, _cpuUsage);
        final memColor = _memoryUsageMB > 0
            ? valueFromBase(memBase, (_memoryUsageMB / 1024) * 100,
                warn: 55, danger: 80)
            : const Color(0xFFB7BEC7);
        final gpuColor = valueFromBase(gpuBase, _gpuUsage);
        final fpsColor = _fps > 0
            ? (_fps >= 55
                ? fpsBase
                : (_fps >= 30
                    ? Color.lerp(fpsBase, const Color(0xFFFFC35A), 0.5)!
                    : const Color(0xFFFF6D7A)))
            : const Color(0xFFB7BEC7);

        final screenWidth = MediaQuery.sizeOf(context).width;
        final narrowScreen = screenWidth < 720;
        final showDetail = screenWidth >= 1160;
        final compact = screenWidth < 900;
        final themeTextStyle = Theme.of(context).textTheme.bodyMedium;
        final baseTextStyle = (themeTextStyle ?? const TextStyle()).copyWith(
          fontFamilyFallback: AppTheme.platformFontFamilyFallback,
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        );

        final items = <Widget>[
          _segment(
            label: 'CPU',
            value: cpuText,
            labelColor: cpuBase,
            valueColor: cpuColor,
            baseStyle: baseTextStyle,
            compact: compact,
          ),
          _segment(
            label: 'MEM',
            value: memText,
            labelColor: memBase,
            valueColor: memColor,
            baseStyle: baseTextStyle,
            compact: compact,
          ),
          _segment(
            label: 'GPU',
            value: gpuText,
            labelColor: gpuBase,
            valueColor: gpuColor,
            baseStyle: baseTextStyle,
            compact: compact,
          ),
          _segment(
            label: 'FPS',
            value: fpsText,
            labelColor: fpsBase,
            valueColor: fpsColor,
            baseStyle: baseTextStyle,
            compact: compact,
          ),
          if (showDetail)
            _segment(
              label: 'DEC',
              value: _activeDecoder,
              labelColor: _shade(decBase, 0.28),
              valueColor: _shade(decBase, 0.06),
              baseStyle: baseTextStyle,
              compact: true,
            ),
          if (showDetail)
            _segment(
              label: 'P',
              value: _playerKernelType,
              labelColor: _shade(playerBase, 0.28),
              valueColor: _shade(playerBase, 0.06),
              baseStyle: baseTextStyle,
              compact: true,
            ),
          if (showDetail)
            _segment(
              label: 'D',
              value: _danmakuKernelType,
              labelColor: _shade(danmakuBase, 0.28),
              valueColor: _shade(danmakuBase, 0.06),
              baseStyle: baseTextStyle,
              compact: true,
            ),
        ];

        if (narrowScreen) {
          return IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  items[i],
                  if (i != items.length - 1) const SizedBox(height: 2),
                ],
              ],
            ),
          );
        }

        return IgnorePointer(
          child: SizedBox(
            height: compact ? 18 : 20,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (i > 0) SizedBox(width: compact ? 8 : 10),
                    items[i],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
