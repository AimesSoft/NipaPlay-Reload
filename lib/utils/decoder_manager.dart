import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:fvp/mdk.dart'; // Commented out old import
import '../../player_abstraction/player_abstraction.dart'; // <-- NEW IMPORT
import 'system_resource_monitor.dart'; // 导入系统资源监视器

const Map<String, List<String>> _supportedDecodersByPlatform = {
  'macos': ["VT", "hap", "dav1d", "FFmpeg"],
  'ios': ["VT", "hap", "dav1d", "FFmpeg"],
  'windows': [
    "MFT:d3d=11",
    "MFT:d3d=12",
    "D3D11",
    "D3D12",
    "DXVA",
    "CUDA",
    "QSV",
    "NVDEC",
    "hap",
    "dav1d",
    "FFmpeg",
  ],
  'linux': [
    "VAAPI",
    "VDPAU",
    "CUDA",
    "NVDEC",
    "rkmpp",
    "V4L2M2M",
    "hap",
    "dav1d",
    "FFmpeg",
  ],
  'android': ["AMediaCodec", "MediaCodec", "dav1d", "FFmpeg"],
  'ohos': ["OH", "FFmpeg", "dav1d"],
};

@visibleForTesting
List<String> platformDefaultDecodersForOperatingSystem(
  String operatingSystem,
) {
  return List<String>.from(
    _supportedDecodersByPlatform[operatingSystem] ?? const ["FFmpeg"],
  );
}

bool _isSoftwareDecoderName(String decoder) {
  final lower = decoder.toLowerCase();
  return lower.contains('ffmpeg') || lower.contains('dav1d');
}

@visibleForTesting
List<String> applyDecoderPreferenceForOperatingSystem({
  required String operatingSystem,
  required List<String> decoders,
  required bool preferHardware,
}) {
  if (decoders.isEmpty) return decoders;

  final candidates = List<String>.from(decoders);
  if (operatingSystem == 'ohos' &&
      !candidates.any((decoder) => decoder.toUpperCase() == 'OH')) {
    // Older HarmonyOS builds persisted ["FFmpeg"] because OH was missing from
    // NipaPlay's platform list. Keep the saved fallbacks, but restore the
    // native MDK decoder candidate so the hardware toggle can take effect.
    candidates.add('OH');
  }

  final software = <String>[];
  final hardware = <String>[];
  for (final decoder in candidates) {
    if (_isSoftwareDecoderName(decoder)) {
      software.add(decoder);
    } else {
      hardware.add(decoder);
    }
  }
  return preferHardware
      ? <String>[...hardware, ...software]
      : <String>[...software, ...hardware];
}

/// 解码器管理类，负责视频解码器的配置和管理
class DecoderManager {
  Player player; // Type remains Player, but now it's our abstracted Player
  static const String _useHardwareDecoderKey = 'use_hardware_decoder';
  static const String _selectedDecodersKey = 'selected_decoders';

  // 当前活跃解码器信息
  String? _currentDecoder;

  DecoderManager({required this.player}) {
    initialize();
  }

  // 更新播放器实例
  void updatePlayer(Player newPlayer) {
    player = newPlayer;
    debugPrint('DecoderManager: 播放器实例已更新');
    // 重新应用解码器设置
    initialize();
  }

  /// 初始化解码器设置
  Future<void> initialize() async {
    if (kIsWeb) return;
    // 设置硬件解码器
    final prefs = await SharedPreferences.getInstance();
    final useHardwareDecoder = prefs.getBool(_useHardwareDecoderKey) ?? true;

    final savedDecoders = prefs.getStringList(_selectedDecodersKey);
    List<String> decoders = [];
    if (savedDecoders != null && savedDecoders.isNotEmpty) {
      decoders = List<String>.from(savedDecoders);
    } else {
      decoders = _getPlatformDefaultDecoders();
      debugPrint('使用平台默认解码器设置: $decoders');
    }

    final adjustedDecoders =
        _applyHardwarePreference(decoders, useHardwareDecoder);

    if (adjustedDecoders.isNotEmpty) {
      player.setDecoders(MediaType.video, adjustedDecoders); // Use our MediaType
      _updateActiveDecoderInfo(adjustedDecoders);

      if (savedDecoders == null ||
          savedDecoders.isEmpty ||
          !listEquals(savedDecoders, adjustedDecoders)) {
        await prefs.setStringList(_selectedDecodersKey, adjustedDecoders);
      }
    }

    // 输出解码器相关属性
    _setGlobalDecodingProperties(); // Ensure global properties are set
  }

