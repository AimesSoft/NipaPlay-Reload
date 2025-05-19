// widgets/custom_scaffold.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/widgets/background_with_blur.dart'; // 导入背景图和模糊效果控件
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/widgets/switchable_view.dart';

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

class _CustomScaffoldState extends State<CustomScaffold> with TickerProviderStateMixin {
  // 当前选中的页面索引
  late int _currentIndex;
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.tabController?.index ?? 0;
    
    // 创建自己的TabController以便双向控制
    _tabController = TabController(
      length: widget.pages.length,
      initialIndex: _currentIndex,
      vsync: this,
    );
    
    // 监听TabController变化
    _tabController.addListener(_handleTabChanged);
  }
  
  void _handleTabChanged() {
    // 仅当索引真正变化时才更新
    if (!_tabController.indexIsChanging) return;
    
    final int newIndex = _tabController.index;
    if (_currentIndex != newIndex) {
      setState(() {
        _currentIndex = newIndex;
      });
    }
  }
  
  @override
  void didUpdateWidget(CustomScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果页面数量变化，重新创建TabController
    if (widget.pages.length != oldWidget.pages.length) {
      _tabController.dispose();
      _tabController = TabController(
        length: widget.pages.length,
        initialIndex: _currentIndex < widget.pages.length ? _currentIndex : 0,
        vsync: this,
      );
      _tabController.addListener(_handleTabChanged);
    }
    
    // 如果外部TabController变化，同步状态
    if (widget.tabController != null && 
        widget.tabController != oldWidget.tabController &&
        widget.tabController!.index != _currentIndex) {
      _currentIndex = widget.tabController!.index;
      _tabController.animateTo(_currentIndex);
    }
  }
  
  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }
  
  // 当页面通过滑动或其他方式变化时调用
  void _handlePageChanged(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
      
      if (_tabController.index != index) {
        _tabController.animateTo(index);
      }
      
      // 同步到外部TabController
      if (widget.tabController != null && widget.tabController!.index != index) {
        widget.tabController!.animateTo(index);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // 获取外观设置，判断是否启用页面滑动动画
        final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context);
        final enableAnimation = appearanceSettings.enablePageAnimation;

        return BackgroundWithBlur(
          child: Scaffold(
            primary: false,
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.7)
                : Colors.black.withOpacity(0.2),
            extendBodyBehindAppBar: false,
            appBar: videoState.shouldShowAppBar() ? AppBar(
              toolbarHeight: !widget.pageIsHome && !globals.isDesktop
                  ? 100
                  : globals.isDesktop
                      ? 20
                      : 60,
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
                controller: _tabController, // 使用内部控制器
                isScrollable: true,
                tabs: widget.tabPage,
                labelColor: Colors.white,
                dividerColor: const Color.fromARGB(59, 255, 255, 255),
                dividerHeight: 3.0,
                indicatorPadding:
                    const EdgeInsets.only(top: 43, left: 15, right: 15),
                unselectedLabelColor: Colors.white60,
                labelPadding: const EdgeInsets.only(bottom: 15.0),
                tabAlignment: TabAlignment.start,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
              ),
            ) : null,
            body: TabControllerScope(
              controller: _tabController,
              enabled: true, // 始终启用
              child: SwitchableView(
                enableAnimation: enableAnimation,
                currentIndex: _currentIndex,
                physics: enableAnimation
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                onPageChanged: _handlePageChanged,
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
    Key? key,
    required this.controller,
    required this.enabled,
    required Widget child,
  }) : super(key: key, child: child);

  static TabController? of(BuildContext context) {
    final TabControllerScope? scope = context.dependOnInheritedWidgetOfExactType<TabControllerScope>();
    return scope?.enabled == true ? scope?.controller : null;
  }

  @override
  bool updateShouldNotify(TabControllerScope oldWidget) {
    return enabled != oldWidget.enabled || controller != oldWidget.controller;
  }
}
