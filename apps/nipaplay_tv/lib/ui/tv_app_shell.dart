import 'package:flutter/material.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import 'focusable_card.dart';
import 'pages/about_page.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/settings_page.dart';

/// TV 应用壳：左侧焦点导航栏 + 右侧内容面板。
/// D-pad 左右可在导航栏与内容区之间穿越，上下在区内移动，确认键激活。
class TvAppShell extends StatefulWidget {
  const TvAppShell({super.key});

  @override
  State<TvAppShell> createState() => _TvAppShellState();
}

class _TvAppShellState extends State<TvAppShell> {
  int _pageIndex = 0;

  void _activate(int index) => setState(() => _pageIndex = index);

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
                children: const [
                  HomePage(),
                  LibraryPage(),
                  SettingsPage(),
                  AboutPage(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
