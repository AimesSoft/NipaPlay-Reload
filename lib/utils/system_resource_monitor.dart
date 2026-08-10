import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/utils/mock_mdk.dart'
    if (dart.library.io) 'package:fvp/mdk.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/src/rust/api/performance.dart' as rust_perf;
import 'package:nipaplay/src/rust/rust_init.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// 系统资源监控类
/// 提供真实的 CPU / 内存 / GPU / FPS 指标。
class SystemResourceMonitor {
  static const MethodChannel _performanceChannel =
      MethodChannel('nipaplay/performance');

  static final SystemResourceMonitor _instance =
      SystemResourceMonitor._internal();

  factory SystemResourceMonitor() => _instance;

  SystemResourceMonitor._internal();

  double _cpuUsage = 0.0;
  double _memoryUsageMB = 0.0;
  double _fps = 0.0;
  double? _gpuUsage;
  String _thermalState = 'N/A';
  double? _dfmLayoutMs;
  double? _dfmSubmitMs;

  String _activeDecoder = '未知';
  String _mdkVersion = '未知';
  String _playerKernelType = '未知';
  String _danmakuKernelType = '未知';

  Timer? _resourceTimer;
  Timer? _fpsTimer;
  bool _started = false;
  int _consumerCount = 0;
  int _monitoringGeneration = 0;

  int _frameCount = 0;
  final Stopwatch _fpsClock = Stopwatch();
  int _lastFpsSampleUs = 0;
  TimingsCallback? _timingsCallback;

  bool _rustPerformanceAvailable = false;
  int _lastCpuTimestampMs = 0;
  int _lastCpuMicros = 0;

  int _lastGpuSampleMillis = 0;
  static const int _gpuSampleIntervalMs = 1500;
  bool _gpuSamplingSupported = true;
  String? _lastGpuSamplingError;
  bool _thermalSamplingSupported = true;

  double get cpuUsage => _cpuUsage;
  double get memoryUsageMB => _memoryUsageMB;
  double get fps => _fps;
  double? get gpuUsage => _gpuUsage;
  String get thermalState => _thermalState;
  double? get dfmLayoutMs => _dfmLayoutMs;
  double? get dfmSubmitMs => _dfmSubmitMs;

  String get activeDecoder => _activeDecoder;
  String get mdkVersion => _mdkVersion;
  String get playerKernelType => _playerKernelType;
  String get danmakuKernelType => _danmakuKernelType;

