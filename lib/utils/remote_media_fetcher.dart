import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';

/// 获取远程媒体文件的基础信息（文件名/大小）并拉取前16MB原始字节。
///
/// 弹弹play的识别接口要求提供精确的文件大小和前16MB数据的MD5值。
/// 对于 WebDAV/HTTP 资源，我们在这里统一处理多种服务器行为：
/// - 尝试 HEAD 拿 `Content-Length`
/// - 使用 Range=0-16MB-1 拉取首段；如服务器回 200，则主动截断
/// - 若仍无法确定大小，回退到 WebDAV PROPFIND Depth=0
/// - 自动携带 Basic 认证（来自 URL 的 userInfo）并绕过系统代理（对内网地址）
class RemoteMediaFetcher {
  /// 弹弹play要求的最大哈希长度：前16MB。
  static const int maxHashLength = 16 * 1024 * 1024;

  /// 请求超时时间
  static const Duration defaultTimeout = Duration(seconds: 20);

  /// 下载远程媒体的元信息及前16MB数据。
  static Future<RemoteMediaHead> fetchHead(Uri originalUri) async {
    final sanitizedUri = _buildSanitizedUri(originalUri);
    final headers = <String, String>{
      'User-Agent': 'NipaPlay/1.0',
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
    };

    final authHeader = _buildBasicAuthHeader(originalUri);
    if (authHeader != null) {
      headers['Authorization'] = authHeader;
    }

    final client = IOClient(_createHttpClientForUri(originalUri));
    try {
      int? fileSize;

      // 尝试 HEAD 获取 Content-Length
      try {
        final headRequest = http.Request('HEAD', sanitizedUri)
          ..headers.addAll(headers)
          ..persistentConnection = false;
        final headStreamed = await client.send(headRequest).timeout(defaultTimeout);
        final headResponse = await http.Response.fromStream(headStreamed);

        if (headResponse.statusCode >= 200 && headResponse.statusCode < 400) {
          fileSize = _parseContentLength(headResponse.headers);
        } else {
          debugPrint('RemoteMediaFetcher: HEAD 请求失败 (HTTP ${headResponse.statusCode})');
        }
      } catch (e) {
        debugPrint('RemoteMediaFetcher: HEAD 请求异常: $e');
      }

      // 使用 Range=0-16MB 拉取首段
      Uint8List headBytes = Uint8List(0);
      try {
        final rangeRequest = http.Request('GET', sanitizedUri)
          ..headers.addAll(headers)
          ..headers['Range'] = 'bytes=0-${maxHashLength - 1}'
          ..persistentConnection = false;

        final rangeStreamed = await client.send(rangeRequest).timeout(defaultTimeout);

        if (rangeStreamed.statusCode == 401 || rangeStreamed.statusCode == 403) {
          throw HttpException('远程服务器拒绝访问 (HTTP ${rangeStreamed.statusCode})');
        }

        if (rangeStreamed.statusCode != 200 && rangeStreamed.statusCode != 206) {
          debugPrint('RemoteMediaFetcher: Range 请求返回 ${rangeStreamed.statusCode}，尝试读取但可能不完整');
        }

        fileSize ??= _parseContentRange(rangeStreamed.headers) ?? rangeStreamed.contentLength;
        headBytes = await _readLimitedBytes(rangeStreamed.stream, maxHashLength);
      } catch (e) {
        debugPrint('RemoteMediaFetcher: Range 请求异常: $e');
      }

      if (headBytes.isEmpty) {
        throw Exception('无法获取远程视频的前16MB数据');
      }

      // 若长度仍未知，尝试 WebDAV PROPFIND
      if (fileSize == null || fileSize <= 0) {
        try {
          fileSize = await _fetchFileSizeViaPropfind(client, sanitizedUri, headers);
        } catch (e) {
          debugPrint('RemoteMediaFetcher: PROPFIND 获取文件大小异常: $e');
        }
      }

      if (fileSize == null || fileSize <= 0) {
        throw Exception('无法确定远程视频的实际大小');
      }

      final expectedBytes = math.min(fileSize, maxHashLength);
      final hasFullRequiredData = headBytes.length >= expectedBytes;

      final fileName = _extractFileNameFromUri(originalUri);
      final hash = _computeHash(headBytes, expectedBytes);

      if (!hasFullRequiredData) {
        throw Exception('仅获取到 ${headBytes.length} 字节，无法满足识别所需的 $expectedBytes 字节');
      }

      return RemoteMediaHead(
        fileName: fileName,
        fileSize: fileSize,
        headBytes: headBytes,
        hash: hash,
      );
    } finally {
      client.close();
    }
  }

  static String _computeHash(Uint8List bytes, int expectedLength) {
    if (bytes.length < expectedLength) {
      return md5.convert(bytes).toString();
    }
    return md5.convert(bytes.sublist(0, expectedLength)).toString();
  }

