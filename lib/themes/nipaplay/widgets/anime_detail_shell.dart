import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';

class NipaplayAnimeDetailScaffold extends StatefulWidget {
  const NipaplayAnimeDetailScaffold({
    super.key,
    required this.child,
    this.backgroundImageUrl,
    this.blurBackground = false,
    this.onClose,
  });

  final Widget child;
  final String? backgroundImageUrl;
  final bool blurBackground;
  final VoidCallback? onClose;

  @override
  State<NipaplayAnimeDetailScaffold> createState() => _NipaplayAnimeDetailScaffoldState();
}

class _NipaplayAnimeDetailScaffoldState extends State<NipaplayAnimeDetailScaffold> {
  Offset _offset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: textColor,
          displayColor: textColor,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          child: Stack(
            children: [
              Center(
                child: Transform.translate(
                  offset: _offset,
                  child: GestureDetector(
                    onTap: () {}, // 阻止点击弹窗内容时触发关闭
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 850,
                        maxHeight: MediaQuery.of(context).size.height * 0.8,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          MediaQuery.of(context).padding.top + 20,
                          20,
                          20,
                        ),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              if (widget.backgroundImageUrl != null &&
                                  widget.backgroundImageUrl!.isNotEmpty)
                                Positioned.fill(
                                  child: ImageFiltered(
                                    imageFilter: widget.blurBackground
                                        ? ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40)
                                        : ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                                    child: Opacity(
                                      opacity: isDark ? 0.25 : 0.35,
                                      child: CachedNetworkImageWidget(
                                        imageUrl: widget.backgroundImageUrl!,
                                        fit: BoxFit.cover,
                                        shouldCompress: false,
                                        loadMode: CachedImageLoadMode.hybrid,
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        bgColor.withOpacity(0.1),
                                        bgColor.withOpacity(0.4),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              DefaultTextStyle(
                                style: TextStyle(color: textColor),
                                child: _PositionProvider(
                                  onMove: (delta) {
                                    setState(() {
                                      _offset += delta;
                                    });
                                  },
                                  child: widget.child,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 内部私有类用于在组件树中传递拖动逻辑
class _PositionProvider extends InheritedWidget {
  final Function(Offset delta) onMove;

  const _PositionProvider({
    required this.onMove,
    required super.child,
  });

  static _PositionProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_PositionProvider>();
  }

  @override
  bool updateShouldNotify(_PositionProvider oldWidget) => false;
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
            _PositionProvider.of(context)?.onMove(details.delta);
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
                Container(
                  margin: const EdgeInsets.only(right: 8.0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: (isDark ? Colors.white : Colors.black).withOpacity(0.12),
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
