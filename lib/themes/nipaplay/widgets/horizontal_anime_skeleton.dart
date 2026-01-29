import 'package:flutter/material.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:provider/provider.dart';

class HorizontalAnimeSkeleton extends StatefulWidget {
  const HorizontalAnimeSkeleton({super.key});

  @override
  State<HorizontalAnimeSkeleton> createState() => _HorizontalAnimeSkeletonState();
}

class _HorizontalAnimeSkeletonState extends State<HorizontalAnimeSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
    final highlightColor = isDark ? Colors.white24 : Colors.black.withOpacity(0.1);
    final showSummary =
        context.watch<AppearanceSettingsProvider>().showAnimeCardSummary;
    final cardWidth = showSummary
        ? HorizontalAnimeCard.detailedCardWidth
        : HorizontalAnimeCard.compactCardWidth;
    final cardHeight = showSummary
        ? HorizontalAnimeCard.detailedCardHeight
        : HorizontalAnimeCard.compactCardHeight;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        if (!showSummary) {
          const double coverAspectRatio = 0.7;
          const double compactTitleHeight = 32;
          const double compactTitleSpacing = 6;
          final coverHeight =
              cardHeight - compactTitleHeight - compactTitleSpacing;
          final coverWidth = coverHeight * coverAspectRatio;
          return Opacity(
            opacity: _animation.value,
            child: Container(
              width: cardWidth,
              height: cardHeight,
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: coverWidth,
                    height: coverHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: coverWidth,
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: highlightColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: cardWidth,
            height: cardHeight,
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧封面图占位
                AspectRatio(
                  aspectRatio: 0.7,
                  child: Container(
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // 右侧文字缓冲占位
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      // 标题条
                      Container(
                        width: double.infinity,
                        height: 18,
                        decoration: BoxDecoration(
                          color: highlightColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 评分/来源小条
                      Container(
                        width: 80,
                        height: 14,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 简介条 1
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 简介条 2
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 简介条 3 (较短)
                      Container(
                        width: 120,
                        height: 12,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
