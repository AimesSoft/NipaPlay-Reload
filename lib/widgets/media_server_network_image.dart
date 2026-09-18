import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/utils/network_settings.dart';

export 'package:nipaplay/services/media_server_image_loader.dart'
    show loadMediaServerImage;

typedef MediaServerImageLoader = Future<Uint8List> Function(Uri uri);

const int _maxMemoryCachedImages = 200;

/// 字节预算：200 张未解码的 JPEG/PNG 原始字节在低端设备上也可能是几十 MB。
const int _maxMemoryCachedBytes = 12 * 1024 * 1024;

final Map<(String, MediaServerImageLoader), Future<Uint8List>> _imageByteCache =
    {};

/// 每个条目已下载完成的字节数；键被移除时同步扣减。
final Map<(String, MediaServerImageLoader), int> _imageByteSizes = {};
int _imageByteCacheBytes = 0;

void clearMediaServerImageMemoryCache() {
  _imageByteCache.clear();
  _imageByteSizes.clear();
  _imageByteCacheBytes = 0;
}

/// 移除一个条目并同步维护字节统计。
void _removeCachedImage((String, MediaServerImageLoader) key) {
  _imageByteCache.remove(key);
  final size = _imageByteSizes.remove(key);
  if (size != null) {
    _imageByteCacheBytes -= size;
    if (_imageByteCacheBytes < 0) _imageByteCacheBytes = 0;
  }
}

Future<Uint8List> _loadCachedImage(
  Uri uri,
  MediaServerImageLoader loader,
) {
  final key = (uri.toString(), loader);
  final cached = _imageByteCache[key];
  if (cached != null) {
    // 命中后重新插入，使 Map 的插入顺序等价于 LRU（Dart Map 保持插入序）。
    _imageByteCache.remove(key);
    _imageByteCache[key] = cached;
    return cached;
  }
  if (_imageByteCache.length >= _maxMemoryCachedImages) {
    _removeCachedImage(_imageByteCache.keys.first);
  }
  final completer = Completer<Uint8List>();
  final future = completer.future;
  _imageByteCache[key] = future;
  Future<Uint8List>.sync(() => loader(uri)).then(
    (bytes) {
      // 只有当条目仍在缓存里时才计入统计（可能已被预算淘汰）。
      if (identical(_imageByteCache[key], future)) {
        _imageByteSizes[key] = bytes.length;
        _imageByteCacheBytes += bytes.length;
        _enforceImageByteBudget();
      }
      completer.complete(bytes);
    },
    onError: (Object error, StackTrace stackTrace) {
      if (identical(_imageByteCache[key], future)) {
        _removeCachedImage(key);
      }
      completer.completeError(error, stackTrace);
    },
  );
  return future;
}

/// 按字节预算淘汰最久未使用的条目（保留至少一个，避免刚插入就被清掉）。
void _enforceImageByteBudget() {
  while (_imageByteCacheBytes > _maxMemoryCachedBytes &&
      _imageByteCache.length > 1) {
    final oldestKey = _imageByteCache.keys.first;
    // 未完成的条目没有字节记账，移除时不会扣减，因此循环仍会推进。
    _removeCachedImage(oldestKey);
  }
}

class MediaServerNetworkImage extends StatefulWidget {
  const MediaServerNetworkImage(
    this.uri, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.filterQuality = FilterQuality.medium,
    this.errorBuilder,
    this.loadingBuilder,
    this.loader,
    this.useMemoryCache = true,
    this.cacheWidth,
    this.cacheHeight,
  });

  final Uri uri;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final MediaServerImageLoader? loader;
  final bool useMemoryCache;

  /// 解码宽度（物理像素）。媒体服务器的海报常常是 1000px+，如果只在
  /// 80×45 的槽位里显示，按原始分辨率解码会白占几 MB 内存并拖慢主 isolate。
  final int? cacheWidth;

  /// 解码高度（物理像素），语义同 [cacheWidth]。
  final int? cacheHeight;

  @override
  State<MediaServerNetworkImage> createState() =>
      _MediaServerNetworkImageState();
}

class _MediaServerNetworkImageState extends State<MediaServerNetworkImage> {
  late Future<Uint8List> _imageBytes;

  @override
  void initState() {
    super.initState();
    _imageBytes = _load();
  }

  @override
  void didUpdateWidget(MediaServerNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.loader != widget.loader ||
        oldWidget.useMemoryCache != widget.useMemoryCache) {
      _imageBytes = _load();
    }
  }

  Future<Uint8List> _load() {
    final loader = widget.loader ?? loadNetworkImageBytes;
    if (!widget.useMemoryCache) {
      return loader(widget.uri);
    }
    return _loadCachedImage(widget.uri, loader);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _imageBytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          final image = Image.memory(
            bytes,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            filterQuality: widget.filterQuality,
            cacheWidth: widget.cacheWidth,
            cacheHeight: widget.cacheHeight,
            errorBuilder: widget.errorBuilder,
          );
          return widget.loadingBuilder?.call(context, image, null) ?? image;
        }
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(
                context,
                snapshot.error!,
                snapshot.stackTrace,
              ) ??
              const SizedBox.shrink();
        }
        return widget.loadingBuilder?.call(
              context,
              const SizedBox.shrink(),
              const ImageChunkEvent(
                cumulativeBytesLoaded: 0,
                expectedTotalBytes: null,
              ),
            ) ??
            const SizedBox.shrink();
      },
    );
  }
}

class MediaServerAwareNetworkImage extends StatelessWidget {
  const MediaServerAwareNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.filterQuality = FilterQuality.medium,
    this.errorBuilder,
    this.loadingBuilder,
    this.loader,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final MediaServerImageLoader? loader;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(url);
    if (isMediaServerImageUri(uri) ||
        NetworkSettings.isDandanplayServiceUri(
            DandanplayHttpClient.targetUri(uri))) {
      return MediaServerNetworkImage(
        uri,
        width: width,
        height: height,
        fit: fit,
        filterQuality: filterQuality,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
        loader: loader,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
      );
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}

class MediaServerAwareCachedNetworkImage extends StatelessWidget {
  const MediaServerAwareCachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.errorWidget,
    this.loader,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final MediaServerImageLoader? loader;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(imageUrl);
    if (isMediaServerImageUri(uri) ||
        NetworkSettings.isDandanplayServiceUri(
            DandanplayHttpClient.targetUri(uri))) {
      return MediaServerNetworkImage(
        uri,
        width: width,
        height: height,
        fit: fit,
        loader: loader,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        errorBuilder: (context, error, _) =>
            errorWidget?.call(context, imageUrl, error) ??
            const SizedBox.shrink(),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      errorWidget: errorWidget,
    );
  }
}

class MediaServerActorAvatar extends StatelessWidget {
  const MediaServerActorAvatar({
    super.key,
    required this.imageUrl,
    required this.size,
    required this.backgroundColor,
    required this.placeholder,
    this.loader,
  });

  final String? imageUrl;
  final double size;
  final Color backgroundColor;
  final Widget placeholder;
  final MediaServerImageLoader? loader;

  @override
  Widget build(BuildContext context) {
    final resolvedImageUrl = imageUrl?.trim();
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: backgroundColor, child: placeholder),
            if (resolvedImageUrl != null && resolvedImageUrl.isNotEmpty)
              MediaServerAwareNetworkImage(
                resolvedImageUrl,
                fit: BoxFit.cover,
                loader: loader,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}
