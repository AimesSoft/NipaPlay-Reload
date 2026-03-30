import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BigScreenMediaImage extends StatelessWidget {
  const BigScreenMediaImage({
    super.key,
    required this.imagePath,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.movie_outlined,
  });

  final String imagePath;
  final BoxFit fit;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final trimmedPath = imagePath.trim();
    if (trimmedPath.isEmpty) {
      return _ImageFallback(icon: fallbackIcon);
    }

    final lowerPath = trimmedPath.toLowerCase();
    if (lowerPath.startsWith('http://') || lowerPath.startsWith('https://')) {
      return CachedNetworkImageWidget(
        imageUrl: trimmedPath,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        loadMode: CachedImageLoadMode.legacy,
        fadeDuration: Duration.zero,
        errorBuilder: (_, __) => _ImageFallback(icon: fallbackIcon),
      );
    }

    if (trimmedPath.startsWith('assets/')) {
      return Image.asset(
        trimmedPath,
        fit: fit,
        errorBuilder: (_, __, ___) => _ImageFallback(icon: fallbackIcon),
      );
    }

    if (kIsWeb) {
      return _ImageFallback(icon: fallbackIcon);
    }

    return Image.file(
      File(trimmedPath),
      fit: fit,
      errorBuilder: (_, __, ___) => _ImageFallback(icon: fallbackIcon),
    );
  }
}

class BigScreenHistoryThumbnail extends StatelessWidget {
  const BigScreenHistoryThumbnail({
    super.key,
    required this.item,
    this.fallbackCoverPath,
  });

  final WatchHistoryItem item;
  final String? fallbackCoverPath;

  @override
  Widget build(BuildContext context) {
    final thumbnailPath = item.thumbnailPath?.trim() ?? '';
    if (thumbnailPath.isNotEmpty) {
      final lowerPath = thumbnailPath.toLowerCase();
      if (lowerPath.startsWith('http://') || lowerPath.startsWith('https://')) {
        return CachedNetworkImage(
          imageUrl: thumbnailPath,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorWidget: (_, __, ___) =>
              _buildDefaultThumbnail(context, fallbackCoverPath?.trim() ?? ''),
        );
      }

      if (!kIsWeb) {
        final thumbnailFile = File(thumbnailPath);
        if (thumbnailFile.existsSync()) {
          int modifiedMs = 0;
          try {
            modifiedMs =
                thumbnailFile.lastModifiedSync().millisecondsSinceEpoch;
          } catch (_) {}

          final cacheKey = '${item.filePath}_${thumbnailPath}_$modifiedMs';
          return FutureBuilder<Uint8List>(
            key: ValueKey(cacheKey),
            future: thumbnailFile.readAsBytes(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(color: Colors.white10);
              }
              if (snapshot.hasError ||
                  !snapshot.hasData ||
                  snapshot.data!.isEmpty) {
                return _buildDefaultThumbnail(
                  context,
                  fallbackCoverPath?.trim() ?? '',
                );
              }
              return Image.memory(
                snapshot.data!,
                key: ValueKey(cacheKey),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => _buildDefaultThumbnail(
                    context, fallbackCoverPath?.trim() ?? ''),
              );
            },
          );
        }
      }
    }

    final coverPath = fallbackCoverPath?.trim() ?? '';
    return _buildDefaultThumbnail(context, coverPath);
  }

  Widget _buildDefaultThumbnail(BuildContext context, String coverPath) {
    if (item.animeId != null && item.animeId! > 0) {
      return FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (context, snapshot) {
          String? imageUrl;
          if (snapshot.hasData) {
            imageUrl = snapshot.data!
                .getString('media_library_image_url_${item.animeId}');
          }

          if (imageUrl != null && imageUrl.isNotEmpty) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Colors.white),
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorWidget: (_, __, ___) =>
                        const _ImageFallback(icon: Icons.videocam_outlined),
                  ),
                ),
                Container(color: Colors.black.withValues(alpha: 0.2)),
                const Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    color: Colors.white54,
                    size: 32,
                  ),
                ),
              ],
            );
          }

          if (coverPath.isNotEmpty) {
            return _buildCoverFallback(coverPath);
          }
          return const _ImageFallback(icon: Icons.videocam_outlined);
        },
      );
    }

    if (coverPath.isNotEmpty) {
      return _buildCoverFallback(coverPath);
    }
    return const _ImageFallback(icon: Icons.videocam_outlined);
  }

  Widget _buildCoverFallback(String coverPath) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BigScreenMediaImage(
          imagePath: coverPath,
          fit: BoxFit.cover,
          fallbackIcon: Icons.videocam_outlined,
        ),
        Container(
          color: Colors.black.withValues(alpha: 0.25),
        ),
        const Center(
          child: Icon(
            Icons.play_circle_outline,
            color: Colors.white70,
            size: 34,
          ),
        ),
      ],
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: colorScheme.onSurfaceVariant,
        size: 30,
      ),
    );
  }
}
