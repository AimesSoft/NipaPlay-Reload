import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';

/// Only library poster entries pass this tag to the detail route. Other
/// entry points leave it null and never participate in a shared transition.
Object mediaLibraryPosterHeroTag(Object source, int animeId) =>
    ('media-library-poster', source, animeId);

class MediaDetailPosterHero extends StatelessWidget {
  const MediaDetailPosterHero({super.key, required this.child, this.tag});
  final Object? tag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (tag == null) return child;
    return Hero(
      tag: tag!,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: (context, animation, direction, from, to) {
        // Keep the already displayed library rendition during the flight.
        // The larger destination decode can finish independently from disk.
        final source =
            (direction == HeroFlightDirection.push ? from : to).widget as Hero;
        return source.child;
      },
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class MediaDetailPoster extends StatelessWidget {
  const MediaDetailPoster({super.key, required this.url, this.heroTag});
  final String? url;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final value = url?.trim() ?? '';
    const fallback = ColoredBox(
        color: Color(0xFF232733),
        child: Center(
            child:
                Icon(Icons.movie_outlined, color: Colors.white38, size: 36)));
    Widget image = fallback;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      image = CachedNetworkImageWidget(
        imageUrl: value,
        fit: BoxFit.cover,
        memCacheWidth: 640,
        fadeDuration: Duration.zero,
        errorBuilder: (_, __) => fallback,
      );
    } else if (!kIsWeb && value.isNotEmpty) {
      image = Image.file(File(value),
          fit: BoxFit.cover,
          cacheWidth: 640,
          errorBuilder: (_, __, ___) => fallback);
    }
    return MediaDetailPosterHero(
        tag: heroTag,
        child:
            ClipRRect(borderRadius: BorderRadius.circular(12), child: image));
  }
}
