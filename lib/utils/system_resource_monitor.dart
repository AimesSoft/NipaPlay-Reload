import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:fvp/mdk.dart'
    if (dart.library.html) 'package:nipaplay/utils/mock_mdk.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/src/rust/api/performance.dart' as rust_perf;
import 'package:nipaplay/src/rust/rust_init.dart';

/// 系统资源监控类
/// 提供真实的 CPU / 内存 / GPU / FPS 指标。
class SystemResourceMonitor {
  static final SystemResourceMonitor _instance =
      SystemResourceMonitor._internal();

  factory SystemResourceMonitor() => _instance;

  SystemResourceMonitor._internal();

  double _cpuUsage = 0.0;
  double _memoryUsageMB = 0.0;
  double _fps = 0.0;
  double? _gpuUsage;

  String _activeDecoder = '未知';
  String _mdkVersion = '未知';
  String _playerKernelType = '未知';
  String _danmakuKernelType = '未知';

  Timer? _resourceTimer;
  Timer? _fpsTimer;
  bool _started = false;
  int _consumerCount = 0;

  int _frameCount = 0;
  late DateTime _lastFpsUpdateTime;
  Ticker? _ticker;

  bool _rustPerformanceAvailable = false;
  int _lastCpuTimestampMs = 0;
  int _lastCpuMicros = 0;

  int _lastGpuSampleMillis = 0;
  static const int _gpuSampleIntervalMs = 1500;

  double get cpuUsage => _cpuUsage;
  double get memoryUsageMB => _memoryUsageMB;
  double get fps => _fps;
  double? get gpuUsage => _gpuUsage;

  String get activeDecoder => _activeDecoder;
  String get mdkVersion => _mdkVersion;
  String get playerKernelType => _playerKernelType;
  String get danmakuKernelType => _danmakuKernelType;

  static Future<void> initialize() async {
    if (!kIsWeb) {
      _instance._initMdkVersion();
      _instance._updatePlayerKernelType();
      _instance._updateDanmakuKernelType();
      await _instance._initRustProbe();
    } else {
      _instance._playerKernelType = 'Video Player';
      _instance._danmakuKernelType = 'CPU';
      _instance._mdkVersion = 'N/A';
      _instance._activeDecoder = '浏览器解码';
      _instance._gpuUsage = null;
    }
  }

  Future<void> _initRustProbe() async {
    try {
      await ensureRustInitialized();
      _rustPerformanceAvailable = rust_perf.isPerformanceProbeAvailable();
    } catch (e) {
      debugPrint('初始化 Rust 性能探针失败: $e');
      _rustPerformanceAvailable = false;
    }
  }

  void _initMdkVersion() {
    try {
      final versionInt = version();
      final major = versionInt ~/ 10000;
      final minor = (versionInt % 10000) ~/ 100;
      final patch = versionInt % 100;
      _mdkVersion = '$major.$minor.$patch';
    } catch (e) {
      debugPrint('获取MDK版本号出错: $e');
      _mdkVersion = '未知';
    }
  }

  void _updatePlayerKernelType() {
    try {
      final kernelType = PlayerFactory.getKernelType();
      switch (kernelType) {
        case PlayerKernelType.mdk:
          _playerKernelType = 'MDK';
          break;
        case PlayerKernelType.videoPlayer:
          _playerKernelType = 'Video Player';
          break;
        case PlayerKernelType.mediaKit:
          _playerKernelType = 'Libmpv';
          break;
      }
    } catch (e) {
      debugPrint('获取播放器内核类型出错: $e');
      _playerKernelType = '未知';
    }
  }

  void setPlayerKernelType(String kernelType) {
    _playerKernelType = kernelType;
  }

  static void dispose() {
    _instance._stopMonitoring();
  }

  static void registerConsumer() {
    _instance._registerConsumer();
  }

  static void unregisterConsumer() {
    _instance._unregisterConsumer();
  }

  void _registerConsumer() {
    _consumerCount++;
    if (!_started) {
      _startMonitoring();
    }
  }

  void _unregisterConsumer() {
    if (_consumerCount > 0) {
      _consumerCount--;
    }
    if (_consumerCount == 0) {
      _stopMonitoring();
    }
  }

  Future<void> _startMonitoring() async {
    if (_started) return;

    if (!_rustPerformanceAvailable && !kIsWeb) {
      await _initRustProbe();
    }

    _initFpsMeasurement();
    _startResourceMonitoring();
    _started = true;
  }

