import 'package:flutter/material.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import 'focusable_card.dart';
import 'pages/about_page.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/settings_page.dart';

/// TV 应用壳：左侧导航栏 + 右侧内容面板。
///
/// 焦点模型：
/// - 导航项自带 focusNode，切页时把焦点交给新页面的入口卡片，
///   避免"高光留在旧页/旧导航项"的问题（IndexedStack 会同时构建全部页面）；
/// - 导航项用 [FocusableCard.selected] 常驻显示"当前所在页"，
///   与焦点高亮分离，所以即使焦点在内容区，导航也能看出当前在哪一页。
class TvAppShell extends StatefulWidget {
  const TvAppShell({super.key});

  @override
  State<TvAppShell> createState() => _TvAppShellState();
}

class _TvAppShellState extends State<TvAppShell> {
  int _pageIndex = 0;

  /// 各页面的入口焦点节点：切页后由壳主动 requestFocus。
  final _pageEntryFocus = <int, FocusNode>{
    0: FocusNode(debugLabel: 'home-entry'),
    1: FocusNode(debugLabel: 'library-entry'),
    2: FocusNode(debugLabel: 'settings-entry'),
    3: FocusNode(debugLabel: 'about-entry'),
  };

  @override
  void dispose() {
    for (final node in _pageEntryFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _activate(int index) {
    setState(() => _pageIndex = index);
    // 切页后把焦点移交给新页面的入口卡片（下一帧，等新页面挂载）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pageEntryFocus[index]?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tabs = [
      (l10n.tabHome, Icons.home_outlined),
      (l10n.tabMediaLibrary, Icons.video_library_outlined),
      (l10n.tabSettings, Icons.settings_outlined),
      (l10n.about, Icons.info_outline),
    ];
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Container(
              width: 220,
              color: Colors.black.withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text(
                      l10n.appTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: const Color(0xFF26C6DA),
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: FocusableCard(
                        autofocus: i == 0,
                        selected: _pageIndex == i,
                        onActivate: () => _activate(i),
                        borderRadius: 12,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(tabs[i].$2, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tabs[i].$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                            if (_pageIndex == i)
                              Icon(Icons.chevron_right,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: IndexedStack(
                index: _pageIndex,
                children: [
                  HomePage(entryFocusNode: _pageEntryFocus[0]),
                  LibraryPage(entryFocusNode: _pageEntryFocus[1]),
                  SettingsPage(entryFocusNode: _pageEntryFocus[2]),
                  AboutPage(entryFocusNode: _pageEntryFocus[3]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
