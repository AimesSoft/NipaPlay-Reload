import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';

class HorizontalAnimeCard extends StatelessWidget {
  final String imageUrl;
  final String title;
  final double? rating;
  final bool isOnAir;
  final String? source;
  final String? summary;
  final VoidCallback onTap;

  const HorizontalAnimeCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onTap,
    this.rating,
    this.isOnAir = false,
    this.source,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 140,
        color: Colors.transparent, // Ensure hit test works
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image
            AspectRatio(
              aspectRatio: 0.7,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.hardEdge,
                child: CachedNetworkImageWidget(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  loadMode: CachedImageLoadMode.legacy,
                  memCacheWidth: 200,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Rating & Status/Source Row
                  Row(
                    children: [
                      if (rating != null && rating! > 0) ...[
                        const Icon(Ionicons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (isOnAir)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 0.5),
                          ),
                          child: const Text(
                            '放送中',
                            style: TextStyle(color: Colors.green, fontSize: 10),
                          ),
                        ),
                      if (source != null) ...[
                        if (isOnAir) const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 0.5),
                          ),
                          child: Text(
                            source!,
                            style: const TextStyle(color: Colors.blueAccent, fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Summary
                  if (summary != null && summary!.isNotEmpty)
                    Text(
                      summary!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.6)
                            : Colors.black54,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}