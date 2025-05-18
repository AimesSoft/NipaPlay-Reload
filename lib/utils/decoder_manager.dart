import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fvp/mdk.dart';
import 'system_resource_monitor.dart'; // 导入系统资源监视器

/// 解码器管理类，负责视频解码器的配置和管理
class DecoderManager {
  final Player player;
  static const String _useHardwareDecoderKey = 'use_hardware_decoder';
  static const String _selectedDecodersKey = 'selected_decoders';
  
  // 当前活跃解码器信息
  String? _currentDecoder;

  DecoderManager({required this.player}) {
    initialize();
  }

  /// 初始化解码器设置
  Future<void> initialize() async {
    // 设置硬件解码器
    final prefs = await SharedPreferences.getInstance();
    final useHardwareDecoder = prefs.getBool(_useHardwareDecoderKey) ?? true;
    
    if (useHardwareDecoder) {
      final savedDecoders = prefs.getStringList(_selectedDecodersKey);
      if (savedDecoders != null && savedDecoders.isNotEmpty) {
        debugPrint('使用保存的解码器设置: $savedDecoders');
        player.setDecoders(MediaType.video, savedDecoders);
        // 更新活跃解码器信息
        _updateActiveDecoderInfo(savedDecoders);
      } else {
        // 获取当前平台的所有解码器
        List<String> decoders = [];
        final allDecoders = getAllSupportedDecoders();
        
        if (Platform.isMacOS) {
          decoders = allDecoders['macos']!;
          debugPrint('macOS平台默认解码器设置: $decoders');
        } else if (Platform.isIOS) {
          decoders = allDecoders['ios']!;
          debugPrint('iOS平台默认解码器设置: $decoders');
        } else if (Platform.isWindows) {
          decoders = allDecoders['windows']!;
          debugPrint('Windows平台默认解码器设置: $decoders');
        } else if (Platform.isLinux) {
          decoders = allDecoders['linux']!;
          debugPrint('Linux平台默认解码器设置: $decoders');
        } else if (Platform.isAndroid) {
          decoders = allDecoders['android']!;
          debugPrint('Android平台默认解码器设置: $decoders');
        } else {
          // 未知平台，使用FFmpeg作为兜底方案
          decoders = ["FFmpeg"];
          debugPrint('未知平台，使用FFmpeg解码器');
        }
        
        // 如果解码器列表不为空，则设置解码器
        if (decoders.isNotEmpty) {
          debugPrint('设置平台解码器: $decoders');
          player.setDecoders(MediaType.video, decoders);
          _updateActiveDecoderInfo(decoders);
          
          // 保存设置的解码器列表
          await prefs.setStringList(_selectedDecodersKey, decoders);
        }
      }
      
      // 设置全局解码属性
      _setGlobalDecodingProperties();
      
      // 输出解码器相关属性
      debugPrint('硬件解码已启用');
    } else {
      // 只使用软件解码
      debugPrint('硬件解码已禁用，仅使用软件解码器');
      player.setDecoders(MediaType.video, ["FFmpeg"]);
      _updateActiveDecoderInfo(["FFmpeg"]);
    }
  }

  /// 配置所有支持的解码器，按平台组织
  Map<String, List<String>> getAllSupportedDecoders() {
    // 为所有平台准备解码器列表
    final Map<String, List<String>> platformDecoders = {
      // macOS解码器 - Apple平台不支持NVIDIA GPU
      'macos': [
        "VT", // Apple平台首选
        "hap", // 对于HAP编码视频
        "dav1d", // AV1解码
        "FFmpeg" // 通用软件解码
      ],
      
      // iOS解码器
      'ios': [
        "VT",
        "hap",
        "dav1d",
        "FFmpeg"
      ],
      
      // Windows解码器
      'windows': [
        "MFT:d3d=11", // Windows首选
        "MFT:d3d=12", // D3D12支持
        "D3D11", // FFmpeg D3D11
        "D3D12", // FFmpeg D3D12
        "DXVA", // 旧版支持
        "CUDA", // NVIDIA GPU
        "QSV", // Intel QuickSync
        "NVDEC", // NVIDIA专用
        "hap",
        "dav1d",
        "FFmpeg"
      ],
      
      // Linux解码器
      'linux': [
        "VAAPI", // Intel/AMD GPU
        "VDPAU", // NVIDIA
        "CUDA",
        "NVDEC",
        "rkmpp", // RockChip
        "V4L2M2M", // 视频硬件解码API
        "hap",
        "dav1d",
        "FFmpeg"
      ],
      
      // Android解码器
      'android': [
        "AMediaCodec", // 首选
        "MediaCodec", // FFmpeg实现
        "dav1d",
        "FFmpeg"
      ]
    };
    
    return platformDecoders;
  }

