import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';

export 'package:nipaplay/services/media_server_image_loader.dart'
    show loadMediaServerImage;

typedef MediaServerImageLoader = Future<Uint8List> Function(Uri uri);

const int _maxMemoryCachedImages = 200;
final Map<(String, MediaServerImageLoader), Future<Uint8List>> _imageByteCache =
    {};

void clearMediaServerImageMemoryCache() {
  _imageByteCache.clear();
}

Future<Uint8List> _loadCachedImage(
  Uri uri,
  MediaServerImageLoader loader,
) {
  final key = (uri.toString(), loader);
  final cached = _imageByteCache[key];
  if (cached != null) {
    return cached;
  }
  if (_imageByteCache.length >= _maxMemoryCachedImages) {
    _imageByteCache.remove(_imageByteCache.keys.first);
  }
  final completer = Completer<Uint8List>();
  final future = completer.future;
  _imageByteCache[key] = future;
  Future<Uint8List>.sync(() => loader(uri)).then(
    completer.complete,
    onError: (Object error, StackTrace stackTrace) {
      if (identical(_imageByteCache[key], future)) {
        _imageByteCache.remove(key);
      }
      completer.completeError(error, stackTrace);
    },
  );
  return future;
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
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final MediaServerImageLoader? loader;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(url);
    if (isMediaServerImageUri(uri)) {
      return MediaServerNetworkImage(
        uri,
        width: width,
        height: height,
        fit: fit,
        filterQuality: filterQuality,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
        loader: loader,
      );
    }
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
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
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final MediaServerImageLoader? loader;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(imageUrl);
    if (isMediaServerImageUri(uri)) {
      return MediaServerNetworkImage(
        uri,
        width: width,
        height: height,
        fit: fit,
        loader: loader,
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
