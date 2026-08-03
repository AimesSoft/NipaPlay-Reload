import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/player_menu/player_menu_definition_builder.dart';
import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_input_controls.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_player_menu_components.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_player_menu_pane_host.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

const double kNipaplayLargeScreenPlayerMenuPanelWidth = 960;

class NipaplayLargeScreenPlayerMenuPanel extends StatefulWidget {
  const NipaplayLargeScreenPlayerMenuPanel({
    super.key,
    required this.isDarkMode,
    required this.initialFocusNode,
    required this.onExitPlayback,
    required this.onSendDanmaku,
    required this.onRequestClose,
  });

  final bool isDarkMode;
  final FocusNode initialFocusNode;
  final VoidCallback onExitPlayback;
  final VoidCallback onSendDanmaku;
  final VoidCallback onRequestClose;

  @override
  State<NipaplayLargeScreenPlayerMenuPanel> createState() =>
      _NipaplayLargeScreenPlayerMenuPanelState();
}

class _NipaplayLargeScreenPlayerMenuPanelState
    extends State<NipaplayLargeScreenPlayerMenuPanel> {
  final FocusNode _panelFocusNode = FocusNode(
    debugLabel: 'nipaplay_large_screen_player_menu_panel',
  );
  final FocusScopeNode _contentFocusScope = FocusScopeNode(
    debugLabel: 'nipaplay_large_screen_player_menu_content',
  );
  final ScrollController _tabScrollController = ScrollController();
  List<_PlayerMenuTabEntry> _latestEntries = const [];
  PlayerMenuPaneId? _selectedPaneId;
  int _focusedTabIndex = 0;
  bool _isContentFocused = false;
  FocusNode? _lastContentFocusNode;

  @override
  void dispose() {
    _panelFocusNode.dispose();
    _contentFocusScope.dispose();
    _tabScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        widget.isDarkMode ? Colors.white : const Color(0xFF161922);
    return Focus(
      focusNode: _panelFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              width: kNipaplayLargeScreenPlayerMenuPanelWidth,
              color: widget.isDarkMode
                  ? Colors.black.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.88),
              child: Consumer<VideoPlayerState>(
                builder: (context, videoState, _) {
                  final definitions = PlayerMenuDefinitionBuilder(
                    context: PlayerMenuContext(
                      videoState: videoState,
                      kernelType: PlayerFactory.getKernelType(),
                    ),
                  ).build();
                  final entries = <_PlayerMenuTabEntry>[
                    const _PlayerMenuTabEntry.actions(),
                    ...definitions.map(_PlayerMenuTabEntry.definition),
                  ];
                  _latestEntries = entries;
                  _focusedTabIndex = _focusedTabIndex.clamp(
                    0,
                    entries.length - 1,
                  );
                  final selectedEntry = _resolveSelectedEntry(entries);

                  return Row(
                    children: [
                      _buildTabs(entries, selectedEntry, textColor),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color:
                            widget.isDarkMode ? Colors.white12 : Colors.black12,
                      ),
                      Expanded(
                        child: _buildContent(
                          videoState,
                          selectedEntry,
                          textColor,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs(
    List<_PlayerMenuTabEntry> entries,
    _PlayerMenuTabEntry selectedEntry,
    Color textColor,
  ) {
    return Focus(
      focusNode: widget.initialFocusNode,
      descendantsAreFocusable: false,
      onFocusChange: (focused) {
        if (focused && _isContentFocused && mounted) {
          setState(() => _isContentFocused = false);
        }
      },
      child: SizedBox(
        width: kNipaplayLargeScreenPlayerMenuSidebarWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 62, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '播放器菜单',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '完整设置',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.58),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _tabScrollController,
                padding: const EdgeInsets.only(bottom: 58),
                itemExtent: 62,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return NipaplayLargeScreenPlayerMenuTab(
                    icon: entry.icon,
                    title: entry.title,
                    category: entry.categoryTitle,
                    selected: entry.samePaneAs(selectedEntry),
                    focused: !_isContentFocused && index == _focusedTabIndex,
                    onTap: () => _selectTab(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    VideoPlayerState videoState,
    _PlayerMenuTabEntry selectedEntry,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 54, 18, 52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedEntry.title,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        selectedEntry.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.58),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '← 返回分类  ·  菜单键关闭',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.48),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: widget.isDarkMode ? Colors.white12 : Colors.black12,
          ),
          Expanded(
            child: FocusScope(
              node: _contentFocusScope,
              canRequestFocus: _isContentFocused,
              descendantsAreFocusable: _isContentFocused,
              child: selectedEntry.paneId == null
                  ? _PlayerMenuActionsPane(
                      videoState: videoState,
                      onExitPlayback: widget.onExitPlayback,
                      onSendDanmaku: widget.onSendDanmaku,
                      onRequestClose: widget.onRequestClose,
                    )
                  : NipaplayLargeScreenPlayerMenuPaneHost(
                      paneId: selectedEntry.paneId!,
                      videoState: videoState,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  _PlayerMenuTabEntry _resolveSelectedEntry(
    List<_PlayerMenuTabEntry> entries,
  ) {
    for (final entry in entries) {
      if (entry.paneId == _selectedPaneId) {
        return entry;
      }
    }
    return entries.first;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final command = NipaplayLargeScreenInputControls.fromKeyEvent(event);
    if (command == null) {
      return KeyEventResult.ignored;
    }
    switch (command) {
      case NipaplayLargeScreenInputCommand.toggleMenu:
      case NipaplayLargeScreenInputCommand.back:
        widget.onRequestClose();
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.navigateUp:
        if (_isContentFocused) {
          _moveContentVerticalFocus(reverse: true);
        } else {
          _moveTabFocus(-1);
        }
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.navigateDown:
        if (_isContentFocused) {
          _moveContentVerticalFocus(reverse: false);
        } else {
          _moveTabFocus(1);
        }
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.navigateLeft:
        if (_isContentFocused) {
          _setContentFocused(false);
        }
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.navigateRight:
        if (_isContentFocused) {
          _moveContentFocus(TraversalDirection.right);
        } else {
          _setContentFocused(true);
        }
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.activate:
        if (_isContentFocused) {
          _activateContentFocus();
        } else {
          _setContentFocused(true);
        }
        return KeyEventResult.handled;
    }
  }

  void _moveTabFocus(int delta) {
    if (_latestEntries.isEmpty) return;
    final next = (_focusedTabIndex + delta).clamp(
      0,
      _latestEntries.length - 1,
    );
    if (next == _focusedTabIndex) return;
    setState(() {
      _focusedTabIndex = next;
      _selectedPaneId = _latestEntries[next].paneId;
      _lastContentFocusNode = null;
    });
    _revealFocusedTab();
  }

  void _selectTab(int index) {
    if (_latestEntries.isEmpty) return;
    final next = index.clamp(0, _latestEntries.length - 1);
    setState(() {
      _focusedTabIndex = next;
      _selectedPaneId = _latestEntries[next].paneId;
      _isContentFocused = false;
      _lastContentFocusNode = null;
    });
    widget.initialFocusNode.requestFocus();
    _revealFocusedTab();
  }

  void _revealFocusedTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tabScrollController.hasClients) return;
      const itemExtent = 62.0;
      final position = _tabScrollController.position;
      final itemTop = _focusedTabIndex * itemExtent;
      final itemBottom = itemTop + itemExtent;
      var target = position.pixels;
      if (itemTop < position.pixels) {
        target = itemTop;
      } else if (itemBottom > position.pixels + position.viewportDimension) {
        target = itemBottom - position.viewportDimension;
      }
      target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 1) return;
      _tabScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _setContentFocused(bool value) {
    if (_isContentFocused == value) {
      if (value) {
        _requestContentFocusAfterFrame();
      } else {
        widget.initialFocusNode.requestFocus();
      }
      return;
    }
    if (!value) {
      final primaryFocus = FocusManager.instance.primaryFocus;
      if (_isFocusInsideContentScope(primaryFocus) &&
          !identical(primaryFocus, _contentFocusScope)) {
        _lastContentFocusNode = primaryFocus;
      }
    }
    setState(() => _isContentFocused = value);
    if (value) {
      _requestContentFocusAfterFrame();
    } else {
      widget.initialFocusNode.requestFocus();
    }
  }

  void _requestContentFocusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isContentFocused) return;
      if (!_ensureContentFocus()) {
        _setContentFocused(false);
      }
    });
  }

  bool _ensureContentFocus() {
    final currentFocus = FocusManager.instance.primaryFocus;
    if (_isUsableContentFocus(currentFocus)) {
      currentFocus!.requestFocus();
      return true;
    }

    final rememberedFocus = _lastContentFocusNode;
    if (_isUsableContentFocus(rememberedFocus)) {
      rememberedFocus!.requestFocus();
      _ensureFocusedControlVisible();
      return true;
    }

    for (final candidate in _contentFocusScope.traversalDescendants) {
      if (!_isUsableContentFocus(candidate)) continue;
      candidate.requestFocus();
      _lastContentFocusNode = candidate;
      _ensureFocusedControlVisible();
      return true;
    }

    // Information and loading panes may temporarily have no actionable
    // descendants. Keep the region active so one left press still returns to
    // the tab column and a later right press can pick up newly loaded controls.
    _contentFocusScope.requestFocus();
    return true;
  }

  bool _moveContentFocus(TraversalDirection direction) {
    if (!_isFocusInsideContentScope(FocusManager.instance.primaryFocus) &&
        !_ensureContentFocus()) {
      return false;
    }
    final fallback = FocusManager.instance.primaryFocus;
    final moved = fallback == null || identical(fallback, _contentFocusScope)
        ? _contentFocusScope.focusInDirection(direction)
        : fallback.focusInDirection(direction);
    if (!_isFocusInsideContentScope(FocusManager.instance.primaryFocus)) {
      _restoreContentFocus(fallback);
      return false;
    }
    _rememberAndRevealCurrentContentFocus();
    return moved;
  }

  bool _moveContentVerticalFocus({required bool reverse}) {
    if (!_isFocusInsideContentScope(FocusManager.instance.primaryFocus) &&
        !_ensureContentFocus()) {
      return false;
    }
    final fallback = FocusManager.instance.primaryFocus;
    final focused = fallback == null || identical(fallback, _contentFocusScope)
        ? null
        : fallback;
    final moved = reverse
        ? (focused?.previousFocus() ?? _contentFocusScope.previousFocus())
        : (focused?.nextFocus() ?? _contentFocusScope.nextFocus());
    if (!_isFocusInsideContentScope(FocusManager.instance.primaryFocus)) {
      _restoreContentFocus(fallback);
      return false;
    }
    if (!moved) {
      _jumpContentScrollBoundary(
        reverse ? TraversalDirection.up : TraversalDirection.down,
      );
    }
    _rememberAndRevealCurrentContentFocus();
    return moved;
  }

  bool _isFocusInsideContentScope(FocusNode? node) {
    if (node == null) return false;
    if (identical(node, _contentFocusScope)) return true;
    return node.ancestors.contains(_contentFocusScope);
  }

  bool _isUsableContentFocus(FocusNode? node) {
    return node != null &&
        node is! FocusScopeNode &&
        !identical(node, _contentFocusScope) &&
        _isFocusInsideContentScope(node) &&
        node.canRequestFocus &&
        !node.skipTraversal &&
        node.context != null;
  }

  void _rememberAndRevealCurrentContentFocus() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (_isUsableContentFocus(primaryFocus)) {
      _lastContentFocusNode = primaryFocus;
    }
    _ensureFocusedControlVisible();
  }

  void _ensureFocusedControlVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isContentFocused) return;
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (focusContext == null) return;
      Scrollable.ensureVisible(
        focusContext,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  void _restoreContentFocus(FocusNode? fallback) {
    if (fallback != null &&
        _isFocusInsideContentScope(fallback) &&
        fallback.canRequestFocus &&
        fallback.context != null) {
      fallback.requestFocus();
      return;
    }
    _ensureContentFocus();
  }

  void _jumpContentScrollBoundary(TraversalDirection direction) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final scrollController =
        PrimaryScrollController.maybeOf(focusContext ?? context);
    if (scrollController == null || !scrollController.hasClients) return;
    final target = direction == TraversalDirection.up
        ? scrollController.position.minScrollExtent
        : scrollController.position.maxScrollExtent;
    scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _activateContentFocus() {
    final focused = FocusManager.instance.primaryFocus;
    if (!_isUsableContentFocus(focused)) {
      _ensureContentFocus();
      return;
    }
    final nodeContext = focused!.context;
    if (nodeContext == null) return;
    Actions.maybeInvoke<ActivateIntent>(nodeContext, const ActivateIntent());
  }
}

class _PlayerMenuActionsPane extends StatelessWidget {
  const _PlayerMenuActionsPane({
    required this.videoState,
    required this.onExitPlayback,
    required this.onSendDanmaku,
    required this.onRequestClose,
  });

  final VideoPlayerState videoState;
  final VoidCallback onExitPlayback;
  final VoidCallback onSendDanmaku;
  final VoidCallback onRequestClose;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: [
        NipaplayLargeScreenPlayerMenuSection(
          header: const Text('播放操作'),
          children: [
            NipaplayLargeScreenPlayerMenuTile(
              leading: const Icon(Icons.arrow_back_rounded),
              title: const Text('返回媒体库'),
              subtitle: const Text('结束当前播放并返回媒体库'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onActivate: onExitPlayback,
            ),
            if (videoState.playerTopSendDanmakuButtonVisible)
              NipaplayLargeScreenPlayerMenuTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded),
                title: const Text('发送弹幕'),
                subtitle: const Text('输入并发送一条弹幕'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onActivate: onSendDanmaku,
              ),
            NipaplayLargeScreenPlayerMenuTile(
              leading: const Icon(Icons.subtitles_rounded),
              title: const Text('显示弹幕'),
              subtitle: Text(videoState.danmakuVisible ? '当前已显示' : '当前已关闭'),
              trailing: FluentSettingsSwitch(
                value: videoState.danmakuVisible,
                onChanged: (_) => videoState.toggleDanmakuVisible(),
              ),
              onActivate: videoState.toggleDanmakuVisible,
            ),
          ],
        ),
        NipaplayLargeScreenPlayerMenuSection(
          header: const Text('菜单'),
          children: [
            NipaplayLargeScreenPlayerMenuTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('关闭播放器菜单'),
              subtitle: const Text('也可以再次按遥控器菜单键'),
              onActivate: onRequestClose,
            ),
          ],
        ),
      ],
    );
  }
}

