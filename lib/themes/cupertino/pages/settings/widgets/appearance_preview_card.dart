import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;

class CupertinoAppearancePreviewCard extends StatelessWidget {
  final ThemeMode mode;

  const CupertinoAppearancePreviewCard({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    final bool isDark = mode == ThemeMode.dark;
    final bool isSystem = mode == ThemeMode.system;

    final Color resolvedBackground = CupertinoDynamicColor.resolve(
      isDark
          ? CupertinoColors.darkBackgroundGray
          : CupertinoColors.systemGroupedBackground,
      context,
    );

    final Color accentColor = isDark
        ? CupertinoColors.systemYellow
        : CupertinoColors.activeBlue;

    final String title;
    final String description;

    if (isSystem) {
      title = '跟随系统';
      description = '根据系统外观自动切换浅色或深色模式。';
    } else if (isDark) {
      title = '深色模式';
      description = '使用偏暗的配色方案，适合夜间或弱光环境。';
    } else {
      title = '浅色模式';
      description = '使用明亮的配色方案，适合日间或高亮环境。';
    }

    return Container(
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '效果预览',
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(
                isDark
                    ? CupertinoColors.systemGrey5
                    : CupertinoColors.systemBackground,
                context,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Icon(
                  isSystem
                      ? CupertinoIcons.circle_lefthalf_fill
                      : (isDark
                          ? CupertinoIcons.moon_stars_fill
                          : CupertinoIcons.sun_max_fill),
                  color: accentColor,
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .copyWith(
                              fontSize: 13,
                              color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemGrey,
                                context,
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
