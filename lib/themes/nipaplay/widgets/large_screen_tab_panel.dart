import 'package:flutter/material.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/pages/tab_labels.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_side_panel.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

const double kNipaplayLargeScreenTabPanelWidth = 220;

class NipaplayLargeScreenTabPanel extends StatelessWidget {
  const NipaplayLargeScreenTabPanel({
    super.key,
    required this.currentIndex,
    required this.isDarkMode,
    required this.tabPage,
    required this.tabController,
    this.onTabActivated,
    this.onToggleLargeScreen,
    this.onToggleThemeFromOrigin,
    this.onOpenSettings,
  });

  final int currentIndex;
  final bool isDarkMode;
  final List<Widget> tabPage;
  final TabController tabController;
  final VoidCallback? onTabActivated;
  final VoidCallback? onToggleLargeScreen;
  final Future<void> Function(Offset globalOrigin)? onToggleThemeFromOrigin;
  final VoidCallback? onOpenSettings;

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
        width: kNipaplayLargeScreenTabPanelWidth,
        child: Padding(
          padding: const EdgeInsets.only(
            bottom: kNipaplayLargeScreenBottomHintHeight,
          ),
          child: Column(
            children: [
              Expanded(
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
                        onTabActivated?.call();
                      },
                      child: _buildSidePanelTabContent(
                        _stripOuterTabPadding(tabPage[index]),
                        itemColor: itemColor,
                      ),
                    );
                  },
                ),
              ),
              if (onToggleLargeScreen != null ||
                  onToggleThemeFromOrigin != null ||
                  onOpenSettings != null)
                _buildActionItems(
                  context,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionItems(
    BuildContext context, {
    required Color activeColor,
    required Color inactiveColor,
  }) {
    final actions = <Widget>[];

    if (onToggleLargeScreen != null) {
      actions.add(
        NipaplayLargeScreenSidePanelItem(
          isSelected: false,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          onTap: () {
            onToggleLargeScreen!.call();
            onTabActivated?.call();
          },
          child: const Row(
            children: [
              Icon(Icons.view_day_rounded, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '退出大屏幕模式',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (onToggleThemeFromOrigin != null) {
      final String themeActionLabel = isDarkMode
          ? context.l10n.toggleToLightMode
          : context.l10n.toggleToDarkMode;
      final IconData themeActionIcon = isDarkMode
          ? Icons.nightlight_rounded
          : Icons.light_mode_rounded;
      actions.add(
        NipaplayLargeScreenSidePanelItem(
          isSelected: false,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          onTap: () {
            _toggleTheme(
              context,
              onToggleFromOrigin: onToggleThemeFromOrigin,
            );
            onTabActivated?.call();
          },
          child: Row(
            children: [
              Icon(themeActionIcon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  themeActionLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (onOpenSettings != null) {
      actions.add(
        NipaplayLargeScreenSidePanelItem(
          isSelected: false,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          onTap: () {
            onOpenSettings!.call();
            onTabActivated?.call();
          },
          child: Row(
            children: [
              const Icon(Icons.settings_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.settingsLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: actions);
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

void _toggleTheme(
  BuildContext context, {
  Future<void> Function(Offset globalOrigin)? onToggleFromOrigin,
}) {
  if (onToggleFromOrigin != null) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final origin = renderObject.localToGlobal(renderObject.size.center(Offset.zero));
      onToggleFromOrigin(origin);
      return;
    }
  }

  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  context.read<ThemeNotifier>().themeMode =
      isDarkMode ? ThemeMode.light : ThemeMode.dark;
}
