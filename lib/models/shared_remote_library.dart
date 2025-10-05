import 'dart:convert';

class SharedRemoteHost {
  SharedRemoteHost({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    this.lastConnectedAt,
    this.lastError,
    this.isOnline = false,
  });

  final String id;
  final String displayName;
  final String baseUrl;
  final DateTime? lastConnectedAt;
  final String? lastError;
  final bool isOnline;

  SharedRemoteHost copyWith({
    String? id,
    String? displayName,
    String? baseUrl,
    DateTime? lastConnectedAt,
    String? lastError,
    bool? isOnline,
  }) {
    return SharedRemoteHost(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      baseUrl: baseUrl ?? this.baseUrl,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      lastError: lastError,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'baseUrl': baseUrl,
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      'lastError': lastError,
      'isOnline': isOnline,
    };
  }

  factory SharedRemoteHost.fromJson(Map<String, dynamic> json) {
    return SharedRemoteHost(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      baseUrl: json['baseUrl'] as String,
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.tryParse(json['lastConnectedAt'] as String)
          : null,
      lastError: json['lastError'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }

  static List<SharedRemoteHost> decodeList(String raw) {
    final decoded = json.decode(raw) as List<dynamic>;
    return decoded.map((item) => SharedRemoteHost.fromJson(item as Map<String, dynamic>)).toList();
  }

  static String encodeList(List<SharedRemoteHost> hosts) {
    return json.encode(hosts.map((host) => host.toJson()).toList());
  }
}

class SharedRemoteAnimeSummary {
  SharedRemoteAnimeSummary({
    required this.animeId,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.imageUrl,
    required this.lastWatchTime,
    required this.episodeCount,
    required this.hasMissingFiles,
  });

  final int animeId;
  final String name;
  final String? nameCn;
  final String? summary;
  final String? imageUrl;
  final DateTime lastWatchTime;
  final int episodeCount;
  final bool hasMissingFiles;

  factory SharedRemoteAnimeSummary.fromJson(Map<String, dynamic> json) {
    return SharedRemoteAnimeSummary(
      animeId: json['animeId'] as int,
      name: json['name'] as String? ?? '未知番剧',
      nameCn: json['nameCn'] as String?,
      summary: json['summary'] as String?,
      imageUrl: json['imageUrl'] as String?,
      lastWatchTime: DateTime.tryParse(json['lastWatchTime'] as String? ?? '') ?? DateTime.now(),
      episodeCount: json['episodeCount'] as int? ?? 0,
      hasMissingFiles: json['hasMissingFiles'] as bool? ?? false,
    );
  }
}

class SharedRemoteEpisode {
  SharedRemoteEpisode({
    required this.shareId,
    required this.title,
    required this.fileName,
    required this.streamPath,
    required this.fileExists,
    this.animeId,
    this.episodeId,
    this.duration,
    this.progress,
    this.fileSize,
    this.lastWatchTime,
    this.videoHash,
  });

  final String shareId;
  final String title;
  final String fileName;
  final String streamPath;
  final bool fileExists;
  final int? animeId;
  final int? episodeId;
  final int? duration;
  final double? progress;
  final int? fileSize;
  final DateTime? lastWatchTime;
  final String? videoHash;

  factory SharedRemoteEpisode.fromJson(Map<String, dynamic> json) {
    return SharedRemoteEpisode(
      shareId: json['shareId'] as String,
      title: json['title'] as String? ?? '未知剧集',
      fileName: json['fileName'] as String? ?? 'unknown',
      streamPath: json['streamPath'] as String,
      fileExists: json['fileExists'] as bool? ?? true,
      animeId: json['animeId'] as int?,
      episodeId: json['episodeId'] as int?,
      duration: json['duration'] as int?,
      progress: (json['progress'] as num?)?.toDouble(),
      fileSize: json['fileSize'] as int?,
      lastWatchTime: json['lastWatchTime'] != null
          ? DateTime.tryParse(json['lastWatchTime'] as String)
          : null,
      videoHash: json['videoHash'] as String?,
    );
  }
}
