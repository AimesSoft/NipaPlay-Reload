import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/background_with_blur.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/platform_utils.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class CustomScaffold extends StatefulWidget {
  final List<Widget> pages;
  final List<Widget> tabPage;
  final bool pageIsHome;
  final bool shouldShowAppBar;
  final TabController? tabController;
  final bool useLargeScreenLayout;

  const CustomScaffold({
    super.key,
    required this.pages,
    required this.tabPage,
    required this.pageIsHome,
    required this.shouldShowAppBar,
    this.tabController,
    this.useLargeScreenLayout = false,
  });

  @override
  State<CustomScaffold> createState() => _CustomScaffoldState();
}

class _CustomScaffoldState extends State<CustomScaffold> {
  int? _lastTabIndex;
  String? _lastAppBarOverlayLogSignature;

  bool get _macOSHdrTransparentUnderlayEnabled {
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        Platform.environment['NIPAPLAY_MACOS_HDR_TRANSPARENT_FLUTTER'] != '0' &&
        Platform.environment['NIPAPLAY_MACOS_HDR_USE_APPKIT_VIEW'] != '1' &&
        Platform.environment['NIPAPLAY_DISABLE_MACOS_WINDOW_OVERLAY'] != '1';
  }

  void _handlePageChangedBySwitchableView(int index) {
    if (widget.tabController != null && widget.tabController!.index != index) {
      widget.tabController!.animateTo(index);
    }
  }

  @override
  void initState() {
    super.initState();
    _attachTabController(widget.tabController);
  }

  @override
  void didUpdateWidget(CustomScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController) {
      _detachTabController(oldWidget.tabController);
      _attachTabController(widget.tabController);
    }
  }

  @override
  void dispose() {
    _detachTabController(widget.tabController);
    super.dispose();
  }

  void _attachTabController(TabController? controller) {
    if (controller == null) {
      return;
    }
    _lastTabIndex = controller.index;
    controller.addListener(_handleTabControllerTick);
  }

  void _detachTabController(TabController? controller) {
    controller?.removeListener(_handleTabControllerTick);
  }

  void _handleTabControllerTick() {
    final controller = widget.tabController;
    if (controller == null) {
      return;
    }
    final currentIndex = controller.index;
    if (_lastTabIndex == currentIndex) {
      return;
    }
    _lastTabIndex = currentIndex;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tabController == null) {
      return const Center(
        child: Text("Error: TabController not provided to CustomScaffold"),
      );
    }

    final bool isDesktopOrTablet = globals.isDesktopOrTablet;
    final bool useLargeScreenLayout =
        widget.useLargeScreenLayout &&
        widget.pageIsHome &&
        isDesktopOrTablet &&
        widget.shouldShowAppBar &&
        widget.tabPage.isNotEmpty;
    const enableAnimation = true;

    final currentIndex = widget.tabController!.index;
    final preloadIndices = widget.pageIsHome
        ? List<int>.generate(
            widget.pages.length,
            (i) => i,
          ).where((i) => i != 1).toList()
        : const <int>[];

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bool hasVideo = context.select<VideoPlayerState, bool>(
      (videoState) => videoState.hasVideo,
    );
    final bool hasNativeVideoSurface = context.select<VideoPlayerState, bool>(
      (videoState) => videoState.player.prefersPlatformVideoSurface,
    );
    final Rect? videoUnderlayRect = context.select<VideoPlayerState, Rect?>(
      (videoState) => videoState.macOSWindowHostedVideoRect,
    );
    final bool useVideoUnderlay =
        _macOSHdrTransparentUnderlayEnabled &&
        hasNativeVideoSurface &&
        widget.pageIsHome &&
        currentIndex == 1 &&
        hasVideo;
    final bool showTabDivider =
        widget.pageIsHome && widget.tabController?.index == 1 && hasVideo;
    final Color tabDividerColor = isDarkMode ? Colors.white24 : Colors.black12;
    final appBarOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
    );
    _logAppBarOverlayStyle(
      isDarkMode: isDarkMode,
      overlayStyle: appBarOverlayStyle,
    );

    final switchableContent = SwitchableView(
      enableAnimation: enableAnimation,
      keepAlive: true,
      preloadIndices: preloadIndices,
      currentIndex: currentIndex,
      physics: const PageScrollPhysics(),
      onPageChanged: _handlePageChangedBySwitchableView,
      children: widget.pages
          .map((page) => RepaintBoundary(child: page))
          .toList(),
    );

    final scaffold = Scaffold(
      primary: false,
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: false,
      appBar: widget.shouldShowAppBar &&
              widget.tabPage.isNotEmpty &&
              !useLargeScreenLayout
          ? AppBar(
              toolbarHeight: !widget.pageIsHome && !isDesktopOrTablet
                  ? 100
                  : isDesktopOrTablet
                  ? 20
                  : 60,
              leading: widget.pageIsHome
                  ? null
                  : IconButton(
                      icon: const Icon(Ionicons.chevron_back_outline),
                      color: isDarkMode ? Colors.white : Colors.black,
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: appBarOverlayStyle,
              bottom: _LogoTabBar(
                tabBar: TabBar(
                  controller: widget.tabController,
                  isScrollable: true,
                  tabs: widget.tabPage,
                  labelColor: const Color(0xFFFF2E55),
                  unselectedLabelColor: isDarkMode
                      ? Colors.white60
                      : Colors.black54,
                  labelPadding: const EdgeInsets.only(bottom: 15.0),
                  tabAlignment: TabAlignment.start,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  dividerColor: showTabDivider
                      ? tabDividerColor
                      : Colors.transparent,
                  dividerHeight: 3.0,
                  indicator: const _CustomTabIndicator(
                    indicatorHeight: 3.0,
                    indicatorColor: Color(0xFFFF2E55),
                    radius: 30.0,
                  ),
                  indicatorSize: TabBarIndicatorSize.label,
                ),
              ),
            )
          : null,
      body: TabControllerScope(
        controller: widget.tabController!,
        enabled: true,
        child: useLargeScreenLayout
            ? _buildLargeScreenLayout(
                currentIndex: currentIndex,
                isDarkMode: isDarkMode,
                content: switchableContent,
              )
            : switchableContent,
      ),
    );

    return BackgroundWithBlur(
      transparentCutout: useVideoUnderlay ? videoUnderlayRect : null,
      child: scaffold,
    );
  }

  Widget _buildLargeScreenLayout({
    required int currentIndex,
    required bool isDarkMode,
    required Widget content,
  }) {
    const Color activeColor = Color(0xFFFF2E55);
    final Color inactiveColor = isDarkMode ? Colors.white60 : Colors.black54;
    final mediaPadding = MediaQuery.of(context).padding;
    final double topInset = globals.isDesktop ? 50 : mediaPadding.top + 14;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NipaplaySidePanel(
          isDarkMode: isDarkMode,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: widget.tabPage.length,
            itemBuilder: (context, index) {
              return NipaplaySidePanelItem(
                isSelected: currentIndex == index,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () {
                  if (widget.tabController!.index != index) {
                    widget.tabController!.animateTo(index);
                  }
                },
                child: _stripOuterTabPadding(widget.tabPage[index]),
              );
            },
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              topInset,
              14,
              14 + mediaPadding.bottom,
            ),
            child: content,
          ),
        ),
      ],
    );
  }

  Widget _stripOuterTabPadding(Widget tabWidget) {
    if (tabWidget is Padding && tabWidget.child != null) {
      return tabWidget.child!;
    }
    return tabWidget;
  }

  void _logAppBarOverlayStyle({
    required bool isDarkMode,
    required SystemUiOverlayStyle overlayStyle,
  }) {
    final signature = [
      isDarkMode.toString(),
      overlayStyle.statusBarIconBrightness?.name ?? 'null',
      overlayStyle.statusBarBrightness?.name ?? 'null',
    ].join('|');
    if (signature == _lastAppBarOverlayLogSignature) {
      return;
    }
    _lastAppBarOverlayLogSignature = signature;

    debugPrint(
      '[SystemUI][AppBar] '
      'isDark=$isDarkMode, '
      'icon=${overlayStyle.statusBarIconBrightness?.name}, '
      'ios=${overlayStyle.statusBarBrightness?.name}',
    );
  }
}