  static Future<void> initialize() async {
    if (!kIsWeb && !globals.isTelevision) {
      _instance._initMdkVersion();
      _instance._updatePlayerKernelType();
      _instance._updateDanmakuKernelType();
      await _instance._initRustProbe();
    } else if (kIsWeb) {
      _instance._playerKernelType = 'Video Player';
      _instance._danmakuKernelType = 'CPU';
      _instance._mdkVersion = 'N/A';
      _instance._activeDecoder = '浏览器解码';
      _instance._gpuUsage = null;
    } else {
      // Television devices are locked to Erika by PlayerFactory. Keep the
      // diagnostics panel in sync with the actual factory policy.
      _instance._updatePlayerKernelType();
      _instance._danmakuKernelType = 'DFM+';
      _instance._mdkVersion = 'N/A';
      _instance._activeDecoder = 'Erika（等待媒体）';
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
        case PlayerKernelType.erika:
          _playerKernelType = 'Erika';
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
    _started = true;
    final generation = ++_monitoringGeneration;

    if (!_rustPerformanceAvailable && !kIsWeb) {
      await _initRustProbe();
    }

    // The HUD may have been hidden while the asynchronous Rust probe was
    // starting. Do not install timers/callbacks for a stale monitoring run.
    if (!_started ||
        generation != _monitoringGeneration ||
        _consumerCount == 0) {
      return;
    }

    _initFpsMeasurement();
    _startResourceMonitoring();
  }

  void _initFpsMeasurement() {
    _removeFpsTimingsCallback();
    _frameCount = 0;
    _fps = 0.0;
    _fpsClock
      ..reset()
      ..start();
    _lastFpsSampleUs = 0;

    // Count frames that actually completed the Flutter rendering pipeline.
    // A dedicated Ticker would continuously request frames itself, inflating
    // the reported FPS and adding load to the workload being measured.
    _timingsCallback = (List<FrameTiming> timings) {
      _frameCount += timings.length;
    };
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);

    _fpsTimer?.cancel();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final nowUs = _fpsClock.elapsedMicroseconds;
      final elapsedUs = nowUs - _lastFpsSampleUs;

      if (elapsedUs > 0) {
        _fps = _frameCount * 1000000 / elapsedUs;
        _frameCount = 0;
        _lastFpsSampleUs = nowUs;
      }
    });
  }

  void _removeFpsTimingsCallback() {
    final callback = _timingsCallback;
    if (callback != null) {
      SchedulerBinding.instance.removeTimingsCallback(callback);
      _timingsCallback = null;
    }
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

    await _updateThermalState();

    if (!_rustPerformanceAvailable) {
      _cpuUsage = 0.0;
      _memoryUsageMB = 0.0;
      _gpuUsage = null;
      return;
    }

    await _updateFromRustSamples();
  }

  Future<void> _updateThermalState() async {
    final supportsThermalState = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        !globals.isTvOS;
    if (!supportsThermalState || !_thermalSamplingSupported) {
      _thermalState = 'N/A';
      return;
    }

    try {
      _thermalState =
          await _performanceChannel.invokeMethod<String>('getThermalState') ??
              'unknown';
    } on MissingPluginException {
      _thermalSamplingSupported = false;
      _thermalState = 'N/A';
    } on PlatformException catch (e) {
      debugPrint('读取 iOS thermalState 失败: $e');
      _thermalState = 'N/A';
    }
  }

  void recordDfmFrameTimings({
    required double layoutMs,
    required double submitMs,
  }) {
    const alpha = 0.15;
    _dfmLayoutMs = _smoothedMetric(_dfmLayoutMs, layoutMs, alpha);
    _dfmSubmitMs = _smoothedMetric(_dfmSubmitMs, submitMs, alpha);
  }

  double _smoothedMetric(double? previous, double sample, double alpha) {
    if (!sample.isFinite || sample < 0) return previous ?? 0.0;
    if (previous == null) return sample;
    return previous + (sample - previous) * alpha;
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
            _cpuUsage = (cpuDeltaMicros / normalizedDenominatorMicros * 100)
                .clamp(0.0, 100.0);
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

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!_gpuSamplingSupported) {
      _gpuUsage = null;
      return;
    }

    if (_gpuUsage != null &&
        nowMs - _lastGpuSampleMillis < _gpuSampleIntervalMs) {
      return;
    }

    try {
      final gpuSample = await rust_perf.sampleGpuPercent();
      _gpuUsage = gpuSample.gpuPercent.clamp(0.0, 100.0);
      _lastGpuSampleMillis = nowMs;
      _lastGpuSamplingError = null;
    } catch (e) {
      final error = e.toString();
      if (_isUnsupportedGpuSamplingError(error)) {
        _gpuSamplingSupported = false;
        _gpuUsage = null;
        return;
      }
      if (_lastGpuSamplingError != error) {
        debugPrint('读取 GPU 采样失败: $error');
        _lastGpuSamplingError = error;
      }
      _gpuUsage = null;
    }
  }

  bool _isUnsupportedGpuSamplingError(String error) {
    return error.contains('gpu_sampling_not_implemented') ||
        error.contains('unsupported_platform');
  }

  void _stopMonitoring() {
    if (!_started) return;
    _started = false;
    _monitoringGeneration++;

    _resourceTimer?.cancel();
    _resourceTimer = null;

    _fpsTimer?.cancel();
    _fpsTimer = null;

    _removeFpsTimingsCallback();
    _fpsClock.stop();
    _frameCount = 0;
    _lastFpsSampleUs = 0;
    _fps = 0.0;

    _lastCpuTimestampMs = 0;
    _lastCpuMicros = 0;
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
          _danmakuKernelType = DanmakuKernelFactory.nipaplayNextDisplayName;
          break;
        case DanmakuRenderEngine.next2:
          _danmakuKernelType = 'NipaPlay Next2';
          break;
        case DanmakuRenderEngine.dfmPlus:
          _danmakuKernelType = 'DFM+';
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
