import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
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

    final Color accentColor = CupertinoTheme.of(context).primaryColor;

    final String title;
    final String description;

    if (isSystem) {
      title = context.l10n.followSystem;
      description = context.l10n.appearancePreviewFollowSystemDescription;
    } else if (isDark) {
      title = context.l10n.darkMode;
      description = context.l10n.appearancePreviewDarkDescription;
    } else {
      title = context.l10n.lightMode;
      description = context.l10n.appearancePreviewLightDescription;
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
            context.l10n.appearancePreviewTitle,
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
