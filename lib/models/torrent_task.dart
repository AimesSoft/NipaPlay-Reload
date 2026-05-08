import 'dart:convert';

import 'package:path/path.dart' as p;

class TorrentTaskFile {
  const TorrentTaskFile({
    required this.index,
    required this.name,
    required this.components,
    required this.length,
    required this.included,
  });

  static const Set<String> videoExtensions = {
    '.mp4',
    '.m4v',
    '.mkv',
    '.mov',
    '.avi',
    '.flv',
    '.ts',
    '.mpeg',
    '.mpg',
    '.webm',
  };

  final int index;
  final String name;
  final List<String> components;
  final int length;
  final bool included;

  String get displayName {
    if (components.isNotEmpty) {
      return components.join('/');
    }
    return name;
  }

  String get fileName {
    final display = displayName;
    return display.isEmpty ? name : p.basename(display);
  }

  bool get isVideo =>
      videoExtensions.contains(p.extension(fileName).toLowerCase());

  factory TorrentTaskFile.fromMap(int index, Map<String, dynamic> map) {
    final rawComponents = map['components'];
    return TorrentTaskFile(
      index: index,
      name: TorrentTask._asString(map['name'], fallback: '未命名文件'),
      components: rawComponents is List
          ? rawComponents.map((value) => value.toString()).toList()
          : const <String>[],
      length: TorrentTask._asInt(map['length']),
      included: map['included'] != false,
    );
  }
}

class TorrentTask {
  const TorrentTask({
    required this.id,
    required this.infoHash,
    required this.name,
    required this.outputFolder,
    required this.state,
    required this.progressBytes,
    required this.uploadedBytes,
    required this.totalBytes,
    required this.finished,
    required this.downloadSpeedBytesPerSecond,
    required this.uploadSpeedBytesPerSecond,
    required this.error,
    this.files = const <TorrentTaskFile>[],
  });

  final int id;
  final String infoHash;
  final String name;
  final String outputFolder;
  final String state;
  final int progressBytes;
  final int uploadedBytes;
  final int totalBytes;
  final bool finished;
  final int downloadSpeedBytesPerSecond;
  final int uploadSpeedBytesPerSecond;
  final String? error;
  final List<TorrentTaskFile> files;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (progressBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isPaused => state == 'paused';

  bool get isActive => state == 'live' || state == 'initializing';

  bool get hasError => state == 'error' || (error?.isNotEmpty ?? false);

  String get autoScanKey => '$infoHash|$outputFolder';

  String get displayState {
    if (hasError) return '错误';
    if (finished) return '已完成';
    switch (state) {
      case 'initializing':
        return '初始化';
      case 'live':
        return '下载中';
      case 'paused':
        return '已暂停';
      default:
        return state.isEmpty ? '等待中' : state;
    }
  }

  factory TorrentTask.fromMap(Map<String, dynamic> map) {
    final stats = map['stats'] is Map<String, dynamic>
        ? map['stats'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final live = stats['live'] is Map<String, dynamic>
        ? stats['live'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return TorrentTask(
      id: _asInt(map['id']),
      infoHash: _asString(map['info_hash']),
      name: _asString(map['name'], fallback: '未命名任务'),
      outputFolder: _asString(map['output_folder']),
      state: _asString(stats['state']),
      progressBytes: _asInt(stats['progress_bytes']),
      uploadedBytes: _asInt(stats['uploaded_bytes']),
      totalBytes: _asInt(stats['total_bytes']),
      finished: stats['finished'] == true,
      downloadSpeedBytesPerSecond:
          _speedBytes(live['download_speed'] as Map<String, dynamic>?),
      uploadSpeedBytesPerSecond:
          _speedBytes(live['upload_speed'] as Map<String, dynamic>?),
      error: stats['error']?.toString(),
      files: _filesFromMap(map),
    );
  }

  TorrentTask copyWith({
    List<TorrentTaskFile>? files,
  }) {
    return TorrentTask(
      id: id,
      infoHash: infoHash,
      name: name,
      outputFolder: outputFolder,
      state: state,
      progressBytes: progressBytes,
      uploadedBytes: uploadedBytes,
      totalBytes: totalBytes,
      finished: finished,
      downloadSpeedBytesPerSecond: downloadSpeedBytesPerSecond,
      uploadSpeedBytesPerSecond: uploadSpeedBytesPerSecond,
      error: error,
      files: files ?? this.files,
    );
  }

  static List<TorrentTask> listFromJson(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return const <TorrentTask>[];
    final torrents = decoded['torrents'];
    if (torrents is! List) return const <TorrentTask>[];
    return torrents
        .whereType<Map<String, dynamic>>()
        .map(TorrentTask.fromMap)
        .toList();
  }

  static TorrentTask? detailsFromJson(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;
    return TorrentTask.fromMap(decoded);
  }

  static List<TorrentTaskFile> _filesFromMap(Map<String, dynamic> map) {
    final rawFiles = map['files'];
    if (rawFiles is! List) return const <TorrentTaskFile>[];
    final files = <TorrentTaskFile>[];
    for (var index = 0; index < rawFiles.length; index++) {
      final rawFile = rawFiles[index];
      if (rawFile is Map<String, dynamic>) {
        files.add(TorrentTaskFile.fromMap(index, rawFile));
      }
    }
    return files;
  }

  static int _speedBytes(Map<String, dynamic>? speed) {
    if (speed == null) return 0;
    final mbps = _asDouble(speed['mbps']);
    return (mbps * 1024 * 1024).round();
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static String _asString(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}