  static Future<Uint8List> _readLimitedBytes(Stream<List<int>> stream, int limit) async {
    final completer = Completer<Uint8List>();
    final builder = BytesBuilder(copy: false);
    StreamSubscription<List<int>>? subscription;

    subscription = stream.listen((chunk) {
      if (builder.length >= limit) {
        return;
      }

      final remaining = limit - builder.length;
      if (chunk.length <= remaining) {
        builder.add(chunk);
        if (builder.length >= limit) {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.complete(builder.takeBytes());
          }
        }
      } else {
        builder.add(chunk.sublist(0, remaining));
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.complete(builder.takeBytes());
        }
      }
    }, onError: (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }, onDone: () {
      if (!completer.isCompleted) {
        completer.complete(builder.takeBytes());
      }
    }, cancelOnError: true);

    return completer.future;
  }

  static int? _parseContentLength(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-length') {
        return int.tryParse(entry.value);
      }
    }
    return null;
  }

  static int? _parseContentRange(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-range') {
        final match = RegExp(r'bytes\s+\d+-\d+/(\d+|\*)').firstMatch(entry.value);
        if (match != null) {
          final total = match.group(1);
          if (total != null && total != '*') {
            return int.tryParse(total);
          }
        }
      }
    }
    return null;
  }

  static Future<int?> _fetchFileSizeViaPropfind(
    IOClient client,
    Uri uri,
    Map<String, String> baseHeaders,
  ) async {
    final headers = Map<String, String>.from(baseHeaders);
    headers['Depth'] = '0';
    headers['Content-Type'] = 'application/xml; charset="utf-8"';

    final request = http.Request('PROPFIND', uri)
      ..headers.addAll(headers)
      ..persistentConnection = false
      ..body = '''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:getcontentlength/>
  </D:prop>
</D:propfind>''';

    final response = await client.send(request).timeout(defaultTimeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final responseBody = await response.stream.bytesToString();
      return _extractFileSizeFromPropfindXml(responseBody);
    }
    return null;
  }

  static int? _extractFileSizeFromPropfindXml(String xmlBody) {
    try {
      final document = XmlDocument.parse(xmlBody);
      for (final element in document.findAllElements('getcontentlength')) {
        final text = element.innerText.trim();
        if (text.isNotEmpty) {
          final value = int.tryParse(text);
          if (value != null) {
            return value;
          }
        }
      }
    } catch (e) {
      debugPrint('RemoteMediaFetcher: 解析 PROPFIND XML 失败: $e');
    }
    return null;
  }

  static String _extractFileNameFromUri(Uri uri) {
    if (uri.pathSegments.isNotEmpty) {
      for (var i = uri.pathSegments.length - 1; i >= 0; i--) {
        final segment = uri.pathSegments[i];
        if (segment.isNotEmpty) {
          return segment;
        }
      }
    }
    if (uri.path.isNotEmpty) {
      final lastSlash = uri.path.lastIndexOf('/');
      return lastSlash >= 0 ? uri.path.substring(lastSlash + 1) : uri.path;
    }
    return 'video';
  }

  static String? _buildBasicAuthHeader(Uri uri) {
    if (uri.userInfo.isEmpty) {
      return null;
    }

    final separatorIndex = uri.userInfo.indexOf(':');
    String username;
    String password;
    if (separatorIndex >= 0) {
      username = uri.userInfo.substring(0, separatorIndex);
      password = uri.userInfo.substring(separatorIndex + 1);
    } else {
      username = uri.userInfo;
      password = '';
    }

    username = Uri.decodeComponent(username);
    password = Uri.decodeComponent(password);

    final credentials = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }

  static HttpClient _createHttpClientForUri(Uri uri) {
    final httpClient = HttpClient();
    httpClient.userAgent = 'NipaPlay/1.0';
    httpClient.autoUncompress = false;
    if (_shouldBypassProxy(uri.host)) {
      httpClient.findProxy = (_) => 'DIRECT';
    }
    return httpClient;
  }

  static bool _shouldBypassProxy(String host) {
    if (host.isEmpty) {
      return false;
    }

    if (host == 'localhost' || host == '127.0.0.1') {
      return true;
    }

    final ip = InternetAddress.tryParse(host);
    if (ip != null) {
      if (ip.type == InternetAddressType.IPv4) {
        final bytes = ip.rawAddress;
        if (bytes.length == 4) {
          final first = bytes[0];
          final second = bytes[1];
          if (first == 10) return true;
          if (first == 127) return true;
          if (first == 192 && second == 168) return true;
          if (first == 172 && second >= 16 && second <= 31) return true;
        }
      } else if (ip.type == InternetAddressType.IPv6) {
        if (ip.isLoopback) {
          return true;
        }
        final firstByte = ip.rawAddress.isNotEmpty ? ip.rawAddress[0] : 0;
        if (firstByte & 0xfe == 0xfc) {
          return true; // fc00::/7 Unique Local Address
        }
      }
    } else {
      if (host.endsWith('.local')) {
        return true;
      }
    }

    return false;
  }

  static Uri _buildSanitizedUri(Uri source) {
    return Uri(
      scheme: source.scheme,
      host: source.host,
      port: source.hasPort ? source.port : null,
      pathSegments: source.pathSegments,
      query: source.hasQuery ? source.query : null,
      fragment: source.fragment.isEmpty ? null : source.fragment,
    );
  }
}

class RemoteMediaHead {
  final String fileName;
  final int fileSize;
  final Uint8List headBytes;
  final String hash;

  const RemoteMediaHead({
    required this.fileName,
    required this.fileSize,
    required this.headBytes,
    required this.hash,
  });
}
