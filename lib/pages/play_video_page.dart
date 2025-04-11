import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/video_player_widget.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../widgets/tooltip_bubble.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import '../widgets/vertical_indicator.dart';
import '../services/dandanplay_service.dart';
import '../widgets/danmaku_overlay.dart';
import '../utils/globals.dart' as globals;

class PlayVideoPage extends StatefulWidget {
  final String? videoPath;
  
  const PlayVideoPage({super.key, this.videoPath});

  @override
  State<PlayVideoPage> createState() => _PlayVideoPageState();
}

class _PlayVideoPageState extends State<PlayVideoPage> {
  bool _isBackButtonHovered = false;
  bool _isBackButtonPressed = false;
  String? _animeTitle;
  String? _episodeTitle;
  bool _isLoadingInfo = false;
  String? _episodeId;

  @override
  void initState() {
    super.initState();
    _loadVideoInfo();
  }

  Future<void> _loadVideoInfo() async {
    if (widget.videoPath == null) return;

    setState(() {
      _isLoadingInfo = true;
    });

    try {
      // 获取视频信息
      final videoInfo = await DandanplayService.getVideoInfo(widget.videoPath!);
      
      if (videoInfo['isMatched'] == true && videoInfo['matches'] != null && videoInfo['matches'].isNotEmpty) {
        final match = videoInfo['matches'][0];
        setState(() {
          _animeTitle = videoInfo['animeTitle'];
          _episodeTitle = videoInfo['episodeTitle'];
          _episodeId = match['episodeId'].toString();
        });

        // 获取弹幕
        if (_episodeId != null && match['animeId'] != null) {
          final animeId = match['animeId'] as int;
          final danmakuInfo = await DandanplayService.getDanmaku(
            _episodeId!,
            animeId,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已加载 ${danmakuInfo['count']} 条弹幕')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法识别该视频')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载视频信息失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoadingInfo = false;
      });
    }
  }

  double getFontSize() {
    if (globals.isPhone) {
      return 20.0;
    } else {
      return 30.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          color: videoState.hasVideo 
              ? Colors.black 
              : Colors.transparent,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                const VideoPlayerWidget(),
                if (_isLoadingInfo)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
                if (_animeTitle != null && _episodeTitle != null)
                  Positioned(
                    top: 16,
                    left: 80,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: videoState.showControls ? 1.0 : 0.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _animeTitle!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _episodeTitle!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (videoState.hasVideo) ...[
                  Positioned.fill(
                    child: Consumer<VideoPlayerState>(
                      builder: (context, videoState, _) {
                        if (!videoState.danmakuVisible) {
                          return const SizedBox.shrink();
                        }
                        return DanmakuOverlay(
                          danmakuList: videoState.danmakuList,
                          currentPosition: videoState.position.inMilliseconds.toDouble(),
                          videoDuration: videoState.videoDuration.inMilliseconds.toDouble(),
                          isPlaying: videoState.status == PlayerStatus.playing,
                          fontSize: getFontSize(),
                          isVisible: videoState.danmakuVisible,
                          opacity: videoState.mappedDanmakuOpacity,
                        );
                      },
                    ),
                  ),
                  Consumer<VideoPlayerState>(
                    builder: (context, videoState, _) {
                      return VerticalIndicator(videoState: videoState);
                    },
                  ),
                ],
                if (videoState.hasVideo && !(globals.isDesktop && videoState.isFullscreen))
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: videoState.showControls ? 1.0 : 0.0,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: MouseRegion(
                        onEnter: (_) {
                          setState(() => _isBackButtonHovered = true);
                          videoState.setControlsHovered(true);
                        },
                        onExit: (_) {
                          setState(() => _isBackButtonHovered = false);
                          videoState.setControlsHovered(false);
                        },
                        child: TooltipBubble(
                          text: '返回',
                          showOnRight: true,
                          verticalOffset: 8,
                          child: GestureDetector(
                            onTapDown: (_) => setState(() => _isBackButtonPressed = true),
                            onTapUp: (_) async {
                              setState(() => _isBackButtonPressed = false);
                              try {
                                // 重置播放器状态
                                await videoState.resetPlayer();
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('重置播放器时出错: $e')),
                                  );
                                }
                              }
                            },
                            onTapCancel: () => setState(() => _isBackButtonPressed = false),
                            child: GlassmorphicContainer(
                              width: 48,
                              height: 48,
                              borderRadius: 25,
                              blur: 30,
                              alignment: Alignment.center,
                              border: 1,
                              linearGradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFFffffff).withOpacity(0.2),
                                  const Color(0xFFFFFFFF).withOpacity(0.2),
                                ],
                              ),
                              borderGradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFFffffff).withOpacity(0.5),
                                  const Color((0xFFFFFFFF)).withOpacity(0.5),
                                ],
                              ),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _isBackButtonHovered ? 1.0 : 0.6,
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 100),
                                  scale: _isBackButtonPressed ? 0.9 : 1.0,
                                  child: const Icon(
                                    Ionicons.chevron_back_outline,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
} 