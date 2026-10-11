/// Jellyfin转码设置模型
class JellyfinTranscodeSettings {
  /// 是否启用转码
  final bool enableTranscoding;
  
  /// 视频转码设置
  final JellyfinVideoTranscodeSettings video;
  
  /// 音频转码设置
  final JellyfinAudioTranscodeSettings audio;
  
  /// 字幕处理设置
  final JellyfinSubtitleSettings subtitle;
  
  /// 网络自适应设置
  final JellyfinAdaptiveSettings adaptive;

  const JellyfinTranscodeSettings({
    this.enableTranscoding = true,
    this.video = const JellyfinVideoTranscodeSettings(),
    this.audio = const JellyfinAudioTranscodeSettings(),
    this.subtitle = const JellyfinSubtitleSettings(),
    this.adaptive = const JellyfinAdaptiveSettings(),
  });

  JellyfinTranscodeSettings copyWith({
    bool? enableTranscoding,
    JellyfinVideoTranscodeSettings? video,
    JellyfinAudioTranscodeSettings? audio,
    JellyfinSubtitleSettings? subtitle,
    JellyfinAdaptiveSettings? adaptive,
  }) {
    return JellyfinTranscodeSettings(
      enableTranscoding: enableTranscoding ?? this.enableTranscoding,
      video: video ?? this.video,
      audio: audio ?? this.audio,
      subtitle: subtitle ?? this.subtitle,
      adaptive: adaptive ?? this.adaptive,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enableTranscoding': enableTranscoding,
      'video': video.toJson(),
      'audio': audio.toJson(),
      'subtitle': subtitle.toJson(),
      'adaptive': adaptive.toJson(),
    };
  }

  factory JellyfinTranscodeSettings.fromJson(Map<String, dynamic> json) {
    return JellyfinTranscodeSettings(
      enableTranscoding: json['enableTranscoding'] ?? true,
      video: JellyfinVideoTranscodeSettings.fromJson(json['video'] ?? {}),
      audio: JellyfinAudioTranscodeSettings.fromJson(json['audio'] ?? {}),
      subtitle: JellyfinSubtitleSettings.fromJson(json['subtitle'] ?? {}),
      adaptive: JellyfinAdaptiveSettings.fromJson(json['adaptive'] ?? {}),
    );
  }
}

/// 视频转码设置
class JellyfinVideoTranscodeSettings {
  /// 转码质量预设
  final JellyfinVideoQuality quality;
  
  /// 自定义视频比特率 (Kbps)
  final int? videoBitRate;
  
  /// 最大分辨率
  final JellyfinResolution? maxResolution;
  
  /// 视频编解码器偏好
  final List<String> preferredCodecs;
  
  /// 是否允许硬件加速
  final bool enableHardwareAcceleration;
  
  /// 最大帧率
  final double? maxFramerate;

  const JellyfinVideoTranscodeSettings({
    this.quality = JellyfinVideoQuality.auto,
    this.videoBitRate,
    this.maxResolution,
    this.preferredCodecs = const ['h264', 'hevc', 'av1'],
    this.enableHardwareAcceleration = true,
    this.maxFramerate,
  });

  JellyfinVideoTranscodeSettings copyWith({
    JellyfinVideoQuality? quality,
    int? videoBitRate,
    JellyfinResolution? maxResolution,
    List<String>? preferredCodecs,
    bool? enableHardwareAcceleration,
    double? maxFramerate,
  }) {
    return JellyfinVideoTranscodeSettings(
      quality: quality ?? this.quality,
      videoBitRate: videoBitRate ?? this.videoBitRate,
      maxResolution: maxResolution ?? this.maxResolution,
      preferredCodecs: preferredCodecs ?? this.preferredCodecs,
      enableHardwareAcceleration: enableHardwareAcceleration ?? this.enableHardwareAcceleration,
      maxFramerate: maxFramerate ?? this.maxFramerate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'quality': quality.index,
      'videoBitRate': videoBitRate,
      'maxResolution': maxResolution?.toJson(),
      'preferredCodecs': preferredCodecs,
      'enableHardwareAcceleration': enableHardwareAcceleration,
      'maxFramerate': maxFramerate,
    };
  }

