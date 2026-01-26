import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';

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
    final Color tabDividerColor = isDark ? Colors.white24 : Colors.black12;

    final hasEpisodes = episodesView != null;
    final canShowTabs = !isDesktopOrTablet &&
        showTabs &&
        hasEpisodes &&
        tabController != null;

    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) {
            NipaplayWindowPositionProvider.of(context)?.onMove(details.delta);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
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
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: isDark ? Colors.white60 : Colors.black54),
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
          TabBar(
            controller: tabController,
            dividerColor: tabDividerColor,
            dividerHeight: 1.0,
            labelColor: isDark ? Colors.white : Colors.black,
            unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding:
                const EdgeInsets.only(top: 46, left: 15, right: 15),
            indicator: BoxDecoration(
              color: isDark ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(30),
            ),
            indicatorWeight: 3,
            tabs: const [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Ionicons.document_text_outline, size: 18),
                    SizedBox(width: 8),
                    Text('简介'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Ionicons.film_outline, size: 18),
                    SizedBox(width: 8),
                    Text('剧集'),
                  ],
                ),
              ),
            ],
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
