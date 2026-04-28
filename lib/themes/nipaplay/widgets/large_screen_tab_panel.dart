import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/pages/tab_labels.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_side_panel.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

const double kNipaplayLargeScreenTabPanelWidth = 220;

enum NipaplayLargeScreenTabPanelCommand {
  activateFocused,
}

class NipaplayLargeScreenTabPanel extends StatelessWidget {
  const NipaplayLargeScreenTabPanel({
    super.key,
    required this.currentIndex,
    required this.isDarkMode,
    required this.tabPage,
    required this.tabController,
    this.focusedIndex = 0,
    this.commandNotifier,
    this.onFocusedIndexChanged,
    this.onTabActivated,
    this.onToggleLargeScreen,
    this.onToggleThemeFromOrigin,
    this.onOpenSettings,
  });

  final int currentIndex;
  final bool isDarkMode;
  final List<Widget> tabPage;
  final TabController tabController;
  final int focusedIndex;
  final ValueListenable<NipaplayLargeScreenTabPanelCommand?>? commandNotifier;
  final ValueChanged<int>? onFocusedIndexChanged;
  final VoidCallback? onTabActivated;
  final VoidCallback? onToggleLargeScreen;
  final Future<void> Function(Offset globalOrigin)? onToggleThemeFromOrigin;
  final VoidCallback? onOpenSettings;

  List<_NipaplayLargeScreenMenuEntry> _buildTabEntries(BuildContext context) {
    final entries = <_NipaplayLargeScreenMenuEntry>[];
    for (int index = 0; index < tabPage.length; index++) {
      entries.add(
        _NipaplayLargeScreenMenuEntry(
          buildChild: (itemColor) => _buildSidePanelTabContent(
            _stripOuterTabPadding(tabPage[index]),
            itemColor: itemColor,
          ),
          onTap: () {
            if (tabController.index != index) {
              tabController.animateTo(index);
            }
            onTabActivated?.call();
          },
        ),
      );
    }
    return entries;
  }