class _PlayerMenuTabEntry {
  const _PlayerMenuTabEntry.actions()
      : definition = null,
        paneId = null;

  _PlayerMenuTabEntry.definition(PlayerMenuItemDefinition definition)
      : definition = definition,
        paneId = definition.paneId;

  final PlayerMenuItemDefinition? definition;
  final PlayerMenuPaneId? paneId;

  String get title => definition?.title ?? '常用操作';

  String get categoryTitle =>
      definition == null ? '播放' : _categoryTitle(definition!.category);

  String get description => definition == null
      ? '退出播放、发送弹幕和显示开关'
      : _paneDescription(definition!.paneId);

  IconData get icon =>
      definition == null ? Icons.tune_rounded : _iconFor(definition!.icon);

  bool samePaneAs(_PlayerMenuTabEntry other) => paneId == other.paneId;

  static String _categoryTitle(PlayerMenuCategory category) {
    switch (category) {
      case PlayerMenuCategory.playbackControl:
        return '播放控制';
      case PlayerMenuCategory.video:
        return '视频';
      case PlayerMenuCategory.audio:
        return '音频';
      case PlayerMenuCategory.subtitle:
        return '字幕';
      case PlayerMenuCategory.danmaku:
        return '弹幕';
      case PlayerMenuCategory.player:
        return '播放器';
      case PlayerMenuCategory.streaming:
        return '串流';
      case PlayerMenuCategory.info:
        return '信息';
    }
  }