  /// 配置所有支持的解码器，按平台组织
  Map<String, List<String>> getAllSupportedDecoders() {
    if (kIsWeb) return {};
    return {
      for (final entry in _supportedDecodersByPlatform.entries)
        entry.key: List<String>.from(entry.value),
    };
  }

  List<String> _getPlatformDefaultDecoders() {
    if (kIsWeb) return [];
    return platformDefaultDecodersForOperatingSystem(Platform.operatingSystem);
  }

  bool _isSoftwareDecoder(String decoder) {
    return _isSoftwareDecoderName(decoder);
  }

  List<String> _applyHardwarePreference(
      List<String> decoders, bool preferHardware) {
    return applyDecoderPreferenceForOperatingSystem(
      operatingSystem: Platform.operatingSystem,
      decoders: decoders,
      preferHardware: preferHardware,
    );
  }

  Future<void> applyHardwareDecodingPreference(bool enabled) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final savedDecoders = prefs.getStringList(_selectedDecodersKey);
    final baseDecoders = (savedDecoders != null && savedDecoders.isNotEmpty)
        ? List<String>.from(savedDecoders)
        : _getPlatformDefaultDecoders();
    final adjustedDecoders = _applyHardwarePreference(baseDecoders, enabled);

    if (adjustedDecoders.isEmpty) return;
    player.setDecoders(MediaType.video, adjustedDecoders);
    _updateActiveDecoderInfo(adjustedDecoders);

