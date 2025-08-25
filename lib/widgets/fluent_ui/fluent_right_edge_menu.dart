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
  String _currentView = 'main'; // main, video, audio, subtitle, danmaku, playlist
  final List<String> _navigationStack = ['main']; // 导航堆栈

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

  void _navigateTo(String view) {
    setState(() {
      _navigationStack.add(view);
      _currentView = view;
    });
  }

  void _navigateBack() {
    if (_navigationStack.length > 1) {
      setState(() {
        _navigationStack.removeLast();
        _currentView = _navigationStack.last;
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
                                  _getViewTitle(_currentView),
                                  style: FluentTheme.of(context).typography.bodyStrong,
                                ),
                              ),
                              // 菜单内容区域
                              Expanded(
                                child: Column(
                                  children: [
                                    // 返回按钮区域
                                    if (_currentView != 'main')
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
                                      child: _buildCurrentView(videoState),
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

  String _getViewTitle(String view) {
    switch (view) {
      case 'main':
        return '播放设置';
      case 'video':
        return '视频设置';
      case 'audio':
        return '音频设置';
      case 'subtitle':
        return '字幕设置';
      case 'danmaku':
        return '弹幕设置';
      case 'playlist':
        return '播放列表';
      case 'playback_rate':
        return '播放速度';
      case 'subtitle_tracks':
        return '字幕轨道';
      case 'audio_tracks':
        return '音频轨道';
      case 'danmaku_tracks':
        return '弹幕轨道';
      case 'danmaku_list':
        return '弹幕列表';
      case 'subtitle_list':
        return '字幕列表';
      case 'danmaku_offset':
        return '弹幕偏移';
      default:
        return '播放设置';
    }
  }

  Widget _buildCurrentView(VideoPlayerState videoState) {
    switch (_currentView) {
      case 'main':
        return _buildMainMenu(videoState);
      case 'video':
        return _buildVideoMenu(videoState);
      case 'audio':
        return _buildAudioMenu(videoState);
      case 'subtitle':
        return _buildSubtitleMenu(videoState);
      case 'danmaku':
        return _buildDanmakuMenu(videoState);
      case 'playlist':
        return _buildPlaylistMenu(videoState);
      case 'playback_rate':
        return _buildPlaybackRateMenu(videoState);
      case 'subtitle_tracks':
        return _buildSubtitleTracksMenu(videoState);
      case 'audio_tracks':
        return _buildAudioTracksMenu(videoState);
      case 'danmaku_tracks':
        return _buildDanmakuTracksMenu(videoState);
      case 'danmaku_list':
        return _buildDanmakuListMenu(videoState);
      case 'subtitle_list':
        return _buildSubtitleListMenu(videoState);
      case 'danmaku_offset':
        return _buildDanmakuOffsetMenu(videoState);
      default:
        return _buildMainMenu(videoState);
    }
  }

  Widget _buildMainMenu(VideoPlayerState videoState) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _buildMenuGroup('视频', [
          _buildMenuItem('播放速度', FluentIcons.clock, () {
            _navigateTo('playback_rate');
          }),
        ]),
        const SizedBox(height: 8),
        _buildMenuGroup('音频', [
          _buildMenuItem('音频轨道', FluentIcons.volume3, () {
            _navigateTo('audio_tracks');
          }),
        ]),
        const SizedBox(height: 8),
        _buildMenuGroup('字幕', [
          _buildMenuItem('字幕轨道', FluentIcons.closed_caption, () {
            _navigateTo('subtitle_tracks');
          }),
          _buildMenuItem('字幕列表', FluentIcons.list, () {
            _navigateTo('subtitle_list');
          }),
        ]),
        const SizedBox(height: 8),
        _buildMenuGroup('弹幕', [
          _buildMenuItem('弹幕设置', FluentIcons.comment, () {
            _navigateTo('danmaku');
          }),
          _buildMenuItem('弹幕轨道', FluentIcons.list, () {
            _navigateTo('danmaku_tracks');
          }),
          _buildMenuItem('弹幕列表', FluentIcons.list, () {
            _navigateTo('danmaku_list');
          }),
          _buildMenuItem('弹幕偏移', FluentIcons.clock, () {
            _navigateTo('danmaku_offset');
          }),
        ]),
        const SizedBox(height: 8),
        _buildMenuGroup('播放器', [
          if (videoState.currentVideoPath != null || videoState.animeId != null)
            _buildMenuItem('播放列表', FluentIcons.playlist_music, () {
              _navigateTo('playlist');
            }),
        ]),
      ],
    );
  }

  Widget _buildVideoMenu(VideoPlayerState videoState) {
    return const Center(
      child: Text('视频设置开发中...'),
    );
  }

  Widget _buildAudioMenu(VideoPlayerState videoState) {
    return const Center(
      child: Text('音频设置开发中...'),
    );
  }

  Widget _buildSubtitleMenu(VideoPlayerState videoState) {
    return const Center(
      child: Text('字幕设置开发中...'),
    );
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

  Widget _buildMenuItem(String title, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: HoverButton(
        onPressed: onTap,
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
                  icon,
                  size: 16,
                  color: FluentTheme.of(context).resources.textFillColorPrimary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
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
}