import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'fluent_playback_rate_menu.dart';
import 'fluent_audio_tracks_menu.dart';
import 'fluent_subtitle_tracks_menu.dart';
import 'fluent_subtitle_list_menu.dart';
import 'fluent_danmaku_settings_menu.dart';
import 'fluent_danmaku_tracks_menu.dart';
import 'fluent_danmaku_list_menu.dart';
import 'fluent_danmaku_offset_menu.dart';
import 'fluent_playlist_menu.dart';
import 'package:nipaplay/player_menu/player_menu_definition_builder.dart';
import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';

class FluentRightEdgeMenu extends StatefulWidget {
  const FluentRightEdgeMenu({super.key});

  @override
  State<FluentRightEdgeMenu> createState() => _FluentRightEdgeMenuState();
}

class _FluentRightEdgeMenuState extends State<FluentRightEdgeMenu>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isMenuVisible = false;
  Timer? _hideTimer;
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  // 导航系统状态
  PlayerMenuPaneId? _currentPane;
  final List<PlayerMenuPaneId?> _navigationStack = [null];

  static const Set<PlayerMenuPaneId> _supportedPaneIds = {
    PlayerMenuPaneId.seekStep,
    PlayerMenuPaneId.playbackRate,
    PlayerMenuPaneId.audioTracks,
    PlayerMenuPaneId.subtitleTracks,
    PlayerMenuPaneId.subtitleList,
    PlayerMenuPaneId.danmakuSettings,
    PlayerMenuPaneId.danmakuTracks,
    PlayerMenuPaneId.danmakuList,
    PlayerMenuPaneId.danmakuOffset,
    PlayerMenuPaneId.playlist,
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 1.0, // 完全隐藏在右侧
      end: 0.0,   // 完全显示
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _showMenu() {
    if (!_isMenuVisible) {
      setState(() {
        _isMenuVisible = true;
      });
      _animationController.forward();
    }
    _hideTimer?.cancel();
  }

  void _hideMenu() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_isHovered) {
        final videoState = Provider.of<VideoPlayerState>(context, listen: false);
        videoState.setShowRightMenu(false);
      }
    });
  }

  void _navigateTo(PlayerMenuPaneId paneId) {
    setState(() {
      _navigationStack.add(paneId);
      _currentPane = paneId;
    });
  }

  void _navigateBack() {
    if (_navigationStack.length > 1) {
      setState(() {
        _navigationStack.removeLast();
        _currentPane = _navigationStack.last;
      });
    }
  }

  void _hideMenuDirectly() {
    _hideTimer?.cancel();
    _animationController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isMenuVisible = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // 只在有视频且非手机平台时显示
        if (!videoState.hasVideo || globals.isPhone) {
          return const SizedBox.shrink();
        }

        // 使用WidgetsBinding.instance.addPostFrameCallback来延迟执行setState
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            // 响应VideoPlayerState的showRightMenu状态
            if (videoState.showRightMenu && !_isMenuVisible) {
              _showMenu();
            } else if (!videoState.showRightMenu && _isMenuVisible) {
              _hideMenuDirectly();
            }
          }
        });

        final menuItems = PlayerMenuDefinitionBuilder(
          context: PlayerMenuContext(
            videoState: videoState,
            kernelType: PlayerFactory.getKernelType(),
          ),
          supportedPaneIds: _supportedPaneIds,
        ).build();
        final paneLookup = {
          for (final item in menuItems) item.paneId: item,
        };
        final currentTitle = _currentPane == null
            ? '播放设置'
            : paneLookup[_currentPane!]?.title ?? '播放设置';

        if (_currentPane != null && !paneLookup.containsKey(_currentPane)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _currentPane = null;
                _navigationStack
                  ..clear()
                  ..add(null);
              });
            }
          });
        }

        return Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: MouseRegion(
            onEnter: (_) {
              setState(() {
                _isHovered = true;
              });
              // 鼠标悬浮时如果菜单未显示，则显示菜单并更新状态
              if (!videoState.showRightMenu) {
                videoState.setShowRightMenu(true);
              }
            },
            onExit: (_) {
              setState(() {
                _isHovered = false;
              });
              // 鼠标离开时延迟隐藏菜单
              _hideMenu();
            },
            child: Stack(
              children: [
                // 触发区域 - 始终存在的细条
                Container(
                  width: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: _isHovered || videoState.showRightMenu ? 0.15 : 0.05),
                      ],
                    ),
                  ),
                ),
                // 菜单内容 - FluentUI风格，贴边显示
                if (_isMenuVisible)
                  AnimatedBuilder(
                    animation: _slideAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(
                          _slideAnimation.value * 280, // 菜单宽度
                          0,
                        ),
                        child: Container(
                          width: 280,
                          decoration: BoxDecoration(
                            color: FluentTheme.of(context).resources.solidBackgroundFillColorSecondary,
                            border: Border(
                              left: BorderSide(
                                color: FluentTheme.of(context).resources.controlStrokeColorDefault,
                                width: 1,
                              ),
                              top: BorderSide(
                                color: FluentTheme.of(context).resources.controlStrokeColorDefault,
                                width: 1,
                              ),
                              bottom: BorderSide(
                                color: FluentTheme.of(context).resources.controlStrokeColorDefault,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Column(
                            children: [
                              // 菜单标题
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: FluentTheme.of(context).resources.solidBackgroundFillColorSecondary,
                                  border: Border(
                                    bottom: BorderSide(
                                      color: FluentTheme.of(context).resources.controlStrokeColorDefault,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  currentTitle,
                                  style: FluentTheme.of(context).typography.bodyStrong,
                                ),
                              ),
                              // 菜单内容区域
                              Expanded(
                                child: Column(
                                  children: [
                                    // 返回按钮区域
                                    if (_currentPane != null)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(8),
                                        child: HoverButton(
                                          onPressed: _navigateBack,
                                          builder: (context, states) {
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: states.isHovered
                                                    ? FluentTheme.of(context).resources.subtleFillColorSecondary
                                                    : Colors.transparent,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    FluentIcons.back,
                                                    size: 16,
                                                    color: FluentTheme.of(context).resources.textFillColorPrimary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '返回',
                                                    style: FluentTheme.of(context).typography.body?.copyWith(
                                                      color: FluentTheme.of(context).resources.textFillColorPrimary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                    ),
                                    // 菜单内容
                                    Expanded(
                                      child: _buildCurrentView(videoState, menuItems),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentView(
      VideoPlayerState videoState, List<PlayerMenuItemDefinition> menuItems) {
    if (_currentPane == null) {
      return _buildMainMenu(videoState, menuItems);
    }

    switch (_currentPane!) {
      case PlayerMenuPaneId.seekStep:
        return _buildSeekStepMenu(videoState);
      case PlayerMenuPaneId.playbackRate:
        return _buildPlaybackRateMenu(videoState);
      case PlayerMenuPaneId.audioTracks:
        return _buildAudioTracksMenu(videoState);
      case PlayerMenuPaneId.subtitleTracks:
        return _buildSubtitleTracksMenu(videoState);
      case PlayerMenuPaneId.subtitleList:
        return _buildSubtitleListMenu(videoState);
      case PlayerMenuPaneId.danmakuSettings:
        return _buildDanmakuMenu(videoState);
      case PlayerMenuPaneId.danmakuTracks:
        return _buildDanmakuTracksMenu(videoState);
      case PlayerMenuPaneId.danmakuList:
        return _buildDanmakuListMenu(videoState);
      case PlayerMenuPaneId.danmakuOffset:
        return _buildDanmakuOffsetMenu(videoState);
      case PlayerMenuPaneId.playlist:
        return _buildPlaylistMenu(videoState);
      default:
        return _buildMainMenu(videoState, menuItems);
    }
  }

  Widget _buildMainMenu(
      VideoPlayerState videoState, List<PlayerMenuItemDefinition> items) {
    final Map<PlayerMenuCategory, List<PlayerMenuItemDefinition>> grouped = {};
    for (final item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    final children = <Widget>[];
    grouped.forEach((category, definitions) {
      children.add(
        _buildMenuGroup(
          _categoryTitle(category),
          definitions.map(_buildMenuItem).toList(growable: false),
        ),
      );
      children.add(const SizedBox(height: 8));
    });
    if (children.isNotEmpty) {
      children.removeLast();
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: children,
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

  Widget _buildDanmakuMenu(VideoPlayerState videoState) {
    return FluentDanmakuSettingsMenu(videoState: videoState);
  }

  Widget _buildPlaylistMenu(VideoPlayerState videoState) {
    return FluentPlaylistMenu(videoState: videoState);
  }

  Widget _buildPlaybackRateMenu(VideoPlayerState videoState) {
    return FluentPlaybackRateMenu(videoState: videoState);
  }

  Widget _buildSubtitleTracksMenu(VideoPlayerState videoState) {
    return FluentSubtitleTracksMenu(videoState: videoState);
  }

  Widget _buildAudioTracksMenu(VideoPlayerState videoState) {
    return FluentAudioTracksMenu(videoState: videoState);
  }

  Widget _buildDanmakuTracksMenu(VideoPlayerState videoState) {
    return FluentDanmakuTracksMenu(videoState: videoState);
  }

  Widget _buildDanmakuListMenu(VideoPlayerState videoState) {
    return FluentDanmakuListMenu(videoState: videoState);
  }

  Widget _buildSubtitleListMenu(VideoPlayerState videoState) {
    return FluentSubtitleListMenu(videoState: videoState);
  }

  Widget _buildDanmakuOffsetMenu(VideoPlayerState videoState) {
    return FluentDanmakuOffsetMenu(videoState: videoState);
  }

  Widget _buildSeekStepMenu(VideoPlayerState videoState) {
    final List<int> seekStepOptions = [5, 10, 15, 30, 60]; // 可选的秒数
    
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            '选择快进快退时间',
            style: FluentTheme.of(context).typography.body?.copyWith(
              color: FluentTheme.of(context).resources.textFillColorSecondary,
            ),
          ),
        ),
        ...seekStepOptions.map((seconds) {
          final isSelected = videoState.seekStepSeconds == seconds;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: HoverButton(
              onPressed: () {
                videoState.setSeekStepSeconds(seconds);
              },
              builder: (context, states) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
                        : states.isHovered
                            ? FluentTheme.of(context).resources.subtleFillColorSecondary
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: isSelected
                        ? Border.all(
                            color: FluentTheme.of(context).accentColor,
                            width: 1,
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? FluentIcons.radio_btn_on : FluentIcons.radio_btn_off,
                        size: 16,
                        color: isSelected
                            ? FluentTheme.of(context).accentColor
                            : FluentTheme.of(context).resources.textFillColorPrimary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$seconds秒',
                          style: FluentTheme.of(context).typography.body?.copyWith(
                            color: isSelected
                                ? FluentTheme.of(context).accentColor
                                : FluentTheme.of(context).resources.textFillColorPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMenuGroup(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            title,
            style: FluentTheme.of(context).typography.caption?.copyWith(
              color: FluentTheme.of(context).resources.textFillColorSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...items,
      ],
    );
  }

  Widget _buildMenuItem(PlayerMenuItemDefinition item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: HoverButton(
        onPressed: () => _navigateTo(item.paneId),
        builder: (context, states) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: states.isHovered
                  ? FluentTheme.of(context).resources.subtleFillColorSecondary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  _iconFor(item.icon),
                  size: 16,
                  color: FluentTheme.of(context).resources.textFillColorPrimary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    style: FluentTheme.of(context).typography.body?.copyWith(
                      color: FluentTheme.of(context).resources.textFillColorPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(PlayerMenuIconToken icon) {
    switch (icon) {
      case PlayerMenuIconToken.subtitles:
        return FluentIcons.closed_caption;
      case PlayerMenuIconToken.subtitleList:
        return FluentIcons.list;
      case PlayerMenuIconToken.audioTrack:
        return FluentIcons.volume3;
      case PlayerMenuIconToken.danmakuSettings:
        return FluentIcons.comment;
      case PlayerMenuIconToken.danmakuTracks:
        return FluentIcons.list;
      case PlayerMenuIconToken.danmakuList:
        return FluentIcons.list;
      case PlayerMenuIconToken.danmakuOffset:
        return FluentIcons.clock;
      case PlayerMenuIconToken.controlBarSettings:
        return FluentIcons.settings;
      case PlayerMenuIconToken.playbackRate:
        return FluentIcons.clock;
      case PlayerMenuIconToken.playlist:
        return FluentIcons.playlist_music;
      case PlayerMenuIconToken.jellyfinQuality:
        return FluentIcons.playlist_music;
      case PlayerMenuIconToken.playbackInfo:
        return FluentIcons.info;
      case PlayerMenuIconToken.seekStep:
        return FluentIcons.settings;
    }
  }
}
