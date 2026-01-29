class PlaybackSession {
  final String itemId;
  final String? mediaSourceId;
  final String? playSessionId;
  final String streamUrl;
  final bool isTranscoding;
  final String? transcodingProtocol;
  final String? transcodingContainer;
  final List<PlaybackMediaSource> mediaSources;
  final PlaybackMediaSource? selectedSource;

  PlaybackSession({
    required this.itemId,
    required this.streamUrl,
    required this.isTranscoding,
    this.mediaSourceId,
    this.playSessionId,
    this.transcodingProtocol,
    this.transcodingContainer,
    this.mediaSources = const [],
    this.selectedSource,
  });

  PlaybackSession copyWith({
    String? streamUrl,
    bool? isTranscoding,
    String? mediaSourceId,
    String? playSessionId,
    String? transcodingProtocol,
    String? transcodingContainer,
    List<PlaybackMediaSource>? mediaSources,
    PlaybackMediaSource? selectedSource,
  }) {
    return PlaybackSession(
      itemId: itemId,
      streamUrl: streamUrl ?? this.streamUrl,
      isTranscoding: isTranscoding ?? this.isTranscoding,
      mediaSourceId: mediaSourceId ?? this.mediaSourceId,
      playSessionId: playSessionId ?? this.playSessionId,
      transcodingProtocol: transcodingProtocol ?? this.transcodingProtocol,
      transcodingContainer: transcodingContainer ?? this.transcodingContainer,
      mediaSources: mediaSources ?? this.mediaSources,
      selectedSource: selectedSource ?? this.selectedSource,
    );
  }
}

class PlaybackMediaSource {
  final String id;
  final String? container;
  final String? path;
  final String? directStreamUrl;
  final String? transcodingUrl;
  final String? transcodingContainer;
  final String? transcodingSubProtocol;
  final bool supportsTranscoding;
  final bool supportsDirectPlay;
  final bool supportsDirectStream;
  final List<Map<String, dynamic>> mediaStreams;

  const PlaybackMediaSource({
    required this.id,
    this.container,
    this.path,
    this.directStreamUrl,
    this.transcodingUrl,
    this.transcodingContainer,
    this.transcodingSubProtocol,
    this.supportsTranscoding = false,
    this.supportsDirectPlay = false,
    this.supportsDirectStream = false,
    this.mediaStreams = const [],
  });

  factory PlaybackMediaSource.fromJson(Map<String, dynamic> json) {
    final rawStreams = json['MediaStreams'];
    final parsedStreams = <Map<String, dynamic>>[];
    if (rawStreams is List) {
      for (final stream in rawStreams) {
        if (stream is Map) {
          parsedStreams.add(Map<String, dynamic>.from(stream));
        }
      }
    }
    return PlaybackMediaSource(
      id: json['Id']?.toString() ?? '',
      container: json['Container']?.toString(),
      path: json['Path']?.toString(),
      directStreamUrl: json['DirectStreamUrl']?.toString(),
      transcodingUrl: json['TranscodingUrl']?.toString(),
      transcodingContainer: json['TranscodingContainer']?.toString(),
      transcodingSubProtocol: json['TranscodingSubProtocol']?.toString(),
      supportsTranscoding: json['SupportsTranscoding'] == true,
      supportsDirectPlay: json['SupportsDirectPlay'] == true,
      supportsDirectStream: json['SupportsDirectStream'] == true,
      mediaStreams: parsedStreams,
    );
  }
}

class DeviceProfile {
  final String name;
  final List<DirectPlayProfile> directPlayProfiles;
  final List<TranscodingProfile> transcodingProfiles;
  final List<SubtitleProfile> subtitleProfiles;
  final List<ResponseProfile> responseProfiles;

  const DeviceProfile({
    required this.name,
    this.directPlayProfiles = const [],
    this.transcodingProfiles = const [],
    this.subtitleProfiles = const [],
    this.responseProfiles = const [],
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'Name': name,
    };
    if (directPlayProfiles.isNotEmpty) {
      json['DirectPlayProfiles'] =
          directPlayProfiles.map((p) => p.toJson()).toList();
    }
    if (transcodingProfiles.isNotEmpty) {
      json['TranscodingProfiles'] =
          transcodingProfiles.map((p) => p.toJson()).toList();
    }
    if (subtitleProfiles.isNotEmpty) {
      json['SubtitleProfiles'] =
          subtitleProfiles.map((p) => p.toJson()).toList();
    }
    if (responseProfiles.isNotEmpty) {
      json['ResponseProfiles'] =
          responseProfiles.map((p) => p.toJson()).toList();
    }
    return json;
  }
}

class DirectPlayProfile {
  final String type;
  final String? container;
  final String? videoCodec;
  final String? audioCodec;

  const DirectPlayProfile({
    required this.type,
    this.container,
    this.videoCodec,
    this.audioCodec,
  });

  Map<String, dynamic> toJson() {
    return {
      'Type': type,
      if (container != null && container!.isNotEmpty) 'Container': container,
      if (videoCodec != null && videoCodec!.isNotEmpty) 'VideoCodec': videoCodec,
      if (audioCodec != null && audioCodec!.isNotEmpty) 'AudioCodec': audioCodec,
    };
  }
}

class TranscodingProfile {
  final String type;
  final String container;
  final String protocol;
  final String? videoCodec;
  final String? audioCodec;
  final int? maxAudioChannels;
  final int? minSegments;
  final bool? breakOnNonKeyFrames;
  final bool? copyTimestamps;
  final bool? enableMpegtsM2TsMode;
  final String? context;

  const TranscodingProfile({
    required this.type,
    required this.container,
    required this.protocol,
    this.videoCodec,
    this.audioCodec,
    this.maxAudioChannels,
    this.minSegments,
    this.breakOnNonKeyFrames,
    this.copyTimestamps,
    this.enableMpegtsM2TsMode,
    this.context,
  });

  Map<String, dynamic> toJson() {
    return {
      'Type': type,
      'Container': container,
      'Protocol': protocol,
      if (videoCodec != null && videoCodec!.isNotEmpty) 'VideoCodec': videoCodec,
      if (audioCodec != null && audioCodec!.isNotEmpty) 'AudioCodec': audioCodec,
      if (maxAudioChannels != null) 'MaxAudioChannels': maxAudioChannels,
      if (minSegments != null) 'MinSegments': minSegments,
      if (breakOnNonKeyFrames != null)
        'BreakOnNonKeyFrames': breakOnNonKeyFrames,
      if (copyTimestamps != null) 'CopyTimestamps': copyTimestamps,
      if (enableMpegtsM2TsMode != null)
        'EnableMpegtsM2TsMode': enableMpegtsM2TsMode,
      if (context != null && context!.isNotEmpty) 'Context': context,
    };
  }
}

class SubtitleProfile {
  final String format;
  final String method;

  const SubtitleProfile({
    required this.format,
    required this.method,
  });

  Map<String, dynamic> toJson() {
    return {
      'Format': format,
      'Method': method,
    };
  }
}

class ResponseProfile {
  final String type;
  final String container;
  final String? videoCodec;
  final String? audioCodec;

  const ResponseProfile({
    required this.type,
    required this.container,
    this.videoCodec,
    this.audioCodec,
  });

  Map<String, dynamic> toJson() {
    return {
      'Type': type,
      'Container': container,
      if (videoCodec != null && videoCodec!.isNotEmpty) 'VideoCodec': videoCodec,
      if (audioCodec != null && audioCodec!.isNotEmpty) 'AudioCodec': audioCodec,
    };
  }
}