  factory JellyfinVideoTranscodeSettings.fromJson(Map<String, dynamic> json) {
    return JellyfinVideoTranscodeSettings(
      quality: JellyfinVideoQuality.values[json['quality'] ?? 0],
      videoBitRate: json['videoBitRate'],
      maxResolution: json['maxResolution'] != null 
          ? JellyfinResolution.fromJson(json['maxResolution'])
          : null,
      preferredCodecs: List<String>.from(json['preferredCodecs'] ?? ['h264', 'hevc', 'av1']),
      enableHardwareAcceleration: json['enableHardwareAcceleration'] ?? true,
      maxFramerate: json['maxFramerate']?.toDouble(),
    );
  }
}

/// 音频转码设置
class JellyfinAudioTranscodeSettings {
  /// 音频比特率 (Kbps)
  final int? audioBitRate;
  
  /// 最大音频声道数
  final int maxAudioChannels;
  
  /// 音频编解码器偏好
  final List<String> preferredCodecs;
  
  /// 音频采样率
  final int? audioSampleRate;

  const JellyfinAudioTranscodeSettings({
    this.audioBitRate,
    this.maxAudioChannels = 2,
    this.preferredCodecs = const ['aac', 'mp3', 'opus'],
    this.audioSampleRate,
  });

  JellyfinAudioTranscodeSettings copyWith({
    int? audioBitRate,
    int? maxAudioChannels,
    List<String>? preferredCodecs,
    int? audioSampleRate,
  }) {
    return JellyfinAudioTranscodeSettings(
      audioBitRate: audioBitRate ?? this.audioBitRate,
      maxAudioChannels: maxAudioChannels ?? this.maxAudioChannels,
      preferredCodecs: preferredCodecs ?? this.preferredCodecs,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'audioBitRate': audioBitRate,
      'maxAudioChannels': maxAudioChannels,
      'preferredCodecs': preferredCodecs,
      'audioSampleRate': audioSampleRate,
    };
  }

  factory JellyfinAudioTranscodeSettings.fromJson(Map<String, dynamic> json) {
    return JellyfinAudioTranscodeSettings(
      audioBitRate: json['audioBitRate'],
      maxAudioChannels: json['maxAudioChannels'] ?? 2,
      preferredCodecs: List<String>.from(json['preferredCodecs'] ?? ['aac', 'mp3', 'opus']),
      audioSampleRate: json['audioSampleRate'],
    );
  }
}

/// 字幕处理设置
class JellyfinSubtitleSettings {
  /// 字幕传输方法
  final JellyfinSubtitleDeliveryMethod deliveryMethod;
  
  /// 是否启用字幕转码
  final bool enableTranscoding;
  
  /// 首选字幕编解码器
  final List<String> preferredCodecs;

  const JellyfinSubtitleSettings({
    this.deliveryMethod = JellyfinSubtitleDeliveryMethod.external,
    this.enableTranscoding = true,
    this.preferredCodecs = const ['srt', 'ass', 'vtt'],
  });

  JellyfinSubtitleSettings copyWith({
    JellyfinSubtitleDeliveryMethod? deliveryMethod,
    bool? enableTranscoding,
    List<String>? preferredCodecs,
  }) {
    return JellyfinSubtitleSettings(
      deliveryMethod: deliveryMethod ?? this.deliveryMethod,
      enableTranscoding: enableTranscoding ?? this.enableTranscoding,
      preferredCodecs: preferredCodecs ?? this.preferredCodecs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deliveryMethod': deliveryMethod.index,
      'enableTranscoding': enableTranscoding,
      'preferredCodecs': preferredCodecs,
    };
  }

