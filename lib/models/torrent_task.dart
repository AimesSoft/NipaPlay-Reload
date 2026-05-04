import 'dart:convert';

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

  double get progress {
    if (totalBytes <= 0) return 0;
    return (progressBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isPaused => state == 'paused';

  bool get isActive => state == 'live' || state == 'initializing';

  bool get hasError => state == 'error' || (error?.isNotEmpty ?? false);

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
