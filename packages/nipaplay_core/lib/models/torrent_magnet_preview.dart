import 'dart:convert';

import 'package:path/path.dart' as p;

class TorrentMagnetPreviewFile {
  const TorrentMagnetPreviewFile({
    required this.index,
    required this.path,
    required this.length,
  });

  final int index;
  final String path;
  final int length;

  String get name => p.basename(path);

  factory TorrentMagnetPreviewFile.fromMap(Map<String, dynamic> map) {
    return TorrentMagnetPreviewFile(
      index: _asInt(map['index']),
      path: _asString(map['path'], fallback: '未命名文件'),
      length: _asInt(map['length']),
    );
  }
}

class TorrentMagnetPreview {
  const TorrentMagnetPreview({
    required this.name,
    required this.suggestedFolderName,
    required this.totalSize,
    required this.files,
  });

  final String name;
  final String suggestedFolderName;
  final int totalSize;
  final List<TorrentMagnetPreviewFile> files;

  factory TorrentMagnetPreview.fromJson(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      return const TorrentMagnetPreview(
        name: '未命名任务',
        suggestedFolderName: '',
        totalSize: 0,
        files: <TorrentMagnetPreviewFile>[],
      );
    }

    final rawFiles = decoded['files'];
    return TorrentMagnetPreview(
      name: _asString(decoded['name'], fallback: '未命名任务'),
      suggestedFolderName: _asString(decoded['suggested_folder_name']),
      totalSize: _asInt(decoded['total_size']),
      files: rawFiles is List
          ? rawFiles
              .whereType<Map<String, dynamic>>()
              .map(TorrentMagnetPreviewFile.fromMap)
              .toList(growable: false)
          : const <TorrentMagnetPreviewFile>[],
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _asString(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}
