
// lib/utils/file_hash.dart
// 提供计算文件 Hash 的工具函数

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/src/rust/api/media_probe.dart' as rust_media;
import 'package:nipaplay/src/rust/rust_init.dart';


const int defaultFileHeadHashBytes = 16 * 1024 * 1024;

/// 计算文件前 [maxBytes] 字节的 MD5 (默认前 16MiB)
Future<String> computeFileHeadMd5(String filePath, { int maxBytes = defaultFileHeadHashBytes }) async {

  final trimmedPath = filePath.trim();
  if (trimmedPath.isEmpty) {
    throw ArgumentError.value(filePath, 'filePath', '文件路径不能为空');
  }
  if (maxBytes <= 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'maxBytes 必须大于 0');
  }
  if (kIsWeb) {
    throw UnsupportedError('Web 平台不支持本地文件路径哈希');
  }

  final file = File(trimmedPath);
  if (!file.existsSync()) {
    throw FileSystemException('文件不存在', trimmedPath);
  }

  try {
    await ensureRustInitialized();
    return await rust_media.hashFileHead(
      filePath: file.path,
      maxBytes: maxBytes,
    );
  } catch (error) {
    final message = error.toString();
    if (message.contains('Failed to load dynamic library') && message.contains('librust_lib_nipaplay.so')) {
      debugPrint('computeFileHeadMd5: Rust 库加载失败, 回退 Dart');
    } else {
      debugPrint('computeFileHeadMd5: Rust 计算失败, 回退 Dart: $error');
    }
  }

  final bytes = await file.openRead(0, maxBytes).expand((chunk) => chunk).toList();
  return md5.convert(bytes).toString();
}
