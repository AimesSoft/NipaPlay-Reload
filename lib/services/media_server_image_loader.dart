import 'dart:async';
import 'dart:typed_data';

import 'package:nipaplay/services/dandanplay_http_client.dart' as http;
import 'package:nipaplay/services/media_server_transport.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';

final Map<String, Uri> _mediaServerBaseUris = {};

void setMediaServerBaseUrl(String serverKey, String? baseUrl) {
  final uri = baseUrl == null ? null : Uri.tryParse(baseUrl);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    _mediaServerBaseUris.remove(serverKey);
    return;
  }
  _mediaServerBaseUris[serverKey] = uri;
}

bool isMediaServerImageUri(Uri uri) {
  if (!_mediaServerBaseUris.values.any((base) => _isWithinBase(base, uri))) {
    return false;
  }
  final segments = uri.pathSegments
      .map((segment) => segment.toLowerCase())
      .toList(growable: false);
  for (var index = 0; index + 2 < segments.length; index += 1) {
    if (segments[index] == 'items' && segments[index + 2] == 'images') {
      return true;
    }
  }
  return false;
}

bool _isWithinBase(Uri base, Uri candidate) {
  if (!_sameOrigin(base, candidate)) {
    return false;
  }
  final baseSegments = base.pathSegments.where((segment) => segment.isNotEmpty);
  final candidateSegments = candidate.pathSegments.iterator;
  for (final baseSegment in baseSegments) {
    if (!candidateSegments.moveNext() ||
        candidateSegments.current.toLowerCase() != baseSegment.toLowerCase()) {
      return false;
    }
  }
  return true;
}

bool _sameOrigin(Uri left, Uri right) {
  return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      left.port == right.port;
}

/// 单次图片下载的超时。
///
/// 图片下载此前没有任何超时：一条卡死的连接会让 [ImageCacheManager]
/// 里对应 URL 的加载条目永远挂在 _loading 上，FutureBuilder 永远等不到
/// 数据或错误，自动重试也不会触发——大屏模式的封面墙"加载一部分后突然
/// 全部停止"正是这个机制。
const Duration _imageFetchTimeout = Duration(seconds: 20);

/// 图片下载并发上限。
///
/// 大屏模式的封面墙一次会发起几十个请求（hybrid 模式每张图还有两条通道）。
/// 无上限的并发在电视盒子上会撞上路由器/NAT 连接表与套接字上限，表现为
/// "加载一部分后突然停止"；这里排队限流，让封面墙分批稳定填充。
const int _maxConcurrentImageFetches = 6;

int _activeImageFetches = 0;
final List<Completer<void>> _imageFetchQueue = <Completer<void>>[];

Future<T> _runWithImageFetchSlot<T>(Future<T> Function() action) async {
  if (_activeImageFetches >= _maxConcurrentImageFetches) {
    final waiter = Completer<void>();
    _imageFetchQueue.add(waiter);
    await waiter.future;
  }
  _activeImageFetches++;
  try {
    return await action();
  } finally {
    _activeImageFetches--;
    if (_imageFetchQueue.isNotEmpty) {
      _imageFetchQueue.removeAt(0).complete();
    }
  }
}

Future<Uint8List> loadNetworkImageBytes(Uri originalUri) {
  return _runWithImageFetchSlot(() => _loadNetworkImageBytesUncapped(originalUri));
}

Future<Uint8List> _loadNetworkImageBytesUncapped(Uri originalUri) async {
  final requestUri = WebRemoteAccessService.proxyUri(originalUri);
  if (isMediaServerImageUri(originalUri)) {
    return loadMediaServerImage(requestUri);
  }

  // 带超时的一次性客户端：超时后 close() 会强制断开底层连接并释放套接字，
  // 保证并发槽位总能被归还。
  final client = http.DandanplayHttpClient();
  try {
    final response = await http.Response.fromStream(
      await client
          .send(http.Request('GET', requestUri))
          .timeout(_imageFetchTimeout),
    ).timeout(_imageFetchTimeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Image request failed: HTTP ${response.statusCode}',
        requestUri,
      );
    }
    return response.bodyBytes;
  } on TimeoutException {
    throw http.ClientException(
      'Image request timed out after ${_imageFetchTimeout.inSeconds}s',
      requestUri,
    );
  } finally {
    client.close();
  }
}

Future<Uint8List> loadMediaServerImage(Uri uri) async {
  final transport = await MediaServerTransport.fromStoredSettings();
  try {
    final response = await transport.send(
      http.Request('GET', uri),
      timeout: const Duration(seconds: 20),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Media-server image request failed: HTTP ${response.statusCode}',
        uri,
      );
    }
    return response.bodyBytes;
  } finally {
    transport.close();
  }
}
