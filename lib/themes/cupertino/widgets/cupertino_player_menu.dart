import 'dart:collection';

import 'package:flutter/cupertino.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/player_menu/player_menu_definition_builder.dart';
import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_playback_info_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_playback_rate_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_seek_step_pane.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class CupertinoPlayerMenu extends StatefulWidget {
  const CupertinoPlayerMenu({super.key});

  @override
  State<CupertinoPlayerMenu> createState() => _CupertinoPlayerMenuState();
}

class _CupertinoPlayerMenuState extends State<CupertinoPlayerMenu> {
  PlayerMenuPaneId? _activePane;
  final List<PlayerMenuPaneId?> _navigationStack = [null];
  late final PlayerKernelType _currentKernelType;

  @override
  void initState() {
    super.initState();
    _currentKernelType = PlayerFactory.getKernelType();
  }

  void _openPane(PlayerMenuPaneId paneId) {
    if (_activePane == paneId) return;
    setState(() {
      _navigationStack.add(paneId);
      _activePane = paneId;
    });
  }

  void _navigateBack() {
    if (_navigationStack.length <= 1) return;
    setState(() {
      _navigationStack.removeLast();
      _activePane = _navigationStack.last;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        final menuItems = PlayerMenuDefinitionBuilder(
          context: PlayerMenuContext(
            videoState: videoState,
            kernelType: _currentKernelType,
          ),
        ).build();
        final Map<PlayerMenuPaneId, PlayerMenuItemDefinition> paneLookup = {
          for (final item in menuItems) item.paneId: item,
        };

        if (_activePane != null && !paneLookup.containsKey(_activePane)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _navigationStack
                ..clear()
                ..add(null);
              _activePane = null;
            });
          });
        }

        final Widget child = _activePane == null
            ? _CupertinoPlayerMenuHome(
                items: menuItems,
                onSelect: _openPane,
              )
            : _CupertinoPlayerMenuPaneView(
                pane: paneLookup[_activePane]!,
                onBack: _navigateBack,
                content: _buildPaneContent(_activePane!, videoState),
              );

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: ValueKey(_activePane ?? 'root'),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildPaneContent(
      PlayerMenuPaneId paneId, VideoPlayerState videoState) {
    switch (paneId) {
      case PlayerMenuPaneId.playbackRate:
        return ChangeNotifierProvider(
          create: (_) => PlaybackRatePaneController(videoState: videoState),
          child: const CupertinoPlaybackRatePane(),
        );
      case PlayerMenuPaneId.seekStep:
        return ChangeNotifierProvider(
          create: (_) => SeekStepPaneController(videoState: videoState),
          child: const CupertinoSeekStepPane(),
        );
      case PlayerMenuPaneId.playbackInfo:
        return CupertinoPlaybackInfoPane(videoState: videoState);
      default:
        return _CupertinoPlayerMenuPlaceholder(
          message: '该功能的 Cupertino 样式正在适配中，请使用其他主题或稍后再试。',
        );
    }
  }
}

class _CupertinoPlayerMenuHome extends StatelessWidget {
  const _CupertinoPlayerMenuHome({
    required this.items,
    required this.onSelect,
  });

  final List<PlayerMenuItemDefinition> items;
  final ValueChanged<PlayerMenuPaneId> onSelect;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return CupertinoBottomSheetContentLayout(
        sliversBuilder: (context, topSpacing) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                '当前无可用的设置项',
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
              ),
            ),
          ),
        ],
      );
    }

    final Map<PlayerMenuCategory, List<PlayerMenuItemDefinition>> grouped =
        LinkedHashMap();
    for (final item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    final slivers = <Widget>[];
    grouped.forEach((category, defs) {
      slivers.add(
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: Text(_categoryTitle(category)),
            children: defs
                .map(
                  (item) => CupertinoListTile(
                    leading: Icon(
                      _iconFor(item.icon),
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                    title: Text(item.title),
                    trailing: const Icon(CupertinoIcons.chevron_right),
                    onTap: () => onSelect(item.paneId),
                  ),
                )
                .toList(),
          ),
        ),
      );
    });

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.only(top: topSpacing, bottom: 12),
          sliver: SliverList(
            delegate: SliverChildListDelegate(slivers),
          ),
        ),
      ],
    );
  }

  String _categoryTitle(PlayerMenuCategory category) {
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

  IconData _iconFor(PlayerMenuIconToken token) {
    switch (token) {
      case PlayerMenuIconToken.subtitles:
        return CupertinoIcons.captions_bubble;
      case PlayerMenuIconToken.subtitleList:
        return CupertinoIcons.square_list;
      case PlayerMenuIconToken.audioTrack:
        return CupertinoIcons.music_note;
      case PlayerMenuIconToken.danmakuSettings:
        return CupertinoIcons.bubble_right;
      case PlayerMenuIconToken.danmakuTracks:
        return CupertinoIcons.bubble_right_fill;
      case PlayerMenuIconToken.danmakuList:
        return CupertinoIcons.list_bullet;
      case PlayerMenuIconToken.danmakuOffset:
        return CupertinoIcons.clock;
      case PlayerMenuIconToken.controlBarSettings:
        return CupertinoIcons.slider_horizontal_3;
      case PlayerMenuIconToken.playbackRate:
        return CupertinoIcons.speedometer;
      case PlayerMenuIconToken.playlist:
        return CupertinoIcons.square_stack_3d_up;
      case PlayerMenuIconToken.jellyfinQuality:
        return CupertinoIcons.tv;
      case PlayerMenuIconToken.playbackInfo:
        return CupertinoIcons.info;
      case PlayerMenuIconToken.seekStep:
        return CupertinoIcons.settings;
    }
  }
}

class _CupertinoPlayerMenuPaneView extends StatelessWidget {
  const _CupertinoPlayerMenuPaneView({
    required this.pane,
    required this.onBack,
    required this.content,
  });

  final PlayerMenuItemDefinition pane;
  final VoidCallback onBack;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: CupertinoNavigationBar(
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: onBack,
              child: const Icon(CupertinoIcons.chevron_back),
            ),
            middle: Text(pane.title),
            border: null,
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _CupertinoPlayerMenuPlaceholder extends StatelessWidget {
  const _CupertinoPlayerMenuPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
