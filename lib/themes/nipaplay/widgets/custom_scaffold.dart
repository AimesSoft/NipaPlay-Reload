import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/background_with_blur.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_scaffold_layout.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_home_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_main_tab_bar.dart';
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
  final VoidCallback? onToggleLargeScreen;
  final Future<void> Function(Offset globalOrigin)? onToggleThemeFromOrigin;
  final VoidCallback? onOpenSettings;

  const CustomScaffold({
    super.key,
    required this.pages,
    required this.tabPage,
    required this.pageIsHome,
    required this.shouldShowAppBar,
    this.tabController,
    this.useLargeScreenLayout = false,
    this.onToggleLargeScreen,
    this.onToggleThemeFromOrigin,
    this.onOpenSettings,
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
      return Center(
        child: Text("Error: TabController not provided to CustomScaffold"),
      );
    }

    final bool isDesktop = globals.isDesktop;
    final bool isTablet = globals.isTablet;
    final bool isDesktopOrTablet = isDesktop || isTablet;
    final bool useLargeScreenLayout = widget.useLargeScreenLayout &&
        widget.pageIsHome &&
        isDesktopOrTablet &&
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
    final bool useVideoUnderlay = _macOSHdrTransparentUnderlayEnabled &&
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
      children: widget.pages.asMap().entries.map((entry) {
        final index = entry.key;
        final page = entry.value;
        final bool useLargeScreenHomePage =
            useLargeScreenLayout && widget.pageIsHome && index == 0;
        if (useLargeScreenHomePage) {
          return const RepaintBoundary(child: NipaplayLargeScreenHomePage());
        }
        return RepaintBoundary(child: page);
      }).toList(),
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
                  : isDesktop
                      ? 20
                      : isTablet
                          ? 30
                          : 60,
              leading: widget.pageIsHome
                  ? null
                  : IconButton(
                      icon: Icon(Ionicons.chevron_back_outline),
                      color: isDarkMode ? Colors.white : Colors.black,
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: appBarOverlayStyle,
              bottom: NipaplayMainTabBar(
                controller: widget.tabController!,
                tabs: widget.tabPage,
                showDivider: showTabDivider,
                dividerColor: tabDividerColor,
                showLeadingLogoOnMobile: true,
              ),
            )
          : null,
      body: TabControllerScope(
        controller: widget.tabController!,
        enabled: true,
        child: useLargeScreenLayout
            ? NipaplayLargeScreenScaffoldLayout(
                currentIndex: currentIndex,
                isDarkMode: isDarkMode,
                tabPage: widget.tabPage,
                tabController: widget.tabController!,
                content: switchableContent,
                onToggleLargeScreen: widget.onToggleLargeScreen,
                onToggleThemeFromOrigin: widget.onToggleThemeFromOrigin,
                onOpenSettings: widget.onOpenSettings,
              )
            : switchableContent,
      ),
    );

    return BackgroundWithBlur(
      transparentCutout: useVideoUnderlay ? videoUnderlayRect : null,
      child: scaffold,
    );
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
    final TabControllerScope? scope =
        context.dependOnInheritedWidgetOfExactType<TabControllerScope>();
    return scope?.enabled == true ? scope?.controller : null;
  }

  @override
  bool updateShouldNotify(TabControllerScope oldWidget) {
    return enabled != oldWidget.enabled || controller != oldWidget.controller;
  }
}
