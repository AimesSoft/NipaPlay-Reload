import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:provider/provider.dart';

class HorizontalAnimeCard extends StatelessWidget {
  static const double detailedCardHeight = 140;
  static const double detailedCardWidth = 320;
  static const double detailedGridMaxCrossAxisExtent = 500;
  static const double detailedListHeight = detailedCardHeight + 20;

  static const double compactCardHeight = 180;
  static const double compactCardWidth = 120;
  static const double compactGridMaxCrossAxisExtent = 140;
  static const double compactListHeight = compactCardHeight + 20;

  static const double _coverAspectRatio = 0.7;
  static const double _compactTitleSpacing = 6;

  final String imageUrl;
  final String title;
  final double? rating;
  final String? source;
  final String? summary;
  final String? progress; // 新增：观看进度
  final VoidCallback onTap;

  const HorizontalAnimeCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onTap,
    this.rating,
    this.source,
    this.summary,
    this.progress,
  });

  Widget _buildCover() {
    return Container(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showSummary =
        context.watch<AppearanceSettingsProvider>().showAnimeCardSummary;

    if (!showSummary) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardHeight = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : compactCardHeight;
            final cardWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : compactCardWidth;

            return SizedBox(
              height: cardHeight,
              width: cardWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: AspectRatio(
                        aspectRatio: _coverAspectRatio,
                        child: _buildCover(),
                      ),
                    ),
                  ),
                  const SizedBox(height: _compactTitleSpacing),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: detailedCardHeight,
        color: Colors.transparent, // Ensure hit test works
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image
            AspectRatio(
              aspectRatio: _coverAspectRatio,
              child: _buildCover(),
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
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Progress Row (New)
                  if (progress != null && progress!.isNotEmpty) ...[
                    Text(
                      progress!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  // Rating & Status/Source Row
                  Row(
                    children: [
                      if (rating != null && rating! > 0) ...[
                        Icon(
                          Ionicons.star,
                          size: 14,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          rating!.toStringAsFixed(1),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (source != null) ...[
                        Text(
                          source!,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Summary
                  if (summary != null && summary!.isNotEmpty)
                    Expanded(
                      child: Text(
                        summary!,
                        maxLines: progress != null ? 2 : 3, // 如果有进度，减少一行简介空间
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.6)
                              : Colors.black54,
                          fontSize: 13,
                          height: 1.4,
                        ),
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
