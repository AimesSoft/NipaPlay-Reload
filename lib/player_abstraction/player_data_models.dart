import 'dart:typed_data';

enum PlayerUpscalerMode {
  off,
  erikaArtCnnC4F16,
  erikaArtCnnC4F32,
}

enum PlayerUpscalerBackendStatus {
  off,
  inactive,
  building,
  scalar,
  simdgroupMatrix,
  unknown,
}

class PlayerUpscalerStatus {
  final PlayerUpscalerMode requestedMode;
  final PlayerUpscalerBackendStatus activeBackend;
  final int fallbackCount;
  final int upscaledFrames;
  final Duration lastEncodeDuration;
  final Duration lastGpuDuration;

  const PlayerUpscalerStatus({
    required this.requestedMode,
    required this.activeBackend,
    required this.fallbackCount,
    required this.upscaledFrames,
    required this.lastEncodeDuration,
    required this.lastGpuDuration,
  });

  const PlayerUpscalerStatus.off()
      : requestedMode = PlayerUpscalerMode.off,
        activeBackend = PlayerUpscalerBackendStatus.off,
        fallbackCount = 0,
        upscaledFrames = 0,
        lastEncodeDuration = Duration.zero,
        lastGpuDuration = Duration.zero;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'requestedMode': requestedMode.name,
      'activeBackend': activeBackend.name,
      'fallbackCount': fallbackCount,
      'upscaledFrames': upscaledFrames,
      'lastEncodeMicros': lastEncodeDuration.inMicroseconds,
      'lastGpuMicros': lastGpuDuration.inMicroseconds,
    };
  }
}

class PlayerFrame {
  final int width;
  final int height;
  final Uint8List bytes;

  PlayerFrame({
    required this.width,
    required this.height,
    required this.bytes,
  });
}

class PlayerVideoCodecParams {
  final int width;
  final int height;
  final String? name;

  PlayerVideoCodecParams({required this.width, required this.height, this.name});
}

class PlayerVideoStreamInfo {
  final PlayerVideoCodecParams codec;
  final String? codecName;

  PlayerVideoStreamInfo({required this.codec, this.codecName});
}

class PlayerSubtitleStreamInfo {
  final String? title;
  final String? language;
  final Map<String, String> metadata;
  final String rawRepresentation; // For mdk.Track.toString() compatibility

  PlayerSubtitleStreamInfo({
    this.title,
    this.language,
    this.metadata = const {},
    required this.rawRepresentation,
  });

  @override
  String toString() => rawRepresentation;
}

class PlayerAudioCodecParams {
  final String? name;
  final int? bitRate;
  final int? channels;
  final int? sampleRate;
  // Add other relevant audio codec parameters if needed

  PlayerAudioCodecParams({
    this.name,
    this.bitRate,
    this.channels,
    this.sampleRate,
  });
}

class PlayerAudioStreamInfo {
  final PlayerAudioCodecParams codec;
  final String? title;
  final String? language;
  final Map<String, String> metadata;
  final String rawRepresentation; // For mdk.Track.toString() compatibility if needed for audio too
  final bool isExternal; // 是否为外部音频轨道（如外挂MKA）

  PlayerAudioStreamInfo({
    required this.codec,
    this.title,
    this.language,
    this.metadata = const {},
    required this.rawRepresentation,
    this.isExternal = false,
  });

  @override
  String toString() => rawRepresentation; // Or a more structured string
}

/// MKV/媒体容器自带的章节标识（来自 libmpv `chapter-list` 属性）。
///
/// 参考：
/// - REFERENCE/mpv/demux/demux_mkv.c:1130 demux_mkv_read_chapters — MKV EBML 章节解析
/// - REFERENCE/mpv/player/command.c:4674 mp_property_list_chapters — chapter-list 属性
/// - REFERENCE/mpv/player/playloop.c:607 get_current_chapter — 当前章节计算
class PlayerChapter {
  /// 章节在 chapter-list 中的索引（0-based）。
  final int index;

  /// 章节起始时间（毫秒，相对媒体起点）。
  final int startMs;

  /// 章节标题（可能为空字符串，对应 mpv "(unnamed)"）。
  final String title;

  const PlayerChapter({
    required this.index,
    required this.startMs,
    required this.title,
  });

  @override
  String toString() => 'PlayerChapter(#$index $startMs ms "$title")';
}

class PlayerMediaInfo {
  final int duration; // in milliseconds
  final List<PlayerVideoStreamInfo>? video;
  final List<PlayerAudioStreamInfo>? audio;
  final List<PlayerSubtitleStreamInfo>? subtitle;
  /// MKV/容器自带章节列表（按 startMs 升序），无章节时为 null。
  final List<PlayerChapter>? chapters;
  final String? specificErrorMessage;

  PlayerMediaInfo({
    required this.duration,
    this.video,
    this.audio,
    this.subtitle,
    this.chapters,
    this.specificErrorMessage,
  });

  // 添加copyWith方法以便更新个别字段
  PlayerMediaInfo copyWith({
    int? duration,
    List<PlayerVideoStreamInfo>? video,
    List<PlayerAudioStreamInfo>? audio,
    List<PlayerSubtitleStreamInfo>? subtitle,
    List<PlayerChapter>? chapters,
    String? specificErrorMessage,
  }) {
    return PlayerMediaInfo(
      duration: duration ?? this.duration,
      video: video ?? this.video,
      audio: audio ?? this.audio,
      subtitle: subtitle ?? this.subtitle,
      chapters: chapters ?? this.chapters,
      specificErrorMessage: specificErrorMessage ?? this.specificErrorMessage,
    );
  }
}
