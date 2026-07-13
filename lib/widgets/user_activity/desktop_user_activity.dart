import 'dart:ui' show ImageFilter;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_main_tab_bar.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/widgets/user_activity/user_activity_view_model.dart';

/// NipaPlay/Fluent renderer for shared user activity data.
class DesktopUserActivity extends StatefulWidget {
  const DesktopUserActivity({super.key, required this.data});

  final UserActivityViewModel data;

  @override
  State<DesktopUserActivity> createState() => _DesktopUserActivityState();
}

class _DesktopUserActivityState extends State<DesktopUserActivity> {
  static Color get _ratingAccentColor => AppAccentColors.current;
  static const double _buttonHoverScale = 1.06;
  int _selectedIndex = 0;

  UserActivityViewModel get data => widget.data;
  bool get isLoading => data.isLoading;
  String? get error => data.error;
  List<Map<String, dynamic>> get recentWatched => data.recentWatched;
  List<Map<String, dynamic>> get favorites => data.favorites;
  List<Map<String, dynamic>> get rated => data.rated;

  Future<void> loadUserActivity() => data.onRefresh();
  void openAnimeDetail(int animeId) => data.onOpenAnimeDetail(animeId);
  String formatTime(String? value) => data.formatTime(value);
  String getFavoriteStatusText(String? status) =>
      data.favoriteStatusText(status);
  String getRatingText(int rating) => data.ratingText(rating);
  String? processImageUrl(String? url) => data.processImageUrl(url);

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final textPrimary = theme.resources.textFillColorPrimary;
    final textSecondary = theme.resources.textFillColorSecondary;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final isDarkMode = theme.brightness == Brightness.dark;
    final unselectedLabelColor = isDarkMode ? Colors.white60 : Colors.black54;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),

        // 标题和刷新按钮
        Row(
          children: [
            Text(
              context.l10n.userActivityTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const Spacer(),
            BlurButton(
              icon: Ionicons.refresh_outline,
              text: context.l10n.mediaServerRefresh,
              flatStyle: true,
              hoverScale: _buttonHoverScale,
              onTap: () {
                if (isLoading) return;
                loadUserActivity();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _DesktopActivityTab(
              label: context.l10n.userActivityTabWatchedCount(
                recentWatched.length,
              ),
              icon: Ionicons.play_circle_outline,
              selected: _selectedIndex == 0,
              selectedColor: accent,
              unselectedColor: unselectedLabelColor,
              onPressed: () => setState(() => _selectedIndex = 0),
            ),
            _DesktopActivityTab(
              label: context.l10n.userActivityTabFavoritesCount(
                favorites.length,
              ),
              icon: Ionicons.heart_outline,
              selected: _selectedIndex == 1,
              selectedColor: accent,
              unselectedColor: unselectedLabelColor,
              onPressed: () => setState(() => _selectedIndex = 1),
            ),
            _DesktopActivityTab(
              label: context.l10n.userActivityTabRatedCount(rated.length),
              icon: Ionicons.star_outline,
              selected: _selectedIndex == 2,
              selectedColor: accent,
              unselectedColor: unselectedLabelColor,
              onPressed: () => setState(() => _selectedIndex = 2),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _buildTabBody(_selectedIndex, accent, textSecondary),
        ),
      ],
    );
  }

  Widget _buildTabBody(
    int index,
    Color accent,
    Color textSecondary,
  ) {
    if (isLoading) {
      return Center(
        child: fluent.ProgressRing(
          activeColor: accent,
          strokeWidth: 2,
        ),
      );
    }

    if (error != null) {
      return _buildErrorState(textSecondary);
    }

    switch (index) {
      case 0:
        return _buildRecentWatchedList();
      case 1:
        return _buildFavoritesList();
      default:
        return _buildRatedList();
    }
  }

  Widget _buildErrorState(Color textSecondary) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          fluent.Icon(
            Ionicons.warning_outline,
            color: textSecondary,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            style: TextStyle(color: textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          BlurButton(
            icon: Ionicons.refresh_outline,
            text: context.l10n.retry,
            flatStyle: true,
            hoverScale: _buttonHoverScale,
            onTap: loadUserActivity,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentWatchedList() {
    final theme = fluent.FluentTheme.of(context);
    final textSecondary = theme.resources.textFillColorSecondary;

    if (recentWatched.isEmpty) {
      return _buildEmptyState(
        context.l10n.userActivityNoWatchedRecords,
        Ionicons.play_circle_outline,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: recentWatched.length,
      itemBuilder: (context, index) {
        final item = recentWatched[index];
        return _buildAnimeListItem(
          item: item,
          subtitle: item['lastEpisodeTitle'] != null
              ? context.l10n.userActivityWatchedEpisode(
                  item['lastEpisodeTitle'].toString(),
                )
              : context.l10n.userActivityWatchedOnly,
          trailing: item['lastWatchedTime'] != null
              ? Text(
                  formatTime(item['lastWatchedTime']),
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildFavoritesList() {
    if (favorites.isEmpty) {
      return _buildEmptyState(
        context.l10n.userActivityNoFavorites,
        Ionicons.heart_outline,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final item = favorites[index];
        final statusText = getFavoriteStatusText(item['favoriteStatus']);

        return _buildAnimeListItem(
          item: item,
          subtitle: statusText,
          trailing: item['rating'] > 0
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    fluent.Icon(
                      Ionicons.star,
                      color: _ratingAccentColor,
                      size: 14,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${item['rating']}',
                      style: TextStyle(
                        color: _ratingAccentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }

  Widget _buildRatedList() {
    if (rated.isEmpty) {
      return _buildEmptyState(
        context.l10n.userActivityNoRatings,
        Ionicons.star_outline,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rated.length,
      itemBuilder: (context, index) {
        final item = rated[index];
        return _buildAnimeListItem(
          item: item,
          subtitle: getRatingText(item['rating']),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              fluent.Icon(
                Ionicons.star,
                color: _ratingAccentColor,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${item['rating']}',
                style: TextStyle(
                  color: _ratingAccentColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnimeListItem({
    required Map<String, dynamic> item,
    required String subtitle,
    Widget? trailing,
  }) {
    return _ActivityListItem(
      item: item,
      subtitle: subtitle,
      trailing: trailing,
      onPressed: () => openAnimeDetail(item['animeId']),
      processImageUrl: processImageUrl,
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    final theme = fluent.FluentTheme.of(context);
    final textSecondary = theme.resources.textFillColorSecondary;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          fluent.Icon(
            icon,
            color: textSecondary,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityListItem extends StatefulWidget {
  final Map<String, dynamic> item;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onPressed;
  final String? Function(String?) processImageUrl;

  const _ActivityListItem({
    required this.item,
    required this.subtitle,
    this.trailing,
    required this.onPressed,
    required this.processImageUrl,
  });

  @override
  State<_ActivityListItem> createState() => _ActivityListItemState();
}

class _ActivityListItemState extends State<_ActivityListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final textPrimary = theme.resources.textFillColorPrimary;
    final textSecondary = theme.resources.textFillColorSecondary;
    final imageUrl = widget.processImageUrl(widget.item['imageUrl']);
    const coverWidth = 48.0;
    const coverHeight = 60.0;
    const coverRadius = 4.0;
    final accentColor = AppAccentColors.current;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: theme.resources.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isHovered
                ? accentColor
                : theme.resources.cardStrokeColorDefault,
            width: _isHovered ? 1.5 : 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: GestureDetector(
              onTap: widget.onPressed,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Leading
                    ClipRRect(
                      borderRadius: BorderRadius.circular(coverRadius),
                      child: imageUrl != null
                          ? Image.network(
                              imageUrl,
                              width: coverWidth,
                              height: coverHeight,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: coverWidth,
                                  height: coverHeight,
                                  color: theme.resources
                                      .cardBackgroundFillColorSecondary,
                                  child: fluent.Icon(
                                    Ionicons.image_outline,
                                    color: textSecondary,
                                    size: 20,
                                  ),
                                );
                              },
                            )
                          : Container(
                              width: coverWidth,
                              height: coverHeight,
                              color: theme
                                  .resources.cardBackgroundFillColorSecondary,
                              child: fluent.Icon(
                                Ionicons.image_outline,
                                color: textSecondary,
                                size: 20,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    // Title and Subtitle
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item['animeTitle'] ??
                                context.l10n.userActivityUnknownTitle,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Trailing
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 8),
                      widget.trailing!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopActivityTab extends StatefulWidget {
  const _DesktopActivityTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onPressed;

  @override
  State<_DesktopActivityTab> createState() => _DesktopActivityTabState();
}

class _DesktopActivityTabState extends State<_DesktopActivityTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color =
        widget.selected ? widget.selectedColor : widget.unselectedColor;
    const labelStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _hovered ? 1.04 : 1,
          duration: const Duration(milliseconds: 140),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    fluent.Icon(widget.icon, size: 17, color: color),
                    const SizedBox(width: 6),
                    Text(widget.label,
                        style: labelStyle.copyWith(color: color)),
                  ],
                ),
                const SizedBox(height: 8),
                NipaplayLabelTabIndicator(
                  label: widget.label,
                  labelStyle: labelStyle,
                  selected: widget.selected,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
