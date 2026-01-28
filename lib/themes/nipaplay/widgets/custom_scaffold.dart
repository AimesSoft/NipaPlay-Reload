// widgets/custom_scaffold.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/themes/nipaplay/widgets/background_with_blur.dart'; // 导入背景图和模糊效果控件
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CustomScaffold extends StatefulWidget {
  final List<Widget> pages;
  final List<Widget> tabPage;
  final bool pageIsHome;
  final bool shouldShowAppBar;
  final TabController? tabController;

  const CustomScaffold(
      {super.key,
      required this.pages,
      required this.tabPage,
      required this.pageIsHome,
      required this.shouldShowAppBar,
      this.tabController});

  @override
  State<CustomScaffold> createState() => _CustomScaffoldState();
}

class _CustomScaffoldState extends State<CustomScaffold> {
  int? _lastTabIndex;

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
          child: Text("Error: TabController not provided to CustomScaffold"));
    }

    final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context);
    final bool isDesktopOrTablet = globals.isDesktopOrTablet;
    // 强制启用动画
    const enableAnimation = true;

    final currentIndex = widget.tabController!.index;
    final preloadIndices = widget.pageIsHome
        ? List<int>.generate(widget.pages.length, (i) => i)
            .where((i) => i != 1)
            .toList()
        : const <int>[];

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bool hasVideo = context.select<VideoPlayerState, bool>(
      (videoState) => videoState.hasVideo,
    );
    final bool showTabDivider = widget.pageIsHome &&
        widget.tabController?.index == 1 &&
        hasVideo;
    final Color tabDividerColor =
        isDarkMode ? Colors.white24 : Colors.black12;

    return BackgroundWithBlur(
      child: Scaffold(
        primary: false,
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: false,
        appBar: widget.shouldShowAppBar && widget.tabPage.isNotEmpty
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
                elevation: 0,
                bottom: _LogoTabBar(
                  tabBar: TabBar(
                    controller: widget.tabController,
                    isScrollable: true,
                    tabs: widget.tabPage,
                    labelColor: const Color(0xFFFF2E55),
                    unselectedLabelColor:
                        isDarkMode ? Colors.white60 : Colors.black54,
                    labelPadding: const EdgeInsets.only(bottom: 15.0),
                    tabAlignment: TabAlignment.start,
                    splashFactory: NoSplash.splashFactory, // 去除水波纹
                    overlayColor:
                        WidgetStateProperty.all(Colors.transparent), // 去除点击背景色
                    // 仅在播放页正在播放时显示滑轨，用于分隔视频与Tab
                    dividerColor:
                        showTabDivider ? tabDividerColor : Colors.transparent,
                    dividerHeight: 3.0,
                    indicator: const _CustomTabIndicator(
                      indicatorHeight: 3.0,
                      indicatorColor: Color(0xFFFF2E55),
                      radius: 30.0, // 使用大圆角形成药丸形状
                    ),
                    indicatorSize: TabBarIndicatorSize.label, // 与label宽度一致
                  ),
                ),
              )
            : null,
        body: TabControllerScope(
          controller: widget.tabController!,
          enabled: true,
          child: SwitchableView(
            enableAnimation: enableAnimation,
            keepAlive: true,
            preloadIndices: preloadIndices,
            currentIndex: currentIndex,
            physics: enableAnimation
                ? const PageScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            onPageChanged: _handlePageChangedBySwitchableView,
            children: widget.pages
                .map((page) => RepaintBoundary(child: page))
                .toList(),
          ),
        ),
      ),
    );
  }
}

/// 提供TabController给子组件的作用域
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

// 自定义Tab指示器
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
    // 将指示器绘制在TabBar的底部
    final Rect rect = Offset(
          offset.dx,
          (configuration.size!.height - decoration.indicatorHeight),
        ) &
        Size(configuration.size!.width, decoration.indicatorHeight);
    final Paint paint = Paint();
    paint.color = decoration.indicatorColor;
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(decoration.radius)),
      paint,
    );
  }
}

class _LogoTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabBar tabBar;

  const _LogoTabBar({super.key, required this.tabBar});

  @override
  Size get preferredSize => tabBar.preferredSize;

  @override
  Widget build(BuildContext context) {
    // 桌面端/平板不显示Logo（移至右上角），移动端与Web保持原有布局
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