class NipaplaySidePanel extends StatelessWidget {
  const NipaplaySidePanel({
    super.key,
    required this.isDarkMode,
    required this.child,
    this.width = 220,
  });

  final bool isDarkMode;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: isDarkMode ? Colors.white12 : Colors.black12,
            width: 1,
          ),
        ),
      ),
      child: child,
    );
  }
}

class NipaplaySidePanelItem extends StatefulWidget {
  const NipaplaySidePanelItem({
    super.key,
    required this.isSelected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
    required this.child,
  });

  final bool isSelected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<NipaplaySidePanelItem> createState() => _NipaplaySidePanelItemState();
}

class _NipaplaySidePanelItemState extends State<NipaplaySidePanelItem> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() {
      _isPressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isInteractiveActive = _isHovered || _isPressed;
    final bool isActive = widget.isSelected || isInteractiveActive;
    final Color itemColor = isActive ? Colors.white : widget.inactiveColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.zero,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: widget.onTap,
        onHover: _setHovered,
        onHighlightChanged: _setPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? widget.activeColor
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isActive
                    ? widget.activeColor
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: itemColor),
            child: IconTheme.merge(
              data: IconThemeData(color: itemColor),
              child: Align(
                alignment: Alignment.centerLeft,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TabControllerScope extends InheritedWidget {
  final TabController controller;
  final bool enabled;

  const TabControllerScope({
    super.key,
    required this.controller,
    required this.enabled,
    required super.child,
  });

  static TabController? of(BuildContext context) {
    final TabControllerScope? scope = context
        .dependOnInheritedWidgetOfExactType<TabControllerScope>();
    return scope?.enabled == true ? scope?.controller : null;
  }

  @override
  bool updateShouldNotify(TabControllerScope oldWidget) {
    return enabled != oldWidget.enabled || controller != oldWidget.controller;
  }
}

class _CustomTabIndicator extends Decoration {
  final double indicatorHeight;
  final Color indicatorColor;
  final double radius;

  const _CustomTabIndicator({
    required this.indicatorHeight,
    required this.indicatorColor,
    required this.radius,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _CustomPainter(this, onChanged);
  }
}

class _CustomPainter extends BoxPainter {
  final _CustomTabIndicator decoration;

  _CustomPainter(this.decoration, VoidCallback? onChanged) : super(onChanged);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    assert(configuration.size != null);
    final Rect rect =
        Offset(
          offset.dx,
          (configuration.size!.height - decoration.indicatorHeight),
        ) &
        Size(configuration.size!.width, decoration.indicatorHeight);
    final Paint paint = Paint()
      ..color = decoration.indicatorColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(decoration.radius)),
      paint,
    );
  }
}

class _LogoTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabBar tabBar;

  const _LogoTabBar({required this.tabBar});

  @override
  Size get preferredSize => tabBar.preferredSize;

  @override
  Widget build(BuildContext context) {
    if (globals.isDesktopOrTablet) {
      return tabBar;
    }

    return Row(
      children: [
        const SizedBox(width: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 20.0),
          child: Image.asset(
            'assets/logo.png',
            height: 40,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: tabBar),
      ],
    );
  }
}
