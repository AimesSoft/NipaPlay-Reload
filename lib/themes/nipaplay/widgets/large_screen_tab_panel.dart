import 'package:flutter/material.dart';
import 'package:nipaplay/pages/tab_labels.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_side_panel.dart';

class NipaplayLargeScreenTabPanel extends StatelessWidget {
  const NipaplayLargeScreenTabPanel({
    super.key,
    required this.currentIndex,
    required this.isDarkMode,
    required this.tabPage,
    required this.tabController,
  });

  final int currentIndex;
  final bool isDarkMode;
  final List<Widget> tabPage;
  final TabController tabController;

  @override
  Widget build(BuildContext context) {
    const Color activeColor = Color(0xFFFF2E55);
    final Color inactiveColor = isDarkMode ? Colors.white60 : Colors.black54;
    // Keep the side tab panel aligned with page base background color.
    final Color panelBackgroundColor =
        isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);

    return ColoredBox(
      color: panelBackgroundColor,
      child: NipaplayLargeScreenSidePanel(
        isDarkMode: isDarkMode,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: tabPage.length,
          itemBuilder: (context, index) {
            final bool isSelected = currentIndex == index;
            final Color itemColor = isSelected
                ? Colors.white
                : (isDarkMode ? Colors.white60 : Colors.black54);

            return NipaplayLargeScreenSidePanelItem(
              isSelected: isSelected,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              onTap: () {
                if (tabController.index != index) {
                  tabController.animateTo(index);
                }
              },
              child: _buildSidePanelTabContent(
                _stripOuterTabPadding(tabPage[index]),
                itemColor: itemColor,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _stripOuterTabPadding(Widget tabWidget) {
    if (tabWidget is Padding && tabWidget.child != null) {
      return tabWidget.child!;
    }
    return tabWidget;
  }

  Widget _buildSidePanelTabContent(
    Widget tabWidget, {
    required Color itemColor,
  }) {
    if (tabWidget is HoverZoomTab) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tabWidget.icon != null) ...[
            IconTheme(
              data: IconThemeData(color: itemColor),
              child: tabWidget.icon!,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            tabWidget.text,
            style: TextStyle(
              color: itemColor,
              fontSize: tabWidget.fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }
    return tabWidget;
  }
}
