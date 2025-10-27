import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 液态玻璃风格的媒体库卡片，用于展示远程服务器中的分类库。
enum MediaServerBrand { jellyfin, emby }

class CupertinoGlassLibraryCard extends StatelessWidget {
  const CupertinoGlassLibraryCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.itemCount,
    required this.accentColor,
    required this.onTap,
    this.showOverlay = true,
    this.serverBrand = MediaServerBrand.jellyfin,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final int? itemCount;
  final Color accentColor;
  final VoidCallback onTap;
  final bool showOverlay;
  final MediaServerBrand serverBrand;

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.of(context).brightness ??
        MediaQuery.maybeOf(context)?.platformBrightness ??
        Brightness.light;

    final overlayColors = brightness == Brightness.dark
        ? [
            CupertinoColors.black.withValues(alpha: 0.55),
            CupertinoColors.black.withValues(alpha: 0.35),
          ]
        : [
            CupertinoColors.white.withValues(alpha: 0.65),
            CupertinoColors.white.withValues(alpha: 0.35),
          ];

    final borderColor = brightness == Brightness.dark
        ? CupertinoColors.white.withValues(alpha: 0.15)
        : CupertinoColors.white.withValues(alpha: 0.35);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned.fill(child: _buildBackground()),
              if (showOverlay)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: overlayColors,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderColor, width: 0.6),
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderColor, width: 0.6),
                    ),
                  ),
                ),
              Positioned(
                top: 16,
                left: 16,
                child: _buildBadge(context),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: _buildTexts(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildFallbackBackground(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return AnimatedOpacity(
            opacity: progress.expectedTotalBytes == null
                ? 0.6
                : progress.cumulativeBytesLoaded /
                    (progress.expectedTotalBytes ?? 1),
            duration: const Duration(milliseconds: 200),
            child: child,
          );
        },
      );
    }
    return _buildFallbackBackground();
  }

  Widget _buildFallbackBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.35),
            accentColor.withValues(alpha: 0.15),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            serverBrand == MediaServerBrand.jellyfin
                ? 'assets/jellyfin.svg'
                : 'assets/emby.svg',
            width: 14,
            height: 14,
            colorFilter: const ColorFilter.mode(CupertinoColors.white, BlendMode.srcIn),
          ),
          if (itemCount != null) ...[
            const SizedBox(width: 6),
            Text(
              '共$itemCount 条目',
              style: TextStyle(
                fontSize: 12,
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTexts(BuildContext context) {
    final titleStyle = const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: CupertinoColors.white,
      height: 1.15,
    );

    final subtitleStyle = TextStyle(
      fontSize: 14,
      color: CupertinoColors.white.withValues(alpha: 0.8),
      height: 1.25,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: subtitleStyle,
          ),
        ],
      ],
    );
  }
}