  /// 更新解码器设置
  Future<void> updateDecoders(List<String> decoders) async {
    if (decoders.isNotEmpty) {
      player.setDecoders(MediaType.video, decoders);
      // 更新活跃解码器信息
      _updateActiveDecoderInfo(decoders);
      
      // 保存设置
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_selectedDecodersKey, decoders);
    }
  }

  /// 更新活跃解码器信息
  void _updateActiveDecoderInfo(List<String> decoders) {
    if (decoders.isEmpty) return;
    
    _currentDecoder = decoders.first;
    
    // 更新系统资源监视器中的解码器信息
    String decoderInfo;
    if (decoders.length == 1 && decoders[0] == "FFmpeg") {
      decoderInfo = "软解 - FFmpeg";
    } else {
      // 确定解码方式类型
      bool isHardwareDecoding = false;
      
      // 第一个解码器通常是优先使用的解码器
      String primaryDecoder = decoders[0];
      
      // 识别硬件解码器
      if (primaryDecoder.contains("VT") || 
          primaryDecoder.contains("D3D11") || 
          primaryDecoder.contains("DXVA") || 
          primaryDecoder.contains("MFT") || 
          primaryDecoder.contains("CUDA") || 
          primaryDecoder.contains("VAAPI") || 
          primaryDecoder.contains("VDPAU") || 
          primaryDecoder.contains("AMediaCodec") ||
          primaryDecoder.contains("hap")) {
        isHardwareDecoding = true;
      }
      
      decoderInfo = isHardwareDecoding ? "硬解 - $primaryDecoder" : "软解 - $primaryDecoder";
    }
    
    // 更新系统资源监视器中的解码器信息
    SystemResourceMonitor().setActiveDecoder(decoderInfo);
  }

  /// 根据平台设置全局解码属性
  void _setGlobalDecodingProperties() {
    // 通用设置
    player.setProperty("video.decode.thread", "4"); // 使用4个解码线程
    
    // 平台特定设置
    if (Platform.isMacOS || Platform.isIOS) {
      // VideoToolbox优化
      player.setProperty("videotoolbox.format", "nv12"); // 对于macOS和iOS优化
      player.setProperty("vt.copy", "0"); // 无复制模式以获得最佳性能
      player.setProperty("vt.async", "1"); // 启用异步解码
      player.setProperty("vt.hardware", "1"); // 确保使用硬件加速
      
      // 检查当前播放视频是否为HEVC格式
      bool isHevcVideo = false;
      if (player.mediaInfo.video != null && player.mediaInfo.video!.isNotEmpty) {
        final codecString = player.mediaInfo.video![0].toString().toLowerCase();
        isHevcVideo = codecString.contains('hevc') || codecString.contains('h265');
      }
      
      // Apple Silicon特定优化
      if (Platform.isMacOS) {
        try {
          // 检测是否为Apple Silicon
          final result = Process.runSync('sysctl', ['hw.optional.arm64']);
          if (result.stdout.toString().contains('hw.optional.arm64: 1')) {
            // Apple Silicon特定设置
            debugPrint('检测到Apple Silicon，应用特定优化');
            player.setProperty("vt.realTime", "1"); // 实时模式
            
            // 对HEVC格式的特殊处理
            if (isHevcVideo) {
              debugPrint('在Apple Silicon上应用HEVC专用硬解设置');
              player.setProperty("videotoolbox.hwaccel", "1"); // 强制硬件加速
              player.setProperty("videotoolbox.zero_copy", "1"); // 零拷贝模式
              player.setProperty("videotoolbox.device", "0"); // 默认设备
              player.setProperty("videotoolbox.hevc_skip_alpha", "1"); // 跳过Alpha通道处理
              player.setProperty("videotoolbox.format_pref", "bgra"); // 首选格式
              player.setProperty("videotoolbox.supports_hevc", "1"); // 明确标记支持HEVC
              player.setProperty("hwdec", "videotoolbox"); // 直接指定硬件解码器
              player.setProperty("hwdec.device", "0"); // 指定设备
              player.setProperty("decoder.priority", "videotoolbox,hap,dav1d,ffmpeg"); // 直接设置解码器优先级
            }
          }
        } catch (e) {
          debugPrint('检测处理器架构时出错: $e');
        }
      }
    } else if (Platform.isWindows) {
      // Windows解码器优化
      player.setProperty("avcodec.hw", "any"); // 尝试任何可用的硬件解码器
      player.setProperty("mft.d3d", "11"); // 默认使用D3D11
      player.setProperty("mft.low_latency", "1"); // 低延迟模式
      player.setProperty("mft.feature_level", "12.1"); // D3D功能级别
      player.setProperty("mft.shared", "1"); // 资源共享
      player.setProperty("mft.pool", "1"); // 使用解码样本池
      
      // 检测是否有NVIDIA GPU
      try {
        final hasNvidiaGpu = _checkForNvidiaGpu();
        if (hasNvidiaGpu) {
          debugPrint('检测到NVIDIA GPU，添加CUDA优化');
          player.setProperty("cuda.device", "0"); // 对于NVIDIA GPU设置CUDA设备
        }
      } catch (e) {
        debugPrint('检测GPU时出错: $e');
      }
    } else if (Platform.isLinux) {
      // Linux解码器优化
      player.setProperty("vaapi.copy", "0"); // 无复制模式
      player.setProperty("vdpau.copy", "0"); // 无复制模式
      player.setProperty("avcodec.hw", "any"); // 尝试任何可用的硬件解码器
    } else if (Platform.isAndroid) {
      // Android解码器优化
      player.setProperty("mediacodec.surface", "1"); // 使用Surface
      player.setProperty("mediacodec.async", "1"); // 异步模式
      player.setProperty("mediacodec.copy", "0"); // 无复制模式
      player.setProperty("mediacodec.image", "1"); // 使用AImageReader
      player.setProperty("mediacodec.dv", "1"); // 支持杜比视界
    }
    
    // 通用高级设置
    player.setProperty("video.decoder", "base=1"); // 使用基础层数据包
    player.setProperty("video.decoder", "dovi=1"); // 支持杜比视界元数据传递
    player.setProperty("video.decoder", "cc=1"); // 支持隐藏字幕
    player.setProperty("video.decoder", "alpha=1"); // 支持Alpha通道
  }

  /// 检查是否有NVIDIA GPU（Windows平台）
  bool _checkForNvidiaGpu() {
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

  /// 获取当前活跃解码器
  Future<String> getActiveDecoder() async {
    try {
      // 首先检查用户设置是否禁用了硬件解码
      final prefs = await SharedPreferences.getInstance();
      final useHardwareDecoder = prefs.getBool(_useHardwareDecoderKey) ?? true;
      if (!useHardwareDecoder) {
        debugPrint('硬件解码已在设置中禁用，强制报告为软解');
      }
      
      // 同步检查保存的解码器设置，如果只有FFmpeg，则视为软解
      final decoders = prefs.getStringList(_selectedDecodersKey) ?? [];
      if (decoders.length == 1 && decoders[0] == "FFmpeg") {
        debugPrint('当前仅使用FFmpeg解码器，强制报告为软解');
      }
      
      // 检查媒体信息
      if (player.mediaInfo.video == null || player.mediaInfo.video!.isEmpty) {
        return "未知"; // 无视频轨道
      }
      
      final videoTrack = player.mediaInfo.video![0];
      
      // 移除不存在的extras属性相关代码
      debugPrint('准备获取解码器信息...');
      
      // 确定视频编码格式
      final codecString = videoTrack.toString();
      String format = "";
      if (codecString.contains("h264") || codecString.contains("avc")) {
        format = "H.264";
      } else if (codecString.contains("hevc") || codecString.contains("h265")) {
        format = "HEVC";
      } else if (codecString.contains("av1")) {
        format = "AV1";
      } else if (codecString.contains("vp9")) {
        format = "VP9";
      } else {
        format = "其他格式";
      }
      
      // HEVC格式的特殊检测逻辑（尤其是在macOS/iOS上）
      if ((Platform.isMacOS || Platform.isIOS) && format == "HEVC") {
        // 检查硬件解码器属性
        try {
          bool isUsingHardware = false;
          
          // 对VT的特殊检查
          try {
            // 尝试多种属性获取VideoToolbox状态
            final vtHardware = player.getProperty('vt.hardware');
            if (vtHardware == "1") {
              debugPrint('检测到VT硬件解码已启用');
              isUsingHardware = true;
            }
            
            final hwdec = player.getProperty('hwdec');
            if (hwdec != null && (hwdec.contains('videotoolbox') || hwdec.contains('vt'))) {
              debugPrint('检测到hwdec属性指向VideoToolbox: $hwdec');
              isUsingHardware = true;
            }
            
            // 直接访问VideoToolbox专用属性
            final vtFormat = player.getProperty('videotoolbox.format');
            if (vtFormat != null && vtFormat.isNotEmpty) {
              debugPrint('检测到VideoToolbox格式设置: $vtFormat');
              isUsingHardware = true;
            }
          } catch (e) {
            debugPrint('检查VideoToolbox状态失败: $e');
          }
          
          if (isUsingHardware) {
            final result = "硬解($format) - VideoToolbox";
            // 更新系统资源监视器
            SystemResourceMonitor().setActiveDecoder(result);
            return result;
          }
        } catch (e) {
          debugPrint('检查HEVC硬件解码状态失败: $e');
        }
      }
      
      // 尝试获取当前解码器
      String? currentDecoder;
      try {
        currentDecoder = player.getProperty('video.decoder.current');
        if (currentDecoder != null && currentDecoder.isNotEmpty) {
          debugPrint('当前解码器: $currentDecoder');
        }
      } catch (e) {
        debugPrint('获取video.decoder.current属性失败: $e');
      }
      
      // 获取解码器说明（如果有）
      String? decoderDescription;
      try {
        decoderDescription = player.getProperty('decoder.description');
        if (decoderDescription != null && decoderDescription.isNotEmpty) {
          debugPrint('解码器说明: $decoderDescription');
        }
      } catch (e) {
        debugPrint('获取decoder.description属性失败: $e');
      }
      
      // 尝试获取更多解码相关属性
      try {
        final hwdec = player.getProperty('hwdec');
        if (hwdec != null && hwdec.isNotEmpty) {
          debugPrint('hwdec属性: $hwdec');
          // 如果hwdec属性非空且不是"no"，则很可能使用硬件解码
          if (hwdec != "no" && !hwdec.contains("disabled")) {
            String result = "硬解($format) - $hwdec";
            SystemResourceMonitor().setActiveDecoder(result);
            return result;
          }
        }
      } catch (e) {
        debugPrint('获取hwdec属性失败: $e');
      }
      
      // 如果在第一个特例检查中未确定是硬解，但存在VT相关的属性，仍可能是硬解
      if ((Platform.isMacOS || Platform.isIOS) && format == "HEVC") {
        try {
          // 再次检查保存的解码器配置
          final decoders = prefs.getStringList(_selectedDecodersKey) ?? [];
          if (decoders.isNotEmpty && decoders[0] == "VT") {
            debugPrint('解码器配置中第一解码器为VT，可能是硬解: $decoders');
          }
          
          // 如果VT在配置的第一位，更倾向于认为它在工作，除非明确有证据表明它不工作
          bool probablyUsingHardware = false;
          if (decoders.isNotEmpty && decoders[0] == "VT") {
            probablyUsingHardware = true;
          }
          
          if (probablyUsingHardware) {
            String result = "硬解($format) - VideoToolbox";
            SystemResourceMonitor().setActiveDecoder(result);
            debugPrint('根据解码器配置认为很可能使用硬解: $result');
            return result;
          }
        } catch (e) {
          debugPrint('检查解码器配置失败: $e');
        }
      }
      
      // 尝试获取所有解码器属性
      Map<String, String> decoderProperties = {};
      final propertyKeys = [
        'video.decoder', 'video.decoder.current',
        'decoder.description', 'hwaccel',
        'hwaccel.copy', 'hwdevice',
        'avcodec.hw', 'video.decode.thread',
        'video.hardware'
      ];
      
      for (final key in propertyKeys) {
        try {
          final value = player.getProperty(key);
          if (value != null && value.isNotEmpty) {
            decoderProperties[key] = value;
          }
        } catch (e) {
          // 忽略不支持的属性
        }
      }
      
      // 输出所有收集到的解码器属性
      if (decoderProperties.isNotEmpty) {
        debugPrint('解码器相关属性:');
        decoderProperties.forEach((key, value) {
          debugPrint('  $key: $value');
        });
      } else {
        debugPrint('未找到任何解码器相关属性');
      }
      
      // 使用增强的解码器识别逻辑
      
      // 如果从player直接获取到了解码器信息，优先使用
      if (currentDecoder != null && currentDecoder.isNotEmpty) {
        // 检查是否为硬件解码器
        String result;
        if (currentDecoder.contains("VT") || 
            currentDecoder.contains("MFT") || 
            currentDecoder.contains("D3D") || 
            currentDecoder.contains("DXVA") ||
            currentDecoder.contains("CUDA") ||
            currentDecoder.contains("VAAPI") ||
            currentDecoder.contains("VDPAU") ||
            currentDecoder.contains("MediaCodec") ||
            currentDecoder.contains("QSV") ||
            currentDecoder.contains("NVDEC") ||
            currentDecoder.contains("MMAL") ||
            currentDecoder.contains("V4L2") ||
            currentDecoder.contains("CedarX")) {
          result = "硬解($format) - $currentDecoder";
        } else {
          result = "软解($format) - $currentDecoder";
        }
        
        // 更新系统资源监视器
        SystemResourceMonitor().setActiveDecoder(result);
        return result;
      }
      
      // 使用解码器说明判断
      if (decoderDescription != null && decoderDescription.isNotEmpty) {
        // 检查是否为硬件解码器
        if (decoderDescription.contains("VideoToolbox") ||
            decoderDescription.contains("Direct3D") ||
            decoderDescription.contains("DXVA") ||
            decoderDescription.contains("CUDA") ||
            decoderDescription.contains("VAAPI") ||
            decoderDescription.contains("VDPAU") ||
            decoderDescription.contains("MediaCodec") ||
            decoderDescription.contains("QuickSync") ||
            decoderDescription.contains("NVDEC")) {
          String result = "硬解($format) - $decoderDescription";
          // 更新系统资源监视器
          SystemResourceMonitor().setActiveDecoder(result);
          return result;
        }
      }
      
      // 如果都没有明确信息，则根据编解码器猜测
      if (codecString.contains("hwaccel") || 
          codecString.contains("hw decoder") ||
          codecString.contains("hardware")) {
        String result = "硬解($format)";
        // 更新系统资源监视器
        SystemResourceMonitor().setActiveDecoder(result);
        return result;
      }
      
      String result = "软解($format)";
      // 更新系统资源监视器
      SystemResourceMonitor().setActiveDecoder(result);
      return result;
    } catch (e) {
      debugPrint('获取活跃解码器信息失败: $e');
      return "未知";
    }
  }

  /// 更新当前活跃解码器信息
  Future<void> updateCurrentActiveDecoder() async {
    // 确保视频已经在播放
    if (player.mediaInfo.video != null && player.mediaInfo.video!.isNotEmpty) {
      // 首先检查硬件解码设置
      final prefs = await SharedPreferences.getInstance();
      final useHardwareDecoder = prefs.getBool(_useHardwareDecoderKey) ?? true;
      final selectedDecoders = prefs.getStringList(_selectedDecodersKey) ?? [];
      
      // 如果硬件解码被禁用，或者只使用FFmpeg，则强制使用软解
      if (!useHardwareDecoder || (selectedDecoders.length == 1 && selectedDecoders[0] == "FFmpeg")) {
        // 获取视频格式
        final videoTrack = player.mediaInfo.video![0];
        final codecString = videoTrack.toString().toLowerCase();
        String format = "未知格式";
        
        if (codecString.contains("h264") || codecString.contains("avc")) {
          format = "H.264";
        } else if (codecString.contains("hevc") || codecString.contains("h265")) {
          format = "HEVC";
        } else if (codecString.contains("av1")) {
          format = "AV1";
        } else if (codecString.contains("vp9")) {
          format = "VP9";
        } else if (codecString.contains("vp8")) {
          format = "VP8";
        } 
        
        // 设置为软解状态
        final softwareDecoder = "软解($format) - FFmpeg";
        // 更新系统资源监视器
        SystemResourceMonitor().setActiveDecoder(softwareDecoder);
        debugPrint('硬件解码已禁用，强制使用软解: $softwareDecoder');
        return;
      }
      
      // 先尝试获取当前解码器的更多属性
      try {
        // 尝试获取更多解码器相关属性
        final hwaccels = player.getProperty('avcodec.hwaccels');
        debugPrint('可用的硬件加速器: $hwaccels');
      } catch (e) {
        debugPrint('获取硬件加速器列表失败: $e');
      }
      
      try {
        // 尝试获取当前硬件加速状态
        final hwaccel = player.getProperty('hwaccel');
        debugPrint('当前硬件加速状态: $hwaccel');
      } catch (e) {
        debugPrint('获取当前硬件加速状态失败: $e');
      }
      
      // 尝试获取所有解码器属性
      Map<String, String> decoderProperties = {};
      final propertyKeys = [
        'video.decoder', 'video.decoder.current',
        'decoder.description', 'hwaccel',
        'hwaccel.copy', 'hwdevice',
        'avcodec.hw', 'video.decode.thread',
        'video.hardware'
      ];
      
      for (final key in propertyKeys) {
        try {
          final value = player.getProperty(key);
          if (value != null && value.isNotEmpty) {
            decoderProperties[key] = value;
          }
        } catch (e) {
          // 忽略不支持的属性
        }
      }
      
      // 输出所有收集到的解码器属性
      if (decoderProperties.isNotEmpty) {
        debugPrint('解码器相关属性:');
        decoderProperties.forEach((key, value) {
          debugPrint('  $key: $value');
        });
      } else {
        debugPrint('未找到任何解码器相关属性');
      }
      
      // 使用增强的解码器识别逻辑
      final activeDecoder = await getActiveDecoder();
      
      // 更新系统资源监视器
      SystemResourceMonitor().setActiveDecoder(activeDecoder);
      debugPrint('更新当前活跃解码器: $activeDecoder');
    }
  }

  /// 切换硬件解码状态
  Future<void> toggleHardwareDecoder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentValue = prefs.getBool(_useHardwareDecoderKey) ?? true;
      final newValue = !currentValue;
      
      // 保存新设置
      await prefs.setBool(_useHardwareDecoderKey, newValue);
      
      if (newValue) {
        // 启用硬件解码
        debugPrint('启用硬件解码');
        
        // 获取当前平台的解码器
        List<String> decoders = [];
        final allDecoders = getAllSupportedDecoders();
        
        if (Platform.isMacOS) {
          decoders = allDecoders['macos']!;
        } else if (Platform.isIOS) {
          decoders = allDecoders['ios']!;
        } else if (Platform.isWindows) {
          decoders = allDecoders['windows']!;
        } else if (Platform.isLinux) {
          decoders = allDecoders['linux']!;
        } else if (Platform.isAndroid) {
          decoders = allDecoders['android']!;
        } else {
          decoders = ["FFmpeg"];
        }
        
        // 获取之前保存的解码器列表
        final savedDecoders = prefs.getStringList(_selectedDecodersKey);
        if (savedDecoders != null && savedDecoders.isNotEmpty && savedDecoders[0] != "FFmpeg") {
          decoders = savedDecoders;
        }
        
        // 应用解码器
        await updateDecoders(decoders);
        
        // 设置全局解码属性
        _setGlobalDecodingProperties();
        
        // 更新当前解码器信息
        updateCurrentActiveDecoder();
      } else {
        // 禁用硬件解码
        debugPrint('禁用硬件解码，仅使用软件解码');
        await updateDecoders(["FFmpeg"]);
        
        // 更新当前解码器信息
        updateCurrentActiveDecoder();
      }
    } catch (e) {
      debugPrint('切换硬件解码状态失败: $e');
    }
  }
  
  /// 强制启用硬件解码（用于视频播放中）
  Future<void> forceEnableHardwareDecoder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 检查当前是否有视频播放
      if (player.mediaInfo.video == null || player.mediaInfo.video!.isEmpty) {
        debugPrint('没有视频播放，无法强制启用硬件解码');
        return;
      }
      
      // 检查当前的解码器设置
      final currentHwDecoding = prefs.getBool(_useHardwareDecoderKey) ?? true;
      if (currentHwDecoding) {
        debugPrint('硬件解码已经启用，无需操作');
        // 检查是否实际使用了硬件解码
        final videoTrack = player.mediaInfo.video![0];
        final codecString = videoTrack.toString().toLowerCase();
        
        // HEVC格式视频特殊处理
        bool isHevc = codecString.contains('hevc') || codecString.contains('h265');
        if (isHevc) {
          debugPrint('检测到HEVC格式视频，应用特殊硬解设置');
          
          // 对于macOS，强制使用VideoToolbox
          if (Platform.isMacOS) {
            // 特别确保VT解码器位于第一位
            List<String> optimizedDecoders = ["VT", "hap", "dav1d", "FFmpeg"];
            player.setDecoders(MediaType.video, optimizedDecoders);
            
            // 特别设置VT相关参数
            player.setProperty("videotoolbox.format", "nv12");
            player.setProperty("videotoolbox.async", "1");
            player.setProperty("videotoolbox.hwaccel", "1");
            player.setProperty("videotoolbox.zero_copy", "1");
            player.setProperty("videotoolbox.device", "0");
            
            // 明确指定硬件解码器
            player.setProperty("hwdec", "videotoolbox");
            
            // 立即更新当前解码器信息
            _updateActiveDecoderInfo(optimizedDecoders);
            
            debugPrint('已特别优化HEVC硬解设置: $optimizedDecoders');
            
            // 保存这个特殊的解码器设置
            await prefs.setStringList(_selectedDecodersKey, optimizedDecoders);
            
            // 稍后检查解码器状态
            await Future.delayed(const Duration(seconds: 1));
            await updateCurrentActiveDecoder();
            
            // 10秒后再次检查解码器状态
            Future.delayed(const Duration(seconds: 10), () async {
              await updateCurrentActiveDecoder();
            });
            
            return;
          }
        }
        return;
      }
      
      // 保存新设置
      await prefs.setBool(_useHardwareDecoderKey, true);
      
      // 获取当前平台的解码器
      List<String> decoders = [];
      final allDecoders = getAllSupportedDecoders();
      
      if (Platform.isMacOS) {
        decoders = allDecoders['macos']!;
      } else if (Platform.isIOS) {
        decoders = allDecoders['ios']!;
      } else if (Platform.isWindows) {
        decoders = allDecoders['windows']!;
      } else if (Platform.isLinux) {
        decoders = allDecoders['linux']!;
      } else if (Platform.isAndroid) {
        decoders = allDecoders['android']!;
      } else {
        decoders = ["FFmpeg"];
      }
      
      if (decoders.isNotEmpty) {
        // 保存选择的解码器
        await prefs.setStringList(_selectedDecodersKey, decoders);
        
        // 设置解码器之前先停止播放器
        bool wasPlaying = false;
        if (player.state == PlaybackState.playing) {
          wasPlaying = true;
          player.state = PlaybackState.paused;
          debugPrint('暂停播放以重新配置解码器');
          await Future.delayed(const Duration(milliseconds: 100));
        }
        
        // 应用解码器设置
        debugPrint('应用解码器设置: $decoders');
        player.setDecoders(MediaType.video, decoders);
        
        // 设置硬件解码相关全局属性
        _setGlobalDecodingProperties();
        
        // 更新解码器信息显示
        _updateActiveDecoderInfo(decoders);
        
        // 如果之前在播放，恢复播放
        if (wasPlaying) {
          await Future.delayed(const Duration(milliseconds: 300));
          player.state = PlaybackState.playing;
          debugPrint('恢复播放');
        }
        
        // 稍后检查解码器状态
        debugPrint('等待1秒后检查解码器状态...');
        await Future.delayed(const Duration(seconds: 1));
        await updateCurrentActiveDecoder();
        
        // 10秒后再次检查解码器状态（确保持续使用硬件解码）
        Future.delayed(const Duration(seconds: 10), () async {
          await updateCurrentActiveDecoder();
        });
        
        debugPrint('硬件解码强制启用成功');
        return;
      }
    } catch (e) {
      debugPrint('强制启用硬件解码失败: $e');
    }
  }

  // 添加一个新的辅助方法，用于在截图后检查解码器状态
  Future<void> checkDecoderAfterScreenshot() async {
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
                
                // 刷新解码器列表
                SharedPreferences prefs = await SharedPreferences.getInstance();
                final useHardwareDecoder = prefs.getBool(_useHardwareDecoderKey) ?? true;
                
                if (useHardwareDecoder) {
                  List<String> decoders = ["VT", "hap", "dav1d", "FFmpeg"];
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