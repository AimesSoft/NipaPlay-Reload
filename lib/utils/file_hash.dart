
// lib/utils/file_hash.dart
// 提供计算文件 Hash 的工具函数

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/src/rust/api/media_probe.dart' as rust_media;
import 'package:nipaplay/src/rust/rust_init.dart';


const int defaultFileHeadHashBytes = 16 * 1024 * 1024;

Uint8List decodeHex(String value, {int? expectedBytes}) {
  final normalized = value.trim();
  if (normalized.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) {
    throw const FormatException('无效的十六进制字符串');
  }
  if (expectedBytes != null && normalized.length != expectedBytes * 2) {
    throw FormatException('十六进制字符串必须表示 $expectedBytes 字节');
  }
  return Uint8List.fromList(
    List<int>.generate(
      normalized.length ~/ 2,
      (index) => int.parse(
        normalized.substring(index * 2, index * 2 + 2),
        radix: 16,
      ),
    ),
  );
}

/// 将字节数组转换为小写十六进制字符串, 与 [decodeHex] 互为逆操作
String encodeHex(Uint8List bytes, { bool uppercase = false }) {
  return bytes.map((b) {
    final hex = b.toRadixString(16).padLeft(2, '0');
    return uppercase ? hex.toUpperCase() : hex;
  }).join();
}

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

/// 通过 HTTP Range 请求读取远程文件前 [maxBytes] 字节并计算 MD5 (默认前 16MiB)
/// 同时返回远程文件的总大小
///
/// [uri] 不应包含用户名/密码 (userInfo), 鉴权信息请通过 [headers] 传入
///
/// 内部会分阶段打印耗时 (连接/响应头, 下载, MD5 计算), 方便定位耗时瓶颈:
/// 通常瓶颈在网络下载阶段 (受限于服务器/网络带宽), 而非本地计算.
Future<({String hash, int size})> computeRemoteFileHeadMd5(
  Uri uri, {
  int maxBytes = defaultFileHeadHashBytes,
  Map<String, String>? headers,
}) async {

  if (maxBytes <= 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'maxBytes 必须大于 0');
  }
  if (kIsWeb) {
    throw UnsupportedError('Web 平台不支持计算远程文件哈希');
  }

  final stopwatch = Stopwatch()..start();
  final client = http.Client();
  try {
    final request = http.Request('GET', uri);
    if (headers != null) request.headers.addAll(headers);
    request.headers['Range'] = 'bytes=0-${maxBytes - 1}';

    final response = await client.send(request);
    final connectMs = stopwatch.elapsedMilliseconds;
    if (response.statusCode >= 400) {
      throw HttpException(
        '请求远程文件失败: HTTP ${response.statusCode}',
        uri: uri,
      );
    }

    final totalSize = _parseRemoteFileSize(response);

    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      final remaining = maxBytes - builder.length;
      if (remaining <= 0) break;
      builder.add(chunk.length > remaining ? chunk.sublist(0, remaining) : chunk);
      if (builder.length >= maxBytes) break;
    }
    final bytes = builder.takeBytes();
    final downloadMs = stopwatch.elapsedMilliseconds - connectMs;

    final hash = md5.convert(bytes).toString();
    final hashMs = stopwatch.elapsedMilliseconds - connectMs - downloadMs;

    debugPrint(
      '[RemoteHash] $uri: 建立连接/响应头 ${connectMs}ms, 下载 ${bytes.length}B 用时 ${downloadMs}ms, '
      'MD5 计算 ${hashMs}ms (下载速度约 ${(bytes.length / 1024 / 1024) / (downloadMs <= 0 ? 1 : downloadMs / 1000)} MiB/s)',
    );

    return (hash: hash, size: totalSize);
  } finally {
    client.close();
  }
}

/// 从响应头中解析远程文件总大小, 优先读取 Content-Range, 其次 Content-Length
int _parseRemoteFileSize(http.StreamedResponse response) {

  final contentRange = response.headers['content-range'];
  if (contentRange != null) {
    final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
    final total = match == null ? null : int.tryParse(match.group(1)!);
    if (total != null) return total;
  }

  final contentLength = response.headers['content-length'];
  if (contentLength != null) {
    final length = int.tryParse(contentLength);
    if (length != null) return length;
  }

  throw const HttpException('无法从响应头中获取远程文件大小');
}

/// 从 URI 的 userInfo (user:password) 构造 HTTP Basic Auth 请求头
/// userInfo 为空时返回 null
Map<String, String>? basicAuthHeadersFromUri(Uri uri) {
  if (uri.userInfo.isEmpty) return null;
  final credentials = base64Encode(utf8.encode(uri.userInfo));
  return <String, String>{'Authorization': 'Basic $credentials'};
}

/// 移除 URI 中的 userInfo (user:password), 避免鉴权信息随请求 URI 一同发送
Uri stripUriUserInfo(Uri uri) {
  return uri.userInfo.isEmpty ? uri : uri.replace(userInfo: '');
}

/// 判断给定路径是否为远程 http(s) 文件地址 (例如 WebDAV 文件地址), 不是则返回 null
Uri? tryParseRemoteFileUri(String filePath) {
  final uri = Uri.tryParse(filePath);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri;
}
