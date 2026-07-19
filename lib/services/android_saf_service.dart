import 'package:flutter/services.dart';

class AndroidSafFileEntry {
  const AndroidSafFileEntry({
    required this.relativePath,
    required this.uri,
    required this.name,
    required this.size,
    required this.modifiedMillis,
    required this.fileHash,
  });

  final String relativePath;
  final String uri;
  final String name;
  final int size;
  final int modifiedMillis;
  final String fileHash;

  factory AndroidSafFileEntry.fromMap(Map<dynamic, dynamic> map) {
    return AndroidSafFileEntry(
      relativePath: map['relativePath'] as String,
      uri: map['uri'] as String,
      name: map['name'] as String,
      size: (map['size'] as num?)?.toInt() ?? 0,
      modifiedMillis: (map['modifiedMillis'] as num?)?.toInt() ?? 0,
      fileHash: map['fileHash'] as String,
    );
  }
}

class AndroidSafFileMetadata {
  const AndroidSafFileMetadata({
    required this.uri,
    required this.name,
    required this.size,
    required this.contentHash,
  });

  final String uri;
  final String name;
  final int size;
  final String contentHash;

  factory AndroidSafFileMetadata.fromMap(Map<dynamic, dynamic> map) {
    return AndroidSafFileMetadata(
      uri: map['uri'] as String,
      name: map['name'] as String,
      size: (map['size'] as num?)?.toInt() ?? 0,
      contentHash: map['contentHash'] as String,
    );
  }
}

class AndroidSafService {
  AndroidSafService._();

  static const MethodChannel _channel = MethodChannel('nipaplay/android_saf');

  static bool isSafUri(String value) {
    return value.toLowerCase().startsWith('content://');
  }

  /// 将 Android SAF tree URI 转换为文件系统路径。仅转换 primary（内部存储）：
  /// content://com.android.externalstorage.documents/tree/primary%3AMovies
  /// -> /storage/emulated/0/Movies。SD/OTG 的 tree URI 无法可靠转路径，原样返回。
  /// app 有 MANAGE_EXTERNAL_STORAGE，primary 路径可直接用 io.File/io.Directory
  /// 访问，恢复与普通文件路径的兼容（浏览/播放/扫描全走原路径）。
  static String tryConvertToFilePath(String uri) {
    if (!isSafUri(uri)) return uri;
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return uri;
    final segments = parsed.pathSegments;
    if (segments.length < 2 || segments[0] != 'tree') return uri;
    // pathSegments 已是解码后的（%3A -> :），不要再 decodeComponent——双重解码
    // 会在文件夹名含 % 时抛 "Illegal percent"（pathSegments 把 %25 解码成 %，
    // 再 decodeComponent 遇到孤立的 % 就 FormatException）。
    final decoded = segments[1];
    final colonIdx = decoded.indexOf(':');
    if (colonIdx < 0) return uri;
    final storageId = decoded.substring(0, colonIdx);
    final relativePath = decoded.substring(colonIdx + 1);
    if (storageId == 'primary') {
      return '/storage/emulated/0/$relativePath';
    }
    // SD/USB OTG: /storage/<storageId>/<relativePath>。
    // MANAGE_EXTERNAL_STORAGE 理论上覆盖 /storage/ 下所有卷，但 USB OTG 实际
    // 可访问性因 OEM/ROM 而异（某些定制 ROM 即使 MANAGE granted 也拒绝真实路径）。
    // 返回路径让调用方 existsSync 验证，不可访问则保留 content:// 走 SAF。
    return '/storage/$storageId/$relativePath';
  }

  static Future<String?> pickDirectory() async {
    return _channel.invokeMethod<String>('pickDirectory');
  }

  static Future<bool> canAccessTree(String treeUri) async {
    final result = await _channel.invokeMethod<bool>(
      'canAccessTree',
      {'treeUri': treeUri},
    );
    return result == true;
  }

  static Future<List<AndroidSafFileEntry>> scanDirectory(
    String treeUri,
  ) async {
    final rawEntries = await _channel.invokeMethod<List<dynamic>>(
      'scanDirectory',
      {'treeUri': treeUri},
    );
    return (rawEntries ?? const <dynamic>[])
        .cast<Map<dynamic, dynamic>>()
        .map(AndroidSafFileEntry.fromMap)
        .toList(growable: false);
  }

  static Future<AndroidSafFileMetadata> getFileMetadata(String uri) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getFileMetadata',
      {'uri': uri},
    );
    if (raw == null) {
      throw PlatformException(
        code: 'SAF_METADATA_EMPTY',
        message: 'Android SAF metadata result is empty.',
      );
    }
    return AndroidSafFileMetadata.fromMap(raw);
  }
}
