// widgets/custom_scaffold.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/widgets/nipaplay_theme/background_with_blur.dart'; // 导入背景图和模糊效果控件
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/switchable_view.dart';

class CustomScaffold extends StatefulWidget {
  final List<Widget> pages;
  final List<Widget> tabPage;
  final bool pageIsHome;
  final TabController? tabController;
  
  const CustomScaffold({
    super.key,
    required this.pages,
    required this.tabPage,
    required this.pageIsHome,
    this.tabController
  });

  @override
  State<CustomScaffold> createState() => _CustomScaffoldState();
}

class _CustomScaffoldState extends State<CustomScaffold> {
  @override
  void initState() {
    super.initState();
    widget.tabController?.addListener(_handleExternalTabChanged);
  }
  
  void _handleExternalTabChanged() {
    if (mounted) {
      setState(() {
      });
    }
  }
  
  @override
  void didUpdateWidget(CustomScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.tabController != oldWidget.tabController) {
      oldWidget.tabController?.removeListener(_handleExternalTabChanged);
      widget.tabController?.addListener(_handleExternalTabChanged);
      setState(() {});
    }
  }
  
  @override
  void dispose() {
    widget.tabController?.removeListener(_handleExternalTabChanged);
    super.dispose();
  }
  
  void _handlePageChangedBySwitchableView(int index) {
    if (widget.tabController != null && widget.tabController!.index != index) {
      widget.tabController!.animateTo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tabController == null) {
      print('[CustomScaffold] CRITICAL: widget.tabController is null. Tabs will not work.');
      return const Center(child: Text("Error: TabController not provided to CustomScaffold"));
    }

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context);
        final enableAnimation = appearanceSettings.enablePageAnimation;

        final currentIndex = widget.tabController!.index;

        return BackgroundWithBlur(
          child: Scaffold(
            primary: false,
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.7)
                : Colors.black.withOpacity(0.2),
            extendBodyBehindAppBar: false,
            appBar: videoState.shouldShowAppBar() && widget.tabPage.isNotEmpty ? AppBar(
              toolbarHeight: !widget.pageIsHome && !globals.isDesktop
                  ? 100
                  : globals.isDesktop
                      ? 20
                      : globals.isTablet ? 30 : 60,
              leading: widget.pageIsHome
                  ? null
                  : IconButton(
                      icon: const Icon(Ionicons.chevron_back_outline),
                      color: Colors.white,
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              bottom: TabBar(
                controller: widget.tabController,
                isScrollable: true,
                tabs: widget.tabPage,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelPadding: const EdgeInsets.only(bottom: 15.0),
                tabAlignment: TabAlignment.start,
                // 恢复灰色背景条，并使用自定义指示器
                dividerColor: const Color.fromARGB(59, 255, 255, 255),
                dividerHeight: 3.0,
                indicator: const _CustomTabIndicator(
                  indicatorHeight: 3.0,
                  indicatorColor: Colors.white,
                  radius: 30.0, // 使用大圆角形成药丸形状
                ),
                indicatorSize: TabBarIndicatorSize.label, // 与label宽度一致
              ),
            ) : null,
            body: TabControllerScope(
              controller: widget.tabController!,
              enabled: true,
              child: SwitchableView(
                enableAnimation: enableAnimation,
                currentIndex: currentIndex,
                physics: enableAnimation
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                onPageChanged: _handlePageChangedBySwitchableView,
                children: widget.pages.map((page) => 
                  RepaintBoundary(child: page)
                ).toList(),
              ),
            ),
          ),
        );
      },
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
    final TabControllerScope? scope = context.dependOnInheritedWidgetOfExactType<TabControllerScope>();
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

  _CustomPainter(this.decoration, VoidCallback? onChanged)
      : super(onChanged);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    assert(configuration.size != null);
    // 将指示器绘制在TabBar的底部
    final Rect rect = Offset(
      offset.dx,
      (configuration.size!.height - decoration.indicatorHeight),
    ) & Size(configuration.size!.width, decoration.indicatorHeight);
    final Paint paint = Paint();
    paint.color = decoration.indicatorColor;
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(decoration.radius)),
      paint,
    );
  }
}