    if (savedDecoders == null ||
        savedDecoders.isEmpty ||
        !listEquals(savedDecoders, adjustedDecoders)) {
      await prefs.setStringList(_selectedDecodersKey, adjustedDecoders);
    }
  }

  /// 更新解码器设置
  Future<void> updateDecoders(List<String> decoders) async {
    if (kIsWeb) return;
    if (decoders.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final useHardwareDecoder = prefs.getBool(_useHardwareDecoderKey) ?? true;
      final adjustedDecoders =
          _applyHardwarePreference(decoders, useHardwareDecoder);
      player.setDecoders(MediaType.video, adjustedDecoders); // Use our MediaType
      _updateActiveDecoderInfo(adjustedDecoders);

      await prefs.setStringList(_selectedDecodersKey, adjustedDecoders);
    }
  }

  /// 更新活跃解码器信息
  void _updateActiveDecoderInfo(List<String> decoders) {
    if (decoders.isEmpty) return;

    _currentDecoder = decoders.first;

    // 更新系统资源监视器中的解码器信息
    String decoderInfo;
    if (decoders.length == 1 && decoders[0].toLowerCase().contains("ffmpeg")) {
      decoderInfo = "软解 - FFmpeg";
    } else {
      // 确定解码方式类型
      bool isHardwareDecoding = false;

      // 第一个解码器通常是优先使用的解码器
      String primaryDecoder = decoders[0];

      // 识别硬件解码器 (simplified check, actual hw/sw is determined by player)
      if (primaryDecoder.contains("VT") ||
          primaryDecoder.contains("D3D11") ||
          primaryDecoder.contains("DXVA") ||
          primaryDecoder.contains("MFT") ||
          primaryDecoder.contains("CUDA") ||
          primaryDecoder.contains("VAAPI") ||
          primaryDecoder.contains("VDPAU") ||
          primaryDecoder.contains("AMediaCodec") ||
          primaryDecoder == "OH" ||
          primaryDecoder.toLowerCase().contains("hap")) { // hap is often hardware accelerated
        isHardwareDecoding = true;
      }

      decoderInfo = isHardwareDecoding ? "硬解 - $primaryDecoder (首选)" : "软解 - $primaryDecoder (首选)";
    }

    // 更新系统资源监视器中的解码器信息
    SystemResourceMonitor().setActiveDecoder(decoderInfo);
  }

  /// 根据平台设置全局解码属性
  void _setGlobalDecodingProperties() {
    // 通用设置 - 不再需要设置大量属性
    // 官方建议：设置解码器就足够了，不需要过多复杂的setProperty调用
    if (kIsWeb) return;

    // 平台特定设置 - 仅保留基本的编解码器设置，不再手动调整大量参数
    if (Platform.isMacOS || Platform.isIOS) {
      // VideoToolbox不需要大量参数设置，解码器选择时已经配置好了
    } else if (Platform.isWindows) {
      // Windows平台使用简化的解码器设置
    } else if (Platform.isLinux) {
      // Linux平台使用简化的解码器设置
    } else if (Platform.isAndroid) {
      // Android平台使用简化的解码器设置
    }

    // 基本通用设置 - 保留关键属性
    player.setProperty("video.decode.thread", "4"); // 使用4个解码线程
  }

  /// 检查是否有NVIDIA GPU（Windows平台）
  bool _checkForNvidiaGpu() {
    if (kIsWeb) return false;
    if (Platform.isWindows) {
      try {
        final result = Process.runSync('wmic', ['path', 'win32_VideoController', 'get', 'name']);
        final output = result.stdout.toString().toLowerCase();
        return output.contains('nvidia');
      } catch (e) {
        debugPrint('检查NVIDIA GPU时出错: $e');
      }
    }
    return false;
  }

  /// 获取当前活跃解码器 (This method primarily reflects the *intended* or *configured* state)
  Future<String> getActiveDecoder() async {
    if (kIsWeb) return "浏览器解码";
    // This method now more reflects the configured decoders rather than a user toggle state.
    // The actual active decoder is best obtained from player.getProperty("video.decoder")
    // as done in updateCurrentActiveDecoder.
    // For now, let's simplify it based on what's configured.
    final prefs = await SharedPreferences.getInstance();
    final decoders = prefs.getStringList(_selectedDecodersKey) ?? [];

    if (decoders.isEmpty) {
      // If no decoders are saved, it means we're using platform defaults, which prioritize hardware.
      // Determine default for current platform to make an educated guess.
      final platformDefaultDecoders =
          platformDefaultDecodersForOperatingSystem(Platform.operatingSystem);

      if (platformDefaultDecoders.isNotEmpty) {
        final primaryDecoder = platformDefaultDecoders[0];
        if (_isSoftwareDecoder(primaryDecoder)) {
          _currentDecoder = "软解 - $primaryDecoder (默认)";
        } else {
          _currentDecoder = "硬解 - $primaryDecoder (默认)";
        }
      } else {
        _currentDecoder = "未知 (默认)";
      }
    } else if (decoders.isNotEmpty) {
      final primaryDecoder = decoders[0];
      if (_isSoftwareDecoder(primaryDecoder)) {
        _currentDecoder = "软解 - $primaryDecoder (配置)";
      } else {
        _currentDecoder = "硬解 - $primaryDecoder (配置)";
      }
    } else {
      _currentDecoder = "未知 (配置检查失败)";
    }
    SystemResourceMonitor().setActiveDecoder(_currentDecoder!);
    return _currentDecoder!;
  }

  /// 更新当前活跃解码器信息（从播放器获取）
  Future<void> updateCurrentActiveDecoder() async {
    if (kIsWeb) return;
    try {
      // 检查媒体信息
      if (player.mediaInfo.video == null || player.mediaInfo.video!.isEmpty) {
        _currentDecoder = "未知 (无视频轨道)";
        SystemResourceMonitor().setActiveDecoder(_currentDecoder!);
        return;
      }

      // 尝试从播放器获取当前正在使用的解码器名称
      // MDK: 通过 MediaEvent("decoder.video") 缓存到 "decoder.video"
      // Libmpv: 通常使用 hwdec/hwdec-current 进行判断
      final activeDecoderName =
          player.getProperty("decoder.video") ?? player.getProperty("video.decoder");

      if (activeDecoderName != null && activeDecoderName.isNotEmpty) {
        // 判断是硬解还是软解
        final lower = activeDecoderName.toLowerCase();
        // 一般来说，FFmpeg/auto/dav1d 属于软件解码；其余多数为硬件或平台解码器
        if (lower.contains("ffmpeg") || lower == "auto" || lower.contains("dav1d")) {
          _currentDecoder = "软解 - $activeDecoderName";
        } else {
          _currentDecoder = "硬解 - $activeDecoderName";
        }
      } else {
        // 如果无法直接获取，则根据已设置的解码器列表判断
        final setDecoders = player.getDecoders(MediaType.video); // Use our MediaType
        if (setDecoders.isNotEmpty) {
          if (setDecoders.length == 1 && setDecoders[0].toLowerCase().contains("ffmpeg")) {
            _currentDecoder = "软解 - FFmpeg";
          } else {
            // Check if the first decoder in the list is a known hardware decoder type
            final primaryConfigured = setDecoders[0];
            final primaryConfiguredLower = primaryConfigured.toLowerCase();
            bool isLikelyHardware = primaryConfiguredLower == "oh" || [
              "vt", "d3d11", "dxva", "mft", "cuda", "vaapi", "vdpau", "amediadcodec", "hap"
            ].any((hwKeyword) => primaryConfiguredLower.contains(hwKeyword));

            if (isLikelyHardware) {
              _currentDecoder = "硬解 - $primaryConfigured (尝试)";
            } else {
              _currentDecoder = "软解 - $primaryConfigured (尝试)";
            }
          }
        } else {
          _currentDecoder = "未知 (未设置解码器)";
        }
      }
      SystemResourceMonitor().setActiveDecoder(_currentDecoder!);
      debugPrint("更新活跃解码器: $_currentDecoder");

    } catch (e) {
      debugPrint('更新当前活跃解码器失败: $e');
      _currentDecoder = "未知 (错误)";
      SystemResourceMonitor().setActiveDecoder(_currentDecoder!);
    }
  }

  /// 强制启用硬件解码（如果当前是软解）
  Future<void> forceEnableHardwareDecoder() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final useHardwareDecoder = prefs.getBool(_useHardwareDecoderKey) ?? true;
    if (!useHardwareDecoder) {
      debugPrint('硬件解码开关已关闭，跳过强制启用硬件解码');
      return;
    }
    // Now that hardware decoding is default, this function primarily re-applies default hardware-first settings.
    // This can be useful if the player somehow ended up on software decoding despite hardware availability.
    debugPrint('尝试重新应用硬件优先的解码器设置...');
    await initialize(); // Initialize will set hardware-first decoders if no specific user choice is saved
    // or if saved choices are already hardware-first.
    final newActiveDecoder = await getActiveDecoder(); // Reflects configured state
    debugPrint('重新应用解码器设置后，配置的解码器: $newActiveDecoder');
    await updateCurrentActiveDecoder(); // Gets actual current decoder from player
    debugPrint('重新应用解码器设置后，播放器实际解码器: $_currentDecoder');
  }

  // 添加一个新的辅助方法，用于在截图后检查解码器状态
  Future<void> checkDecoderAfterScreenshot() async {
    if (kIsWeb) return;
    try {
      // 确保视频正在播放
      if (player.mediaInfo.video != null &&
          player.mediaInfo.video!.isNotEmpty &&
          player.state == PlaybackState.playing) {

        // 获取视频编码格式
        final videoTrack = player.mediaInfo.video![0];
        final codecString = videoTrack.toString().toLowerCase();

        // 特别关注HEVC格式
        if (codecString.contains('hevc') || codecString.contains('h265')) {
          debugPrint('截图后检查HEVC编码解码器状态...');

          // 在macOS上检查VideoToolbox状态
          if (Platform.isMacOS) {
            try {
              final prefs = await SharedPreferences.getInstance();
              final useHardwareDecoder =
                  prefs.getBool(_useHardwareDecoderKey) ?? true;
              if (!useHardwareDecoder) {
                debugPrint('硬件解码开关已关闭，跳过VideoToolbox重新启用');
              } else {
                final vtHardware = player.getProperty('vt.hardware');
                final hwdec = player.getProperty('hwdec');
                final vtFormat = player.getProperty('videotoolbox.format');

                if (vtHardware == "1" ||
                    (hwdec != null && hwdec.contains('videotoolbox')) ||
                    (vtFormat != null && vtFormat.isNotEmpty)) {
                  debugPrint('截图后确认VideoToolbox正在工作');
                } else {
                  debugPrint('截图后发现VideoToolbox可能未激活，尝试重新启用硬件解码...');

                  // 重新应用VideoToolbox设置
                  player.setProperty("videotoolbox.format", "nv12");
                  player.setProperty("vt.async", "1");
                  player.setProperty("vt.hardware", "1");
                  player.setProperty("hwdec", "videotoolbox");

                  List<String> decoders = ["VT", "hap", "dav1d", "FFmpeg"]; // Default hardware-first for macOS
                  player.setDecoders(MediaType.video, decoders);
                  debugPrint('截图后重新应用解码器设置: $decoders');
                }
              }
            } catch (e) {
              debugPrint('截图后检查VideoToolbox状态失败: $e');
            }
          }
        }

        // 更新解码器状态显示
        await updateCurrentActiveDecoder();
      }
    } catch (e) {
      debugPrint('截图后检查解码器状态失败: $e');
    }
  }
}
