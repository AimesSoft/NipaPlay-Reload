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
