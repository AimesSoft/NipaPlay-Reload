import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart' as http;
import 'package:nipaplay_core/services/media_server_transport.dart';
import 'package:nipaplay_core/services/web_remote_access_service.dart';
import 'package:nipaplay_core/utils/network_settings.dart';

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

/// 判断封面 URL 是否落在 Bangumi 官方图床/API 域上。
///
/// 用户填了 Bangumi 镜像后，API 请求会走镜像，但封面字节此前始终直连官方
/// 域——国内/受限网络下官方域不可达就是整片封面裂图（镜像白填）。这里把
/// 官方域识别出来，好让下载时优先改走镜像。
bool _isBangumiOfficialImageUri(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return false;
  if (host == 'api.bgm.tv' || host == 'bgm.tv' || host == 'next.bgm.tv') {
    return true;
  }
  // 静态图床：lain.bgm.tv / *.bgm.tv（如 lain.bgm-proxy-*.pages.dev 不适用，
  // 那是镜像自己的域，本来就能直连）。
  return host.endsWith('.bgm.tv');
}

/// 把 Bangumi 官方域的封面 URL 重写到用户配置的镜像域。
///
/// 镜像（如 bgm-proxy-*.pages.dev）同时代理 API 与 /pic/ 静态图床，所以
/// 只需换 host（保留端口与 path+query）即可；官方域直连失败时正是靠这一
/// 步把图片请求救回来。
Future<Uri> _bangumiMirrorUri(Uri original) async {
  try {
    final server = await NetworkSettings.getBangumiServer();
    if (server.isEmpty) return original;
    final mirror = Uri.tryParse(server);
    if (mirror == null || mirror.host.isEmpty) return original;
    if (mirror.host.toLowerCase() == original.host.toLowerCase()) {
      return original;
    }
    return original.replace(
      scheme: mirror.scheme,
      host: mirror.host,
      port: mirror.hasPort ? mirror.port : null,
    );
  } catch (_) {
    return original;
  }
}

/// 判断封面 URL 是否落在 TMDB 官方图床上。
///
/// 弹弹play 的电影/剧集条目（imageUrl）直接给 image.tmdb.org 地址，该域
/// 在国内/受限网络下 TLS 握手即被重置（Connection reset by peer），表现为
/// 整片封面裂图。这里把官方域识别出来，好让下载时优先改走用户配置的镜像。
bool _isTmdbOfficialImageUri(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return false;
  // image.tmdb.org 是唯一图床域；themoviedb.org 的 www/media 子域对 /t/p/
  // 路径只做 301 重定向，最终仍落回 image.tmdb.org，改写它们没有意义。
  return host == 'image.tmdb.org' || host.endsWith('.tmdb.org');
}

/// 把 TMDB 官方图床的封面 URL 重写到用户配置的镜像域。
///
/// 镜像按原路径反向代理图床（如自建 Cloudflare Pages/Worker），所以只需
/// 换 host（保留端口与 path+query）即可。
Future<Uri> _tmdbMirrorUri(Uri original) async {
  try {
    final server = await NetworkSettings.getTmdbImageServer();
    if (server.isEmpty) return original;
    final mirror = Uri.tryParse(server);
    if (mirror == null || mirror.host.isEmpty) return original;
    if (mirror.host.toLowerCase() == original.host.toLowerCase()) {
      return original;
    }
    return original.replace(
      scheme: mirror.scheme,
      host: mirror.host,
      port: mirror.hasPort ? mirror.port : null,
    );
  } catch (_) {
    return original;
  }
}

Future<Uint8List> _loadNetworkImageBytesUncapped(Uri originalUri) async {
  final requestUri = WebRemoteAccessService.proxyUri(originalUri);
  if (isMediaServerImageUri(originalUri)) {
    return loadMediaServerImage(requestUri);
  }

  // Bangumi 官方域的封面优先走用户配置的镜像，失败再回落原地址。
  // 顺序很重要：官方域在受限网络下往往是"连不上"而不是"慢"，若先试官方
  // 域会白白吃掉一个 20s 超时和一个并发槽。
  final bool canUseMirror =
      _isBangumiOfficialImageUri(originalUri) && !kIsWeb;
  if (canUseMirror) {
    final mirrorUri = await _bangumiMirrorUri(originalUri);
    if (mirrorUri != originalUri) {
      try {
        return await _fetchImageBytes(mirrorUri);
      } catch (e) {
        debugPrint(
            '[ImageLoader] 镜像取图失败，回退原地址: $mirrorUri -> $originalUri ($e)');
      }
    }
  }

  // TMDB 官方图床同策略：镜像优先，失败回落原地址（TLS 重置虽快，但持续
  // 打一个被封的域没有意义，且每次都占一个并发槽）。
  final bool canUseTmdbMirror =
      _isTmdbOfficialImageUri(originalUri) && !kIsWeb;
  if (canUseTmdbMirror) {
    final mirrorUri = await _tmdbMirrorUri(originalUri);
    if (mirrorUri != originalUri) {
      try {
        return await _fetchImageBytes(mirrorUri);
      } catch (e) {
        debugPrint(
            '[ImageLoader] TMDB镜像取图失败，回退原地址: $mirrorUri -> $originalUri ($e)');
      }
    }
  }

  return _fetchImageBytes(requestUri);
}

Future<Uint8List> _fetchImageBytes(Uri uri) async {
  // 带超时的一次性客户端：超时后 close() 会强制断开底层连接并释放套接字，
  // 保证并发槽位总能被归还。
  final client = http.DandanplayHttpClient();
  try {
    final response = await http.Response.fromStream(
      await client
          .send(http.Request('GET', uri))
          .timeout(_imageFetchTimeout),
    ).timeout(_imageFetchTimeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Image request failed: HTTP ${response.statusCode}',
        uri,
      );
    }
    return response.bodyBytes;
  } on TimeoutException {
    throw http.ClientException(
      'Image request timed out after ${_imageFetchTimeout.inSeconds}s',
      uri,
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
