// widgets/custom_scaffold.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/widgets/background_with_blur.dart'; // 导入背景图和模糊效果控件
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

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
  late int _currentIndex;
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.tabController?.index ?? 0;
    
    // 添加监听器以更新当前索引
    widget.tabController?.addListener(_handleTabChange);
  }
  
  @override
  void didUpdateWidget(CustomScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 当控制器改变时，更新监听器
    if (oldWidget.tabController != widget.tabController) {
      oldWidget.tabController?.removeListener(_handleTabChange);
      widget.tabController?.addListener(_handleTabChange);
      _currentIndex = widget.tabController?.index ?? 0;
    }
  }
  
  @override
  void dispose() {
    // 移除监听器
    widget.tabController?.removeListener(_handleTabChange);
    super.dispose();
  }
  
  void _handleTabChange() {
    if (widget.tabController != null && _currentIndex != widget.tabController!.index) {
      setState(() {
        _currentIndex = widget.tabController!.index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // 判断当前活动页面是否为视频播放页 (假定视频播放页索引为0)
        final bool isVideoPlayerPageActive = _currentIndex == 0;

        return DefaultTabController(
          length: widget.pages.length,
          initialIndex: _currentIndex,
          child: BackgroundWithBlur(
            child: Scaffold(
              primary: false,
              // ignore: deprecated_member_use
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  // ignore: deprecated_member_use
                  ? Colors.black.withOpacity(0.7)
                  // ignore: deprecated_member_use
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
                          // 这里可以自定义返回按钮的逻辑
                          Navigator.of(context).pop();
                        },
                      ),
                backgroundColor: Colors.transparent,
                elevation: 0,
                bottom: TabBar(
                  controller: widget.tabController,
                  isScrollable: true,
                  tabs: widget.tabPage, // 使用从 tab_labels.dart 中导入的标签
                  labelColor: Colors.white,
                  dividerColor: const Color.fromARGB(59, 255, 255, 255),
                  dividerHeight: 3.0,
                  indicatorPadding:
                      const EdgeInsets.only(top: 43, left: 15, right: 15),
                  unselectedLabelColor: Colors.white60,
                  labelPadding: const EdgeInsets.only(bottom: 15.0),
                  tabAlignment: TabAlignment.start,
                  indicator: BoxDecoration(
                    color: Colors.white, // 设置指示器的颜色
                    borderRadius: BorderRadius.circular(30), // 设置圆角矩形的圆角半径
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                ),
              ) : null,
              // 使用IndexedStack替代TabBarView，保持所有页面状态
              body: IndexedStack(
                index: _currentIndex,
                children: widget.pages.map((page) => 
                  // 为每个页面添加RepaintBoundary，限制重绘范围
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