  factory JellyfinSubtitleSettings.fromJson(Map<String, dynamic> json) {
    return JellyfinSubtitleSettings(
      deliveryMethod: JellyfinSubtitleDeliveryMethod.values[json['deliveryMethod'] ?? 1],
      enableTranscoding: json['enableTranscoding'] ?? true,
      preferredCodecs: List<String>.from(json['preferredCodecs'] ?? ['srt', 'ass', 'vtt']),
    );
  }
}

/// 网络自适应设置
class JellyfinAdaptiveSettings {
  /// 是否启用自适应码率
  final bool enableAdaptiveBitrate;
  
  /// 网络监测间隔（秒）
  final int networkCheckInterval;
  
  /// 低网速阈值 (Mbps)
  final double lowBandwidthThreshold;
  
  /// 高网速阈值 (Mbps)
  final double highBandwidthThreshold;

  const JellyfinAdaptiveSettings({
    this.enableAdaptiveBitrate = true,
    this.networkCheckInterval = 30,
    this.lowBandwidthThreshold = 2.0,
    this.highBandwidthThreshold = 10.0,
  });

  JellyfinAdaptiveSettings copyWith({
    bool? enableAdaptiveBitrate,
    int? networkCheckInterval,
    double? lowBandwidthThreshold,
    double? highBandwidthThreshold,
  }) {
    return JellyfinAdaptiveSettings(
      enableAdaptiveBitrate: enableAdaptiveBitrate ?? this.enableAdaptiveBitrate,
      networkCheckInterval: networkCheckInterval ?? this.networkCheckInterval,
      lowBandwidthThreshold: lowBandwidthThreshold ?? this.lowBandwidthThreshold,
      highBandwidthThreshold: highBandwidthThreshold ?? this.highBandwidthThreshold,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enableAdaptiveBitrate': enableAdaptiveBitrate,
      'networkCheckInterval': networkCheckInterval,
      'lowBandwidthThreshold': lowBandwidthThreshold,
      'highBandwidthThreshold': highBandwidthThreshold,
    };
  }

  factory JellyfinAdaptiveSettings.fromJson(Map<String, dynamic> json) {
    return JellyfinAdaptiveSettings(
      enableAdaptiveBitrate: json['enableAdaptiveBitrate'] ?? true,
      networkCheckInterval: json['networkCheckInterval'] ?? 30,
      lowBandwidthThreshold: json['lowBandwidthThreshold']?.toDouble() ?? 2.0,
      highBandwidthThreshold: json['highBandwidthThreshold']?.toDouble() ?? 10.0,
    );
  }
}

/// 视频质量预设（基于网络带宽）
enum JellyfinVideoQuality {
  auto,        // 自动选择（服务器决定）
  bandwidth1m, // 1 Mbps (360p)
  bandwidth2m, // 2 Mbps (480p)
  bandwidth5m, // 5 Mbps (720p)
  bandwidth10m,// 10 Mbps (1080p)
  bandwidth20m,// 20 Mbps (1080p高质量)
  bandwidth40m,// 40 Mbps (4K)
  original,    // 原始质量（不转码，DirectPlay）
}

extension JellyfinVideoQualityExtension on JellyfinVideoQuality {
  String get displayName {
    switch (this) {
      case JellyfinVideoQuality.auto:
        return '自动选择';
      case JellyfinVideoQuality.bandwidth1m:
        return '省流量 (1 Mbps, 360p)';
      case JellyfinVideoQuality.bandwidth2m:
        return '标准 (2 Mbps, 480p)';
      case JellyfinVideoQuality.bandwidth5m:
        return '高清 (5 Mbps, 720p)';
      case JellyfinVideoQuality.bandwidth10m:
        return '全高清 (10 Mbps, 1080p)';
      case JellyfinVideoQuality.bandwidth20m:
        return '超清 (20 Mbps, 1080p)';
      case JellyfinVideoQuality.bandwidth40m:
        return '4K (40 Mbps, 2160p)';
      case JellyfinVideoQuality.original:
        return '原始质量';
    }
  }

