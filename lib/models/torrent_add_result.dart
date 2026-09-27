import 'dart:convert';

class TorrentAddResult {
  const TorrentAddResult(
      {required this.id,
      required this.alreadyExists,
      required this.outputFolder});

  final int id;
  final bool alreadyExists;
  final String outputFolder;

  factory TorrentAddResult.fromJson(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    return TorrentAddResult(
      id: (data['id'] as num).toInt(),
      alreadyExists: data['already_exists'] == true,
      outputFolder: data['output_folder'] as String,
    );
  }

  String get message =>
      alreadyExists ? '任务已存在，保留原状态和保存位置：$outputFolder' : '已添加下载任务';
}