  List<_NipaplayLargeScreenMenuEntry> _buildActionEntries(
      BuildContext context) {
    final entries = <_NipaplayLargeScreenMenuEntry>[];
    if (onToggleLargeScreen != null) {
      entries.add(
        _NipaplayLargeScreenMenuEntry(
          buildChild: (_) => const Row(
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
          onTap: () {
            onToggleLargeScreen!.call();
            onTabActivated?.call();
          },
        ),
      );
    }

    if (onToggleThemeFromOrigin != null) {
      final String themeActionLabel = isDarkMode
          ? context.l10n.toggleToLightMode
          : context.l10n.toggleToDarkMode;
      final IconData themeActionIcon =
          isDarkMode ? Icons.nightlight_rounded : Icons.light_mode_rounded;
      entries.add(
        _NipaplayLargeScreenMenuEntry(
          buildChild: (_) => Row(
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
          onTap: () {
            _toggleTheme(
              context,
              onToggleFromOrigin: onToggleThemeFromOrigin,
            );
            onTabActivated?.call();
          },
        ),
      );
    }

    if (onOpenSettings != null) {
      entries.add(
        _NipaplayLargeScreenMenuEntry(
          buildChild: (_) => Row(
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
          onTap: () {
            onOpenSettings!.call();
            onTabActivated?.call();
          },
        ),
      );
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    const Color activeColor = Color(0xFFFF2E55);
    final Color inactiveColor = isDarkMode ? Colors.white60 : Colors.black54;
    // Keep the side tab panel aligned with page base background color.
    final Color panelBackgroundColor =
        isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
    final tabEntries = _buildTabEntries(context);
    final actionEntries = _buildActionEntries(context);
    final entries = <_NipaplayLargeScreenMenuEntry>[
      ...tabEntries,
      ...actionEntries,
    ];
    final normalizedFocusedIndex =
        entries.isEmpty ? 0 : focusedIndex.clamp(0, entries.length - 1);

    if (normalizedFocusedIndex != focusedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onFocusedIndexChanged?.call(normalizedFocusedIndex);
      });
    }

    return ColoredBox(
      color: panelBackgroundColor,
      child: NipaplayLargeScreenSidePanel(
        isDarkMode: isDarkMode,
        width: kNipaplayLargeScreenTabPanelWidth,
        child: Padding(
          padding: const EdgeInsets.only(
            top: kNipaplayLargeScreenBottomHintHeight,
            bottom: kNipaplayLargeScreenBottomHintHeight,
          ),
          child: _NipaplayLargeScreenTabPanelCommandHost(
            commandNotifier: commandNotifier,
            onActivateFocused: () {
              if (entries.isEmpty) {
                return;
              }
              entries[normalizedFocusedIndex].onTap();
            },
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: tabEntries.length,
                    itemBuilder: (context, index) {
                      final bool isSelectedByTab = currentIndex == index;
                      final bool isSelectedByFocus =
                          index == normalizedFocusedIndex;
                      final bool isActive =
                          isSelectedByTab || isSelectedByFocus;
                      final Color itemColor =
                          isActive ? Colors.white : inactiveColor;

                      return NipaplayLargeScreenSidePanelItem(
                        isSelected: isActive,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        onTap: () {
                          onFocusedIndexChanged?.call(index);
                          tabEntries[index].onTap();
                        },
                        child: tabEntries[index].buildChild(itemColor),
                      );
                    },
                  ),
                ),
                if (actionEntries.isNotEmpty)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children:
                        List.generate(actionEntries.length, (actionIndex) {
                      final int entryIndex = tabEntries.length + actionIndex;
                      final bool isFocused =
                          entryIndex == normalizedFocusedIndex;
                      final Color itemColor =
                          isFocused ? Colors.white : inactiveColor;
                      return NipaplayLargeScreenSidePanelItem(
                        isSelected: isFocused,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        onTap: () {
                          onFocusedIndexChanged?.call(entryIndex);
                          actionEntries[actionIndex].onTap();
                        },
                        child: actionEntries[actionIndex].buildChild(itemColor),
                      );
                    }),
                  ),
              ],
            ),
          ),
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

class _NipaplayLargeScreenMenuEntry {
  const _NipaplayLargeScreenMenuEntry({
    required this.buildChild,
    required this.onTap,
  });

  final Widget Function(Color itemColor) buildChild;
  final VoidCallback onTap;
}

class _NipaplayLargeScreenTabPanelCommandHost extends StatefulWidget {
  const _NipaplayLargeScreenTabPanelCommandHost({
    required this.child,
    required this.onActivateFocused,
    this.commandNotifier,
  });

  final Widget child;
  final VoidCallback onActivateFocused;
  final ValueListenable<NipaplayLargeScreenTabPanelCommand?>? commandNotifier;

  @override
  State<_NipaplayLargeScreenTabPanelCommandHost> createState() =>
      _NipaplayLargeScreenTabPanelCommandHostState();
}

class _NipaplayLargeScreenTabPanelCommandHostState
    extends State<_NipaplayLargeScreenTabPanelCommandHost> {
  @override
  void initState() {
    super.initState();
    widget.commandNotifier?.addListener(_handleCommand);
  }

  @override
  void didUpdateWidget(
      covariant _NipaplayLargeScreenTabPanelCommandHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commandNotifier == widget.commandNotifier) {
      return;
    }
    oldWidget.commandNotifier?.removeListener(_handleCommand);
    widget.commandNotifier?.addListener(_handleCommand);
  }

  @override
  void dispose() {
    widget.commandNotifier?.removeListener(_handleCommand);
    super.dispose();
  }

  void _handleCommand() {
    final command = widget.commandNotifier?.value;
    if (command == null) {
      return;
    }
    if (command == NipaplayLargeScreenTabPanelCommand.activateFocused) {
      widget.onActivateFocused();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

void _toggleTheme(
  BuildContext context, {
  Future<void> Function(Offset globalOrigin)? onToggleFromOrigin,
}) {
  if (onToggleFromOrigin != null) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final origin =
          renderObject.localToGlobal(renderObject.size.center(Offset.zero));
      onToggleFromOrigin(origin);
      return;
    }
  }

  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  context.read<ThemeNotifier>().themeMode =
      isDarkMode ? ThemeMode.light : ThemeMode.dark;
}
