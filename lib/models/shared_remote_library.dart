import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';

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
    String? imageUrl = json['imageUrl'] as String?;
    
    if (kIsWeb && 
        imageUrl != null && 
        imageUrl.isNotEmpty && 
        !imageUrl.startsWith('http://') && 
        !imageUrl.startsWith('https://')) {
      final original = imageUrl;
      imageUrl = WebRemoteAccessService.imageProxyUrl(imageUrl);
      debugPrint('[SharedRemoteLib] Converted local image: $original -> $imageUrl');
    }

    return SharedRemoteAnimeSummary(
      animeId: json['animeId'] as int,
      name: json['name'] as String? ?? '未知番剧',
      nameCn: json['nameCn'] as String?,
      summary: json['summary'] as String?,
      imageUrl: imageUrl,
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
    this.lastPosition,
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
  final int? lastPosition;
  final double? progress;
  final int? fileSize;
  final DateTime? lastWatchTime;
  final String? videoHash;

  factory SharedRemoteEpisode.fromJson(Map<String, dynamic> json) {
    final rawStreamPath = json['streamPath'] as String?;
    final originalFilePath = json['originalFilePath'] as String?;
    final resolvedStreamPath = (rawStreamPath ?? '').trim().isNotEmpty
        ? rawStreamPath!.trim()
        : (originalFilePath ?? '').trim();

    return SharedRemoteEpisode(
      shareId: json['shareId']?.toString() ?? '',
      title: json['title'] as String? ?? '未知剧集',
      fileName: json['fileName'] as String? ?? 'unknown',
      streamPath: resolvedStreamPath,
      fileExists: json['fileExists'] as bool? ?? true,
      animeId: json['animeId'] as int?,
      episodeId: json['episodeId'] as int?,
      duration: json['duration'] as int?,
      lastPosition: json['lastPosition'] as int?,
      progress: (json['progress'] as num?)?.toDouble(),
      fileSize: json['fileSize'] as int?,
      lastWatchTime: json['lastWatchTime'] != null
          ? DateTime.tryParse(json['lastWatchTime'] as String)
          : null,
      videoHash: json['videoHash'] as String?,
    );
  }
}

class SharedRemoteScannedFolder {
  SharedRemoteScannedFolder({
    required this.path,
    required this.name,
    required this.exists,
  });

  final String path;
  final String name;
  final bool exists;

  factory SharedRemoteScannedFolder.fromJson(Map<String, dynamic> json) {
    return SharedRemoteScannedFolder(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      exists: json['exists'] as bool? ?? false,
    );
  }
}

class SharedRemoteScanStatus {
  SharedRemoteScanStatus({
    required this.isScanning,
    required this.progress,
    required this.message,
    required this.totalFilesFound,
  });

  final bool isScanning;
  final double progress;
  final String message;
  final int totalFilesFound;

  factory SharedRemoteScanStatus.fromJson(Map<String, dynamic> json) {
    return SharedRemoteScanStatus(
      isScanning: json['isScanning'] as bool? ?? false,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      message: json['message'] as String? ?? '',
      totalFilesFound: json['totalFilesFound'] as int? ?? 0,
    );
  }
}

class SharedRemoteFileEntry {
  SharedRemoteFileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.size,
    this.modifiedTime,
    this.animeName,
    this.episodeTitle,
    this.animeId,
    this.episodeId,
    this.isFromScan,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedTime;
  final String? animeName;
  final String? episodeTitle;
  final int? animeId;
  final int? episodeId;
  final bool? isFromScan;

  factory SharedRemoteFileEntry.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return SharedRemoteFileEntry(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isDirectory: json['isDirectory'] as bool? ?? false,
      size: json['size'] as int?,
      modifiedTime: json['modifiedTime'] != null
          ? DateTime.tryParse(json['modifiedTime'] as String)
          : null,
      animeName: json['animeName'] as String?,
      episodeTitle: json['episodeTitle'] as String?,
      animeId: parseInt(json['animeId']),
      episodeId: parseInt(json['episodeId']),
      isFromScan: json['isFromScan'] as bool?,
    );
  }
}
