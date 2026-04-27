import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_tab_panel.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class NipaplayLargeScreenScaffoldLayout extends StatelessWidget {
  const NipaplayLargeScreenScaffoldLayout({
    super.key,
    required this.currentIndex,
    required this.isDarkMode,
    required this.tabPage,
    required this.tabController,
    required this.content,
  });

  final int currentIndex;
  final bool isDarkMode;
  final List<Widget> tabPage;
  final TabController tabController;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding;
    final double topInset = globals.isDesktop ? 50 : mediaPadding.top + 14;

    return Stack(
      children: [
        Positioned.fill(
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
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: NipaplayLargeScreenTabPanel(
            currentIndex: currentIndex,
            isDarkMode: isDarkMode,
            tabPage: tabPage,
            tabController: tabController,
          ),
        ),
      ],
    );
  }
}
