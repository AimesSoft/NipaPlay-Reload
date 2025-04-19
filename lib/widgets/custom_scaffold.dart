// widgets/custom_scaffold.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/widgets/background_with_blur.dart'; // 导入背景图和模糊效果控件
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import '../main.dart' show tabControllerKey;

class CustomScaffold extends StatelessWidget {
  final List<Widget> pages;
  final List<Widget> tabPage;
  final bool pageIsHome;
  final TabController? tabController;
  const CustomScaffold(
      {super.key,
      required this.pages,
      required this.tabPage,
      required this.pageIsHome,
      this.tabController});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return DefaultTabController(
          length: pages.length,
          initialIndex: tabController?.index ?? 0,
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
                toolbarHeight: !pageIsHome && !isDesktop
                    ? 100
                    : isDesktop
                        ? 20
                        : 60,
                leading: pageIsHome
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
                  controller: tabController,
                  isScrollable: true,
                  tabs: tabPage, // 使用从 tab_labels.dart 中导入的标签
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
              body: TabBarView(
                controller: tabController,
                viewportFraction: 1.0,
                physics: const BouncingScrollPhysics(),
                children: pages,
              ),
            ),
          ),
        );
      },
    );
  }
}
