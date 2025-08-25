import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

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
                                  color: FluentTheme.of(context).resources.solidBackgroundFillColorTertiary,
                                  border: Border(
                                    bottom: BorderSide(
                                      color: FluentTheme.of(context).resources.controlStrokeColorDefault,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  '播放设置',
                                  style: FluentTheme.of(context).typography.bodyStrong,
                                ),
                              ),
                              // 菜单内容区域
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.all(8),
                                  children: [
                                    _buildMenuGroup('视频', [
                                      _buildMenuItem('画质设置', FluentIcons.video, () {
                                        // TODO: 打开画质设置
                                      }),
                                      _buildMenuItem('播放速度', FluentIcons.clock, () {
                                        // TODO: 打开播放速度设置
                                      }),
                                    ]),
                                    const SizedBox(height: 8),
                                    _buildMenuGroup('音频', [
                                      _buildMenuItem('音轨选择', FluentIcons.volume3, () {
                                        // TODO: 打开音轨选择
                                      }),
                                    ]),
                                    const SizedBox(height: 8),
                                    _buildMenuGroup('字幕', [
                                      _buildMenuItem('字幕轨道', FluentIcons.closed_caption, () {
                                        // TODO: 打开字幕轨道设置
                                      }),
                                    ]),
                                    const SizedBox(height: 8),
                                    _buildMenuGroup('弹幕', [
                                      _buildMenuItem('弹幕设置', FluentIcons.comment, () {
                                        // TODO: 打开弹幕设置
                                      }),
                                    ]),
                                    const SizedBox(height: 8),
                                    _buildMenuGroup('播放列表', [
                                      _buildMenuItem('播放列表', FluentIcons.playlist_music, () {
                                        // TODO: 打开播放列表
                                      }),
                                    ]),
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