import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';

class NipaplayAnimeDetailScaffold extends StatelessWidget {
  const NipaplayAnimeDetailScaffold({
    super.key,
    required this.child,
    this.backgroundImageUrl,
  });

  final Widget child;
  final String? backgroundImageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.3),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.of(context).padding.top + 20,
          20,
          20,
        ),
        child: Stack(
          children: [
            if (backgroundImageUrl != null && backgroundImageUrl!.isNotEmpty)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: CachedNetworkImageWidget(
                    imageUrl: backgroundImageUrl!,
                    fit: BoxFit.cover,
                    shouldCompress: false,
                    loadMode: CachedImageLoadMode.hybrid,
                  ),
                ),
              ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: Colors.black.withOpacity(0.2),
                ),
              ),
            ),
            GlassmorphicContainer(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 15,
              blur: 25,
              alignment: Alignment.center,
              border: 0.5,
              linearGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color.fromARGB(255, 219, 219, 219).withOpacity(0.1),
                  const Color.fromARGB(255, 208, 208, 208).withOpacity(0.1),
                ],
                stops: const [0.1, 1],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.15),
                ],
              ),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final hasEpisodes = episodesView != null;
    final canShowTabs = !isDesktopOrTablet &&
        showTabs &&
        hasEpisodes &&
        tabController != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
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
                        ?.copyWith(color: Colors.white60),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (sourceLabel != null)
                Container(
                  margin: const EdgeInsets.only(right: 8.0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Ionicons.cloud_outline,
                          size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        sourceLabel!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              if (headerActions != null) ...headerActions!,
              IconButton(
                icon: const Icon(
                  Ionicons.close_circle_outline,
                  color: Colors.white70,
                  size: 28,
                ),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        if (canShowTabs)
          TabBar(
            controller: tabController,
            dividerColor: const Color.fromARGB(59, 255, 255, 255),
            dividerHeight: 3.0,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding:
                const EdgeInsets.only(top: 46, left: 15, right: 15),
            indicator: BoxDecoration(
              color: Colors.white,
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