  /// 获取对应的比特率（Kbps）
  int? get bitrate {
    switch (this) {
      case JellyfinVideoQuality.bandwidth1m:
        return 1000;   // 1 Mbps
      case JellyfinVideoQuality.bandwidth2m:
        return 2000;   // 2 Mbps
      case JellyfinVideoQuality.bandwidth5m:
        return 5000;   // 5 Mbps
      case JellyfinVideoQuality.bandwidth10m:
        return 10000;  // 10 Mbps
      case JellyfinVideoQuality.bandwidth20m:
        return 20000;  // 20 Mbps
      case JellyfinVideoQuality.bandwidth40m:
        return 40000;  // 40 Mbps
      default:
        return null;   // auto 和 original 不限制
    }
  }

  /// 获取推荐的最大分辨率
  JellyfinResolution? get maxResolution {
    switch (this) {
      case JellyfinVideoQuality.bandwidth1m:
        return const JellyfinResolution(width: 640, height: 360);
      case JellyfinVideoQuality.bandwidth2m:
        return const JellyfinResolution(width: 854, height: 480);
      case JellyfinVideoQuality.bandwidth5m:
        return const JellyfinResolution(width: 1280, height: 720);
      case JellyfinVideoQuality.bandwidth10m:
      case JellyfinVideoQuality.bandwidth20m:
        return const JellyfinResolution(width: 1920, height: 1080);
      case JellyfinVideoQuality.bandwidth40m:
        return const JellyfinResolution(width: 3840, height: 2160);
      default:
        return null;   // auto 和 original 不限制分辨率
    }
  }
  
  /// 是否需要转码（原始质量不转码）
  bool get requiresTranscoding {
    return this != JellyfinVideoQuality.original;
  }
}

/// 分辨率设置
class JellyfinResolution {
  final int width;
  final int height;

  const JellyfinResolution({
    required this.width,
    required this.height,
  });

  JellyfinResolution copyWith({
    int? width,
    int? height,
  }) {
    return JellyfinResolution(
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'width': width,
      'height': height,
    };
  }

  factory JellyfinResolution.fromJson(Map<String, dynamic> json) {
    return JellyfinResolution(
      width: json['width'],
      height: json['height'],
    );
  }

  @override
  String toString() => '${width}x$height';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JellyfinResolution &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => width.hashCode ^ height.hashCode;
}

/// 字幕传输方法
enum JellyfinSubtitleDeliveryMethod {
  encode,   // 烧录到视频
  embed,    // 嵌入流中
  external, // 外部字幕文件
  hls,      // HLS分段
  drop,     // 不传输字幕
}

extension JellyfinSubtitleDeliveryMethodExtension on JellyfinSubtitleDeliveryMethod {
  String get apiValue {
    switch (this) {
      case JellyfinSubtitleDeliveryMethod.encode:
        return 'Encode';
      case JellyfinSubtitleDeliveryMethod.embed:
        return 'Embed';
      case JellyfinSubtitleDeliveryMethod.external:
        return 'External';
      case JellyfinSubtitleDeliveryMethod.hls:
        return 'Hls';
      case JellyfinSubtitleDeliveryMethod.drop:
        return 'Drop';
    }
  }

  String get displayName {
    switch (this) {
      case JellyfinSubtitleDeliveryMethod.encode:
        return '烧录字幕';
      case JellyfinSubtitleDeliveryMethod.embed:
        return '嵌入字幕';
      case JellyfinSubtitleDeliveryMethod.external:
        return '外挂字幕';
      case JellyfinSubtitleDeliveryMethod.hls:
        return 'HLS字幕';
      case JellyfinSubtitleDeliveryMethod.drop:
        return '不显示字幕';
    }
  }
}
