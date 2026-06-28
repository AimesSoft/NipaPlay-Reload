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
  String? _lastVideoUnderlayLogSignature;

  bool get _nativeVideoUnderlayDebugLogsEnabled {
    if (kReleaseMode || kIsWeb) {
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return Platform.environment['NIPAPLAY_WINDOWS_HDR_EXIT_TRACE'] == '1';
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return Platform.environment['NIPAPLAY_MACOS_HDR_EXIT_TRACE'] == '1';
    }
    return false;
  }

  bool get _windowHostedVideoUnderlayEnabled {
    if (kIsWeb) {
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return Platform.environment['NIPAPLAY_MACOS_HDR_TRANSPARENT_FLUTTER'] !=
              '0' &&
          Platform.environment['NIPAPLAY_MACOS_HDR_USE_APPKIT_VIEW'] != '1' &&
          Platform.environment['NIPAPLAY_DISABLE_MACOS_WINDOW_OVERLAY'] != '1';
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return Platform.environment['NIPAPLAY_DISABLE_WINDOWS_WINDOW_OVERLAY'] !=
          '1';
    }
    return false;
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

    final bool isDesktop = globals.isDesktop;
    final bool isTablet = globals.isTablet;
    final bool isDesktopOrTablet = isDesktop || isTablet;
    final bool useLargeScreenLayout = widget.useLargeScreenLayout &&
        widget.pageIsHome &&
        isDesktopOrTablet &&
        widget.tabPage.isNotEmpty;
    const enableAnimation = false;

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
    final bool hasWindowHostedVideoSurface =
        context.select<VideoPlayerState, bool>(
      (videoState) => videoState.player.usesWindowOverlayVideoSurface,
    );
    final bool useVideoUnderlay = (hasWindowHostedVideoSurface ||
            (_windowHostedVideoUnderlayEnabled && hasNativeVideoSurface)) &&
        widget.pageIsHome &&
        currentIndex == 1 &&
        hasVideo;
    _logVideoUnderlayState(
      enabled: useVideoUnderlay,
      hasNativeVideoSurface: hasNativeVideoSurface,
      hasVideo: hasVideo,
      currentIndex: currentIndex,
    );
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
      children: widget.pages.map((page) {
        final bool wrapLargeScreenContent =
            useLargeScreenLayout && widget.pageIsHome;
        if (wrapLargeScreenContent) {
          return RepaintBoundary(
            child: NipaplayLargeScreenContentPage(child: page),
          );
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

    return _WindowHostedVideoBackground(
      enabled: useVideoUnderlay,
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

  void _logVideoUnderlayState({
    required bool enabled,
    required bool hasNativeVideoSurface,
    required bool hasVideo,
    required int currentIndex,
  }) {
    if (!_nativeVideoUnderlayDebugLogsEnabled) {
      return;
    }
    final signature = [
      defaultTargetPlatform.name,
      enabled.toString(),
      hasNativeVideoSurface.toString(),
      hasVideo.toString(),
      currentIndex.toString(),
    ].join('|');
    if (signature == _lastVideoUnderlayLogSignature) {
      return;
    }
    _lastVideoUnderlayLogSignature = signature;
    debugPrint(
      '[NativeVideoUnderlay] platform=${defaultTargetPlatform.name} '
      'enabled=$enabled hasNativeVideoSurface=$hasNativeVideoSurface '
      'hasVideo=$hasVideo currentIndex=$currentIndex',
    );
  }
}

class _WindowHostedVideoBackground extends StatelessWidget {
  const _WindowHostedVideoBackground({
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return BackgroundWithBlur(child: child);
    }
    return Selector<VideoPlayerState, Rect?>(
      selector: (_, videoState) => videoState.windowHostedVideoRect,
      builder: (context, videoUnderlayRect, child) {
        return _WindowHostedVideoBlackBackground(
          transparentCutout: videoUnderlayRect,
          child: child!,
        );
      },
      child: child,
    );
  }
}

class _WindowHostedVideoBlackBackground extends StatelessWidget {
  const _WindowHostedVideoBlackBackground({
    required this.child,
    required this.transparentCutout,
  });

  final Widget child;
  final Rect? transparentCutout;

  @override
  Widget build(BuildContext context) {
    final cutout = transparentCutout;
    final background = cutout == null
        ? const ColoredBox(color: Colors.black)
        : ClipPath(
            clipper: _RectCutoutClipper(cutout: cutout),
            child: const ColoredBox(color: Colors.black),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: background),
        child,
      ],
    );
  }
}

class _RectCutoutClipper extends CustomClipper<Path> {
  const _RectCutoutClipper({required this.cutout});

  final Rect cutout;

  @override
  Path getClip(Size size) {
    final bounds = Offset.zero & size;
    final effectiveCutout = cutout.intersect(bounds);
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(bounds);
    if (!effectiveCutout.isEmpty) {
      path.addRect(effectiveCutout);
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _RectCutoutClipper oldClipper) {
    return oldClipper.cutout != cutout;
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
