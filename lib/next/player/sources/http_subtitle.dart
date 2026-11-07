import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';

/// Cache an explicitly supplied HTTP subtitle, without media-library clients.
/// The cache filename and display-name preference stay compatible with Classic.
Future<String> cacheHttpSubtitle(Uri uri) async {
  final name = p.posix.basename(uri.path),
      extension = p.extension(uri.path).toLowerCase();
  if (extension == '.idx') throw StateError('VobSub 索引缺少同名 .sub 文件');
  final root = await StorageService.getAppStorageDirectory();
  final hash = sha1
      .convert(utf8.encode('shared:${uri.replace(userInfo: '', fragment: '')}'))
      .toString();
  var base = p
      .setExtension(name, '')
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .trim();
  if (base.isEmpty) base = 'subtitle';
  if (base.length > 80) base = base.substring(0, 80);
  final file = File(p.join(root.path, 'remote_subtitles',
      '$base-${hash.substring(0, 8)}$extension'));
  if (!await file.exists() || await file.length() == 0) {
    await file.parent.create(recursive: true);
    final staging = File('${file.path}.downloading');
    final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 45),
        headers: {'user-agent': 'NipaPlay', 'accept': '*/*'}));
    try {
      await dio.download(uri.replace(userInfo: '').toString(), staging.path);
      if (await staging.length() == 0) throw StateError('字幕返回空内容');
      await staging.rename(file.path);
    } finally {
      dio.close(force: true);
      if (await staging.exists()) await staging.delete();
    }
  }
  if (extension == '.sub' && isVobSubBinaryFile(file.path)) {
    throw StateError('VobSub 位图字幕缺少同名 .idx 文件');
  }
  final prefs = await SharedPreferences.getInstance();
  const key = 'remote_subtitle_display_names_v1';
  final names =
      (jsonDecode(prefs.getString(key) ?? '{}') as Map).cast<String, dynamic>();
  names[file.path] = name;
  if (names.length > 200) {
    for (final key in names.keys.take(names.length - 100).toList()) {
      names.remove(key);
    }
  }
  await prefs.setString(key, jsonEncode(names));
  return file.path;
}
