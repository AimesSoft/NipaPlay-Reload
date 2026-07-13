import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class NipaplayAnimeDetailLayout extends StatelessWidget {
  const NipaplayAnimeDetailLayout({
    super.key,
    required this.title,
    required this.infoView,
    this.subtitle,
    this.sourceLabel,
    this.headerActions,
    this.onClose,
    this.tabController,
    this.showTabs = true,
    this.enableAnimation = false,
    this.isDesktopOrTablet = false,
    this.episodesView,
    this.desktopView,
    this.sourceLabelUseContainer = true,
  });

  final String title;
  final String? subtitle;
  final String? sourceLabel;
  final List<Widget>? headerActions;
  final VoidCallback? onClose;
  final TabController? tabController;
  final bool showTabs;
  final bool enableAnimation;
  final bool isDesktopOrTablet;
  final Widget infoView;
  final Widget? episodesView;
  final Widget? desktopView;
  final bool sourceLabelUseContainer;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black;
    final Color iconColor = isDark ? Colors.white70 : Colors.black87;
    final bottomSheetScope = CupertinoBottomSheetScope.maybeOf(context);
    final phoneTopInset = isDesktopOrTablet
        ? 0.0
        : (bottomSheetScope?.contentTopInset ?? 0) +
            (bottomSheetScope?.contentTopSpacing ?? 0);
    final titleStyle = isDesktopOrTablet
        ? Theme.of(context).textTheme.titleLarge?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
            )
        : Theme.of(context).textTheme.titleMedium?.copyWith(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            );

    final hasEpisodes = episodesView != null;
    final canShowTabs =
        !isDesktopOrTablet && showTabs && hasEpisodes && tabController != null;

    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) {
            NipaplayWindowPositionProvider.of(context)?.onMove(details.delta);
          },
          onDoubleTap: () {
            NipaplayWindowPositionProvider.of(context)?.onToggleDisplayMode();
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12 + phoneTopInset, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: titleStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (subtitle != null &&
                    subtitle!.isNotEmpty &&
                    subtitle != title)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.white60 : Colors.black54),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (sourceLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: sourceLabelUseContainer
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: (isDark ? Colors.white : Colors.black)
                                  .withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: (isDark ? Colors.white : Colors.black)
                                      .withOpacity(0.12),
                                  width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Ionicons.cloud_outline,
                                    size: 14, color: iconColor),
                                const SizedBox(width: 4),
                                Text(
                                  sourceLabel!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: iconColor),
                                ),
                              ],
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Ionicons.cloud_outline,
                                  size: 14, color: iconColor),
                              const SizedBox(width: 4),
                              Text(
                                sourceLabel!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: iconColor),
                              ),
                            ],
                          ),
                  ),
                if (headerActions != null) ...headerActions!,
              ],
            ),
          ),
        ),
        if (canShowTabs)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: AnimatedBuilder(
                animation: tabController!,
                builder: (context, _) => AdaptiveSegmentedControl(
                  labels: const ['简介', '剧集'],
                  selectedIndex: tabController!.index,
                  onValueChanged: (index) {
                    if (tabController!.index != index) {
                      tabController!.animateTo(index);
                    }
                  },
                ),
              ),
            ),
          ),
        Expanded(
          child: isDesktopOrTablet && desktopView != null
              ? desktopView!
              : (!hasEpisodes || tabController == null)
                  ? infoView
                  : SwitchableView(
                      controller: tabController,
                      currentIndex: tabController!.index,
                      enableAnimation: enableAnimation,
                      physics: enableAnimation
                          ? const PageScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      onPageChanged: (index) {
                        if (tabController!.index != index) {
                          tabController!.animateTo(index);
                        }
                      },
                      children: [
                        infoView,
                        episodesView!,
                      ],
                    ),
        ),
      ],
    );
  }
}