  static String _paneDescription(PlayerMenuPaneId paneId) {
    switch (paneId) {
      case PlayerMenuPaneId.subtitleSettings:
        return '字幕大小、延迟、位置、颜色、字体和样式';
      case PlayerMenuPaneId.subtitleTracks:
        return '选择内嵌、外部或远程字幕轨道';
      case PlayerMenuPaneId.subtitleList:
        return '浏览字幕内容并跳转到对应时间';
      case PlayerMenuPaneId.audioTracks:
        return '选择本地或服务器音频轨道';
      case PlayerMenuPaneId.danmakuSettings:
        return '完整弹幕显示、样式、屏蔽和导出设置';
      case PlayerMenuPaneId.danmakuTracks:
        return '管理和启用不同来源的弹幕轨道';
      case PlayerMenuPaneId.danmakuList:
        return '浏览弹幕内容并跳转到对应时间';
      case PlayerMenuPaneId.danmakuOffset:
        return '修正弹幕与视频之间的同步差异';
      case PlayerMenuPaneId.playbackRate:
        return '选择预设或输入精确播放速度';
      case PlayerMenuPaneId.playlist:
        return '浏览并切换当前播放列表';
      case PlayerMenuPaneId.jellyfinQuality:
        return '选择服务器媒体源、转码质量和字幕';
      case PlayerMenuPaneId.playbackInfo:
        return '查看当前媒体、弹幕和播放状态';
      case PlayerMenuPaneId.seekStep:
        return '设置快进快退、长按倍速和跳过时间';
    }
  }