  void _initFpsMeasurement() {
    _lastFpsUpdateTime = DateTime.now();
    _frameCount = 0;

    _ticker?.dispose();
    _ticker = Ticker((Duration elapsed) {
      _frameCount++;
    });
    _ticker?.start();

    _fpsTimer?.cancel();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastFpsUpdateTime).inMilliseconds;

      if (elapsed > 0) {
        _fps = _frameCount * 1000 / elapsed;
        _frameCount = 0;
        _lastFpsUpdateTime = now;
      }
    });
  }

  void _startResourceMonitoring() {
    _resourceTimer?.cancel();
    _resourceTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _updateRealResourceUsage();
    });
  }

  Future<void> _updateRealResourceUsage() async {
    if (kIsWeb) {
      _cpuUsage = 0.0;
      _memoryUsageMB = 0.0;
      _gpuUsage = null;
      return;
    }

    if (!_rustPerformanceAvailable) {
      _cpuUsage = 0.0;
      _memoryUsageMB = 0.0;
      _gpuUsage = null;
      return;
    }

    await _updateFromRustSamples();
  }

  Future<void> _updateFromRustSamples() async {
    try {
      final cpuSample = await rust_perf.sampleCpuCounters();
      final timestampMs = cpuSample.timestampMs.toInt();
      final cpuMicros = cpuSample.processCpuMicros.toInt();
      final logicalCpus = cpuSample.logicalCpus > 0 ? cpuSample.logicalCpus : 1;

      if (_lastCpuTimestampMs > 0 && _lastCpuMicros > 0) {
        final wallDeltaMs = timestampMs - _lastCpuTimestampMs;
        final cpuDeltaMicros = cpuMicros - _lastCpuMicros;

        if (wallDeltaMs > 0 && cpuDeltaMicros >= 0) {
          final normalizedDenominatorMicros = wallDeltaMs * 1000 * logicalCpus;
          if (normalizedDenominatorMicros > 0) {
            _cpuUsage =
                (cpuDeltaMicros / normalizedDenominatorMicros * 100).clamp(0.0, 100.0);
          }
        }
      }

      _lastCpuTimestampMs = timestampMs;
      _lastCpuMicros = cpuMicros;
    } catch (e) {
      debugPrint('读取 CPU 采样失败: $e');
    }

    try {
      final memory = await rust_perf.sampleMemoryRssMb();
      _memoryUsageMB = memory.toDouble();
    } catch (e) {
      debugPrint('读取内存采样失败: $e');
    }

    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_gpuUsage != null && nowMs - _lastGpuSampleMillis < _gpuSampleIntervalMs) {
        return;
      }

      final gpuSample = await rust_perf.sampleGpuPercent();
      _gpuUsage = gpuSample.gpuPercent.clamp(0.0, 100.0);
      _lastGpuSampleMillis = nowMs;
    } catch (_) {
      _gpuUsage = null;
    }
  }

  void _stopMonitoring() {
    if (!_started) return;

    _resourceTimer?.cancel();
    _resourceTimer = null;

    _fpsTimer?.cancel();
    _fpsTimer = null;

    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;

    _lastCpuTimestampMs = 0;
    _lastCpuMicros = 0;

    _started = false;
  }

  void setActiveDecoder(String decoder) {
    _activeDecoder = decoder;
  }

  void _updateDanmakuKernelType() {
    try {
      final kernelType = DanmakuKernelFactory.getKernelType();
      switch (kernelType) {
        case DanmakuRenderEngine.cpu:
          _danmakuKernelType = 'CPU';
          break;
        case DanmakuRenderEngine.gpu:
          _danmakuKernelType = 'GPU';
          break;
        case DanmakuRenderEngine.canvas:
          _danmakuKernelType = 'Canvas';
          break;
        case DanmakuRenderEngine.nipaplayNext:
          _danmakuKernelType = 'NipaPlay Next';
          break;
      }
    } catch (e) {
      debugPrint('获取弹幕内核类型出错: $e');
      _danmakuKernelType = '未知';
    }
  }

  void updatePlayerKernelType() {
    _updatePlayerKernelType();
  }

  void updateDanmakuKernelType() {
    _updateDanmakuKernelType();
  }
}
