import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_tab_panel.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class NipaplayLargeScreenScaffoldLayout extends StatefulWidget {
  const NipaplayLargeScreenScaffoldLayout({
    super.key,
    required this.currentIndex,
    required this.isDarkMode,
    required this.tabPage,
    required this.tabController,
    required this.content,
    this.onToggleLargeScreen,
    this.onToggleThemeFromOrigin,
    this.onOpenSettings,
  });

  final int currentIndex;
  final bool isDarkMode;
  final List<Widget> tabPage;
  final TabController tabController;
  final Widget content;
  final VoidCallback? onToggleLargeScreen;
  final Future<void> Function(Offset globalOrigin)? onToggleThemeFromOrigin;
  final VoidCallback? onOpenSettings;

  @override
  State<NipaplayLargeScreenScaffoldLayout> createState() =>
      _NipaplayLargeScreenScaffoldLayoutState();
}

class _NipaplayLargeScreenScaffoldLayoutState
    extends State<NipaplayLargeScreenScaffoldLayout> {
  bool _isTabPanelVisible = false;

  void _toggleTabPanel() {
    setState(() {
      _isTabPanelVisible = !_isTabPanelVisible;
    });
  }

  void _closeTabPanel() {
    if (!_isTabPanelVisible) {
      return;
    }
    setState(() {
      _isTabPanelVisible = false;
    });
  }

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
            child: widget.content,
          ),
        ),
        if (_isTabPanelVisible)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeTabPanel,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: ColoredBox(
                    color: widget.isDarkMode
                        ? Colors.black.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          left: _isTabPanelVisible ? 0 : -kNipaplayLargeScreenTabPanelWidth,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !_isTabPanelVisible,
            child: NipaplayLargeScreenTabPanel(
              currentIndex: widget.currentIndex,
              isDarkMode: widget.isDarkMode,
              tabPage: widget.tabPage,
              tabController: widget.tabController,
              onTabActivated: _closeTabPanel,
              onToggleLargeScreen: widget.onToggleLargeScreen,
              onToggleThemeFromOrigin: widget.onToggleThemeFromOrigin,
              onOpenSettings: widget.onOpenSettings,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: NipaplayLargeScreenBottomHintOverlay(
            isDarkMode: widget.isDarkMode,
            onToggleMenu: _toggleTabPanel,
          ),
        ),
      ],
    );
  }
}