  static IconData _iconFor(PlayerMenuIconToken token) {
    switch (token) {
      case PlayerMenuIconToken.subtitleSettings:
        return Icons.text_fields_rounded;
      case PlayerMenuIconToken.subtitles:
        return Icons.subtitles_rounded;
      case PlayerMenuIconToken.subtitleList:
        return Icons.format_list_bulleted_rounded;
      case PlayerMenuIconToken.audioTrack:
        return Icons.audiotrack_rounded;
      case PlayerMenuIconToken.danmakuSettings:
        return Icons.chat_bubble_outline_rounded;
      case PlayerMenuIconToken.danmakuTracks:
        return Icons.dynamic_feed_rounded;
      case PlayerMenuIconToken.danmakuList:
        return Icons.view_list_rounded;
      case PlayerMenuIconToken.danmakuOffset:
        return Icons.timer_rounded;
      case PlayerMenuIconToken.playbackRate:
        return Icons.speed_rounded;
      case PlayerMenuIconToken.playlist:
        return Icons.playlist_play_rounded;
      case PlayerMenuIconToken.jellyfinQuality:
        return Icons.high_quality_rounded;
      case PlayerMenuIconToken.playbackInfo:
        return Icons.info_outline_rounded;
      case PlayerMenuIconToken.seekStep:
        return Icons.skip_next_rounded;
    }
  }
}
