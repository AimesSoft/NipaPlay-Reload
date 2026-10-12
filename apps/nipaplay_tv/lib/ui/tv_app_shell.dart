import 'package:flutter/material.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import 'focusable_card.dart';
import 'pages/about_page.dart';
import 'pages/profile_page.dart';
import '../data/tv_media_sources.dart';
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

  /// 导航栏焦点节点：返回键回退与失焦兜底的锚点。
  final _navFocus = List.generate(
    5,
    (i) => FocusNode(debugLabel: 'nav-$i'),
  );
  int _navIndex = 0;

  /// 已配置的媒体连接（全部）。
  List<TvMediaSource> _mediaSources = const [];

  /// 钉选到侧边栏的连接（用户手动选择）。
  List<TvMediaSource> get _pinnedSources =>
      _mediaSources.where((s) => s.pinned).toList();

  /// 侧栏点入的源 key（进入后直接显示该源的番剧列表）。
  String? _openedSourceKey;
  int? _activeSourceIndex;
  /// 递增请求令牌：保证重复点击同一来源也能触发页面刷新。
  int _sourceRequestId = 0;

  /// 遥控焦点兜底：任何时刻焦点都不允许为空，否则 D-pad 将彻底失灵。
  void _ensureFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null || !primary.hasFocus) {
        _pageEntryFocus[_pageIndex]?.requestFocus();
      }
    });
  }

  /// 各页面的入口焦点节点：切页后由壳主动 requestFocus。
  final _pageEntryFocus = <int, FocusNode>{
    0: FocusNode(debugLabel: 'home-entry'),
    1: FocusNode(debugLabel: 'library-entry'),
    2: FocusNode(debugLabel: 'profile-entry'),
    3: FocusNode(debugLabel: 'settings-entry'),
    4: FocusNode(debugLabel: 'about-entry'),
  };

  @override
  void initState() {
    super.initState();
    // 焦点变化后兜底检查，避免遥控操作中途失焦。
    FocusManager.instance.addListener(_ensureFocus);
    _reloadSources();
  }

  Future<void> _reloadSources() async {
    final list = await TvMediaSourceStore.load();
    if (mounted) setState(() => _mediaSources = list);
  }

  /// 打开某个媒体连接：切到媒体库页并聚焦该源（index 为 pinned 列表下标）。
  void _openSource(int index) {
    final pinned = _pinnedSources;
    if (index < 0 || index >= pinned.length) return;
    final target = pinned[index];
    final realIndex = _mediaSources.indexWhere(
        (s) => s.location == target.location && s.kind == target.kind);
    setState(() {
      _pageIndex = 1;
      _activeSourceIndex = realIndex >= 0 ? realIndex : null;
      _sourceRequestId++;
      _openedSourceKey = '${target.kind.name}|${target.location}';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pageEntryFocus[1]?.requestFocus();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_ensureFocus);
    for (final node in _pageEntryFocus.values) {
      node.dispose();
    }
    for (final node in _navFocus) {
      node.dispose();
    }
    super.dispose();
  }

  void _activate(int index) {
    setState(() {
      _pageIndex = index;
      if (index == 1) {
        _activeSourceIndex = null;
        _openedSourceKey = null;
      }
    });
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
      ('我的', Icons.person_outline),
      (l10n.tabSettings, Icons.settings_outlined),
      (l10n.about, Icons.info_outline),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // 返回键：把焦点交还导航栏（遥控"回退"语义），避免焦点丢失。
        _navFocus[_navIndex].requestFocus();
      },
      child: _buildBody(context, tabs),
    );
  }

  Widget _buildBody(
      BuildContext context, List<(String, IconData)> tabs) {
    final l10n = context.l10n;
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
                  for (var i = 0; i < tabs.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: FocusableCard(
                        focusNode: _navFocus[i],
                        onFocused: () => _navIndex = i,
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
                    // 「媒体库」下方：逐个列出已添加的媒体连接
                    if (i == 1 && _pinnedSources.isNotEmpty)
                      for (var k = 0; k < _pinnedSources.length; k++)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 2, 12, 2),
                          child: FocusableCard(
                            onActivate: () => _openSource(k),
                            borderRadius: 10,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            child: Row(
                              children: [
                                Icon(_pinnedSources[k].icon,
                                    size: 18, color: const Color(0xFF26C6DA)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _pinnedSources[k].name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 14, color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
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
                  HomePage(
                    entryFocusNode: _pageEntryFocus[0],
                    onRequestLogin: () => _activate(2), // 跳到「我的」登录
                  ),
                  LibraryPage(
                    entryFocusNode: _pageEntryFocus[1],
                    activeSourceIndex: _activeSourceIndex,
                    sourceRequestId: _sourceRequestId,
                    initialContentSource: _openedSourceKey,
                    onSourcesChanged: _reloadSources,
                  ),
                  ProfilePage(entryFocusNode: _pageEntryFocus[2]),
                  SettingsPage(entryFocusNode: _pageEntryFocus[3]),
                  AboutPage(entryFocusNode: _pageEntryFocus[4]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
