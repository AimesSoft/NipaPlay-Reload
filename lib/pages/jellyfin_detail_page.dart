import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/widgets/nipaplay_theme/cached_network_image_widget.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/switchable_view.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/jellyfin_dandanplay_matcher.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart'; // 导入TabChangeNotifier
import 'package:nipaplay/widgets/nipaplay_theme/blur_button.dart';

class JellyfinDetailPage extends StatefulWidget {
  final String jellyfinId;

  const JellyfinDetailPage({super.key, required this.jellyfinId});

  @override
  State<JellyfinDetailPage> createState() => _JellyfinDetailPageState();
  
  static Future<WatchHistoryItem?> show(BuildContext context, String jellyfinId) {
    // 获取外观设置Provider
    final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context, listen: false);
    final enableAnimation = appearanceSettings.enablePageAnimation;
    
    return showGeneralDialog<WatchHistoryItem>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierLabel: '关闭详情页',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return JellyfinDetailPage(jellyfinId: jellyfinId);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        // 如果禁用动画，直接返回child
        if (!enableAnimation) {
          return FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: child,
          );
        }
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }
}

class _JellyfinDetailPageState extends State<JellyfinDetailPage> with SingleTickerProviderStateMixin {
  // 静态Map，用于存储Jellyfin视频的哈希值（ID -> 哈希值）
  static final Map<String, String> _jellyfinVideoHashes = {};
  static final Map<String, Map<String, dynamic>> _jellyfinVideoInfos = {};
  
  JellyfinMediaItemDetail? _mediaDetail;
  List<JellyfinSeasonInfo> _seasons = [];
  final Map<String, List<JellyfinEpisodeInfo>> _episodesBySeasonId = {};
  String? _selectedSeasonId;
  bool _isLoading = true;
  String? _error;
  bool _isMovie = false; // 新增状态，判断是否为电影

  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _loadMediaDetail();
    // _tabController = TabController(length: 2, vsync: this); // 延迟到加载后初始化
    // _tabController!.addListener(() {
    //   if (mounted && !_tabController!.indexIsChanging) {
    //     setState(() {
    //       // 当 TabController 的索引稳定改变后，触发重建以更新 SwitchableView 的 currentIndex
    //     });
    //   }
    // });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadMediaDetail() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final jellyfinService = JellyfinService.instance;
      
      // 加载媒体详情
      final detail = await jellyfinService.getMediaItemDetails(widget.jellyfinId);
      
      if (mounted) {
        setState(() {
          _mediaDetail = detail;
          _isMovie = detail.type == 'Movie'; // 判断是否为电影

          if (_isMovie) {
            _isLoading = false;
            // 对于电影，我们不需要 TabController
          } else {
            // 对于剧集，初始化 TabController
            _tabController = TabController(
                length: 2,
                vsync: this,
                initialIndex: Provider.of<AppearanceSettingsProvider>(context, listen: false)
                    .animeCardAction == AnimeCardAction.synopsis ? 0 : 1
            );
            _tabController!.addListener(() {
              if (mounted && !_tabController!.indexIsChanging) {
                setState(() {
                  // 当 TabController 的索引稳定改变后，触发重建以更新 SwitchableView 的 currentIndex
                });
              }
            });
          }
        });
      }

      // 如果是剧集，才加载季节信息
      if (!_isMovie) {
        final seasons = await jellyfinService.getSeriesSeasons(widget.jellyfinId);
        
        if (mounted) {
          setState(() {
            _seasons = seasons;
            _isLoading = false;
            
            // 如果有季，选择第一个季
            if (seasons.isNotEmpty) {
              _selectedSeasonId = seasons.first.id;
              _loadEpisodesForSeason(seasons.first.id);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _loadEpisodesForSeason(String seasonId) async {
    // 如果已经加载过，不重复加载
    if (_episodesBySeasonId.containsKey(seasonId)) {
      setState(() {
        _selectedSeasonId = seasonId;
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedSeasonId = seasonId;
    });
    
    try {
      final jellyfinService = JellyfinService.instance;
      // Ensure _mediaDetail is not null and has a valid id before calling getSeasonEpisodes
      if (_mediaDetail?.id == null) {
        if (mounted) {
          setState(() {
            _error = '无法获取剧集详情，无法加载剧集列表。';
            _isLoading = false;
          });
        }
        return;
      }
      final episodes = await jellyfinService.getSeasonEpisodes(_mediaDetail!.id, seasonId);
      
      if (mounted) {
        setState(() {
          _episodesBySeasonId[seasonId] = episodes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }
  
  Future<WatchHistoryItem?> _createWatchHistoryItem(JellyfinEpisodeInfo episode) async {
    // 使用JellyfinDandanplayMatcher来创建可播放的历史记录项
    try {
      final matcher = JellyfinDandanplayMatcher.instance;
      
      // 先进行预计算和预匹配，不阻塞主流程
      matcher.precomputeVideoInfoAndMatch(context, episode).then((preMatchResult) {
        final String? videoHash = preMatchResult['videoHash'] as String?;
        final String? fileName = preMatchResult['fileName'] as String?;
        final int? fileSize = preMatchResult['fileSize'] as int?;
        
        if (videoHash != null && videoHash.isNotEmpty) {
          debugPrint('预计算哈希值成功: $videoHash');
          
          // 需要在播放器创建或历史项创建时使用这个哈希值
          // 由于JellyfinEpisodeInfo没有videoHash属性，我们暂时存储在全局变量中
          _jellyfinVideoHashes[episode.id] = videoHash;
          debugPrint('视频哈希值已缓存: ${episode.id} -> $videoHash');
          
          // 同时保存文件名和文件大小信息
          Map<String, dynamic> videoInfo = {
            'hash': videoHash,
            'fileName': fileName ?? '',
            'fileSize': fileSize ?? 0
          };
          _jellyfinVideoInfos[episode.id] = videoInfo;
          debugPrint('视频信息已缓存: ${episode.id} -> $videoInfo');
        }
        
        if (preMatchResult['success'] == true) {
          debugPrint('预匹配成功: animeId=${preMatchResult['animeId']}, episodeId=${preMatchResult['episodeId']}');
        } else {
          debugPrint('预匹配未成功: ${preMatchResult['message']}');
        }
      }).catchError((e) {
        debugPrint('预计算过程中出错: $e');
      });
      
      // 继续常规匹配流程
      final playableItem = await matcher.createPlayableHistoryItem(context, episode);
      
      // 如果我们有这个视频的信息，添加到历史项中
      if (playableItem != null) {
        // 添加哈希值
        if (_jellyfinVideoHashes.containsKey(episode.id)) {
          final videoHash = _jellyfinVideoHashes[episode.id];
          playableItem.videoHash = videoHash;
          debugPrint('成功将哈希值 $videoHash 添加到历史记录项');
        }
        
        // 存储完整的视频信息，可用于后续弹幕匹配
        if (_jellyfinVideoInfos.containsKey(episode.id)) {
          final videoInfo = _jellyfinVideoInfos[episode.id]!;
          // 将视频信息存储到tag字段（如果必要）
          // 或者在播放时单独传递
          debugPrint('已准备视频信息: ${videoInfo['fileName']}, 文件大小: ${videoInfo['fileSize']} 字节');
        }
      }
      
      debugPrint('成功创建可播放历史项: ${playableItem?.animeName} - ${playableItem?.episodeTitle}, animeId=${playableItem?.animeId}, episodeId=${playableItem?.episodeId}');
      return playableItem;
    } catch (e) {
      debugPrint('创建可播放历史记录项失败: $e');
      // 出现错误时仍然返回基本的WatchHistoryItem，确保播放功能不会完全失败
      return episode.toWatchHistoryItem();
    }
  }

  Future<void> _playMovie() async {
    if (_mediaDetail == null || !_isMovie) return;

    // 将 JellyfinMediaItemDetail 转换为 JellyfinMovieInfo
    // 这是必要的，因为匹配器需要一个 JellyfinMovieInfo 对象
    final movieInfo = JellyfinMovieInfo(
      id: _mediaDetail!.id,
      name: _mediaDetail!.name,
      overview: _mediaDetail!.overview,
      originalTitle: _mediaDetail!.originalTitle,
      imagePrimaryTag: _mediaDetail!.imagePrimaryTag,
      imageBackdropTag: _mediaDetail!.imageBackdropTag,
      productionYear: _mediaDetail!.productionYear,
      dateAdded: _mediaDetail!.dateAdded,
      premiereDate: _mediaDetail!.premiereDate,
      communityRating: _mediaDetail!.communityRating,
      genres: _mediaDetail!.genres,
      officialRating: _mediaDetail!.officialRating,
      cast: _mediaDetail!.cast,
      directors: _mediaDetail!.directors,
      runTimeTicks: _mediaDetail!.runTimeTicks,
      studio: _mediaDetail!.seriesStudio,
    );

    try {
      final matcher = JellyfinDandanplayMatcher.instance;
      final playableItem = await matcher.createPlayableHistoryItemFromMovie(context, movieInfo);
      if (playableItem == null) return; // 用户取消，彻底中断
      if (mounted) {
        Navigator.of(context).pop(playableItem);
      } else if (mounted) {
        // 如果匹配失败，可以给用户一个提示
        BlurSnackBar.show(context, '未能找到匹配的弹幕信息，但仍可播放。');
        // 即使没有弹幕，也创建一个基本的播放项
        final basicItem = movieInfo.toWatchHistoryItem();
        Navigator.of(context).pop(basicItem);
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '播放失败: $e');
      }
      debugPrint('电影播放失败: $e');
    }
  }
  
  String _formatRuntime(int? runTimeTicks) {
    if (runTimeTicks == null) return '';
    
    // Jellyfin中的RunTimeTicks单位是100纳秒
    final durationInSeconds = runTimeTicks / 10000000;
    final hours = (durationInSeconds / 3600).floor();
    final minutes = ((durationInSeconds % 3600) / 60).floor();
    
    if (hours > 0) {
      return '$hours小时${minutes > 0 ? ' $minutes分钟' : ''}';
    } else {
      return '$minutes分钟';
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget pageContent;

    if (_isLoading && _mediaDetail == null) {
      pageContent = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else if (_error != null && _mediaDetail == null) {
      pageContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('加载详情失败:', style: TextStyle(color: Colors.white.withOpacity(0.8))),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              BlurButton(
                icon: Icons.refresh,
                text: '重试',
                onTap: _loadMediaDetail,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                fontSize: 16,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
    } else if (_mediaDetail == null) {
      // 理论上在成功加载后 _mediaDetail 不会为 null，除非发生意外
      pageContent = const Center(child: Text('未找到媒体详情', style: TextStyle(color: Colors.white70)));
    } else {
      // 成功加载，构建详情UI
      final screenSize = MediaQuery.of(context).size;
      final isPortrait = screenSize.height > screenSize.width;
      final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context, listen: false);
      final enableAnimation = appearanceSettings.enablePageAnimation;

      pageContent = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _mediaDetail!.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Ionicons.close_circle_outline,
                      color: Colors.white70, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (!_isMovie && _tabController != null) // 如果不是电影，才显示TabBar
            TabBar(
              controller: _tabController,
              dividerColor: const Color.fromARGB(59, 255, 255, 255),
              dividerHeight: 3.0,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.only(top: 46, left: 15, right: 15), // 根据实际TabBar高度调整
              indicator: BoxDecoration(
                color: Colors.blueAccent, // Jellyfin 主题色或自定义
                borderRadius: BorderRadius.circular(30),
              ),
              indicatorWeight: 3,
              tabs: const [
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Ionicons.document_text_outline, size: 18), SizedBox(width: 8), Text('简介')])),
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Ionicons.film_outline, size: 18), SizedBox(width: 8), Text('剧集')])),
              ],
            ),
          Expanded(
            child: _isMovie || _tabController == null
              ? RepaintBoundary(child: _buildInfoView(isPortrait)) // 如果是电影，直接显示信息页
              : SwitchableView(
                  controller: _tabController,
                  currentIndex: _tabController!.index,
                  enableAnimation: enableAnimation,
                  physics: enableAnimation
                      ? const PageScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    if (_tabController!.index != index) {
                      _tabController!.animateTo(index);
                    }
                  },
                  children: [
                    RepaintBoundary(child: _buildInfoView(isPortrait)), // 使用RepaintBoundary优化
                    RepaintBoundary(child: _buildEpisodesView(isPortrait)), // 使用RepaintBoundary优化
                  ],
                ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent, // Dialog背景由showGeneralDialog的barrierColor控制
      body: Padding(
        // 调整Padding以匹配AnimeDetailPage
        padding: EdgeInsets.fromLTRB(
            20, MediaQuery.of(context).padding.top + 20, 20, 20),
        child: GlassmorphicContainer(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 15,
          blur: 25, // 与AnimeDetailPage一致
          alignment: Alignment.center,
          border: 0.5, // 与AnimeDetailPage一致
          linearGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ // 与AnimeDetailPage一致或自定义Jellyfin风格
              const Color.fromARGB(255, 60, 60, 80).withOpacity(0.2), // 深色调
              const Color.fromARGB(255, 40, 40, 60).withOpacity(0.2), // 更深的色调
            ],
            stops: const [0.1, 1],
          ),
          borderGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ // 与AnimeDetailPage一致
              Colors.white.withOpacity(0.15),
              Colors.white.withOpacity(0.15),
            ],
          ),
          child: pageContent,
        ),
      ),
    );
  }

  Widget _buildInfoView(bool isPortrait) {
    if (_mediaDetail == null) return const SizedBox.shrink();

    final jellyfinService = JellyfinService.instance;
    final backdropUrl = _mediaDetail!.imageBackdropTag != null
        ? jellyfinService.getImageUrl(_mediaDetail!.id, type: 'Backdrop', width: 1920, height: 1080, quality: 95)
        : '';

    // 注意：这里的返回按钮逻辑需要调整或移除，因为顶部已经有了全局关闭按钮
    return Stack(
      children: [
        // 背景图 - 直接使用网络图片，跳过压缩缓存
        if (backdropUrl.isNotEmpty)
          Positioned.fill(
            child: Image.network(
              backdropUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.grey[900],
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white54),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(color: Colors.grey[900]);
              },
            ),
          ),

        // 背景暗化层
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.75), // 可以稍微调整透明度
          ),
        ),

        // 内容区域
        // 移除原有的 Positioned 返回按钮
        SingleChildScrollView(
          // padding: const EdgeInsets.only(top: 16, bottom: 24, left:16, right: 16), // 调整内边距，因为顶部标题和TabBar已在外部处理
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部信息区域（海报 + 基本信息）
              isPortrait
                  ? _buildPortraitHeader() // 竖屏布局
                  : _buildLandscapeHeader(), // 横屏布局
              
              const SizedBox(height: 24),
              
              // 剧情简介
              if (_mediaDetail!.overview != null && _mediaDetail!.overview!.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '剧情简介',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _mediaDetail!.overview!,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
                
              const SizedBox(height: 24),
              
              // 演员信息
              if (_mediaDetail!.cast.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '演员',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 100, // 根据内容调整或使其可滚动
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _mediaDetail!.cast.length,
                        itemBuilder: (context, index) {
                          final actor = _mediaDetail!.cast[index];
                          
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.grey.shade800,
                                  backgroundImage: actor.primaryImageTag != null
                                      ? NetworkImage(jellyfinService.getImageUrl(actor.id, type: 'Primary', width: 100, quality: 90))
                                      : null,
                                  child: actor.primaryImageTag == null
                                      ? const Icon(Icons.person, color: Colors.white54)
                                      : null,
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    actor.name,
                                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
  
  // _buildPortraitHeader, _buildLandscapeHeader, _buildDetailInfo 方法中的文本颜色和样式也需要调整为白色或浅色系，以适应深色毛玻璃背景
  // 例如：
  Widget _buildPortraitHeader() {
    if (_mediaDetail == null) return const SizedBox.shrink();
    
    final jellyfinService = JellyfinService.instance;
    final posterUrl = _mediaDetail!.imagePrimaryTag != null
        ? jellyfinService.getImageUrl(_mediaDetail!.id, type: 'Primary', width: 300, quality: 95)
        : '';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center, // 竖屏时内容居中
      children: [
        Center( // 确保海报居中
          child: Container(
            width: 200,
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: posterUrl.isNotEmpty
                  ? CachedNetworkImageWidget(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error) {
                        return Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: Icon(
                              Ionicons.image_outline, // 使用 Ionicons
                              size: 40,
                              color: Colors.white30,
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey[800],
                      child: const Center(
                        child: Icon(
                          Ionicons.film_outline, // 使用 Ionicons
                          size: 40,
                          color: Colors.white30,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        Center( // 确保标题居中
          child: Text(
            _mediaDetail!.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white, // 调整颜色
            ),
            textAlign: TextAlign.center,
          ),
        ),
        
        if (_mediaDetail!.productionYear != null)
          Center( // 确保年份居中
            child: Text(
              '(${_mediaDetail!.productionYear})',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[300], // 调整颜色
              ),
              textAlign: TextAlign.center,
            ),
          ),
        
        const SizedBox(height: 16),
        
        _buildDetailInfo(), // 这个方法内部的文本颜色也需要调整
      ],
    );
  }

  Widget _buildLandscapeHeader() {
    if (_mediaDetail == null) return const SizedBox.shrink();
    
    final jellyfinService = JellyfinService.instance;
    final posterUrl = _mediaDetail!.imagePrimaryTag != null
        ? jellyfinService.getImageUrl(_mediaDetail!.id, type: 'Primary', width: 300, quality: 95)
        : '';
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 180, // 可以根据屏幕宽度动态调整
          height: 270, // width * 1.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: posterUrl.isNotEmpty
                ? CachedNetworkImageWidget(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error) {
                      return Container(
                        color: Colors.grey[800],
                        child: const Center(
                          child: Icon(
                            Ionicons.image_outline, // 使用 Ionicons
                            size: 40,
                            color: Colors.white30,
                          ),
                        ),
                      );
                    },
                  )
                : Container(
                    color: Colors.grey[800],
                    child: const Center(
                      child: Icon(
                        Ionicons.film_outline, // 使用 Ionicons
                        size: 40,
                        color: Colors.white30,
                      ),
                    ),
                  ),
          ),
        ),
        
        const SizedBox(width: 24),
        
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mediaDetail!.name,
                style: const TextStyle(
                  fontSize: 24, // 可以适当调大
                  fontWeight: FontWeight.bold,
                  color: Colors.white, // 调整颜色
                ),
              ),
              
              if (_mediaDetail!.productionYear != null)
                Text(
                  '(${_mediaDetail!.productionYear})',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[300], // 调整颜色
                  ),
                ),
              
              const SizedBox(height: 16),
              
              _buildDetailInfo(), // 这个方法内部的文本颜色也需要调整
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailInfo() {
    if (_mediaDetail == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_mediaDetail!.communityRating != null)
          Row(
            children: [
              const Icon(
                Ionicons.star, // 使用 Ionicons
                color: Colors.amber,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                _mediaDetail!.communityRating!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white, // 调整颜色
                ),
              ),
              const SizedBox(width: 16),
              
              if (_mediaDetail!.officialRating != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white54),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _mediaDetail!.officialRating!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70, // 调整颜色
                    ),
                  ),
                ),
            ],
          ),
        
        const SizedBox(height: 8),
        
        if (_mediaDetail!.runTimeTicks != null)
          Row(
            children: [
              const Icon(
                Ionicons.time_outline, // 使用 Ionicons
                color: Colors.white54,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                _formatRuntime(_mediaDetail!.runTimeTicks),
                style: const TextStyle(
                  color: Colors.white70, // 调整颜色
                ),
              ),
            ],
          ),
        
        const SizedBox(height: 8),
        
        if (_mediaDetail!.seriesStudio != null && _mediaDetail!.seriesStudio!.isNotEmpty)
          Row(
            children: [
              const Icon(
                Ionicons.business_outline, // 使用 Ionicons
                color: Colors.white54,
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _mediaDetail!.seriesStudio!,
                  style: const TextStyle(
                    color: Colors.white70, // 调整颜色
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        
        const SizedBox(height: 16),
        
        if (_mediaDetail!.genres.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _mediaDetail!.genres.map((genre) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15), // 调整颜色
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  genre,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70, // 调整颜色
                  ),
                ),
              );
            }).toList(),
          ),
        
        // 如果是电影，在详情信息下方添加播放按钮
        if (_isMovie) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              BlurButton(
                icon: Icons.play_arrow,
                text: '播放',
                onTap: _playMovie,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                fontSize: 18,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildEpisodesView(bool isPortrait) {
    // 移除原有的 Positioned 返回按钮，因为顶部已经有了全局关闭按钮
    return Column( // 不再需要 Stack，因为返回按钮已全局处理
      children: [
        // const SizedBox(height: 16), // 顶部间距可以根据整体布局调整，TabBar外部已有间距
        
        // 季节选择器
        if (_seasons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _seasons.length,
                itemBuilder: (context, index) {
                  final season = _seasons[index];
                  final isSelected = season.id == _selectedSeasonId;
                  
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: () => _loadEpisodesForSeason(season.id),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isSelected ? Colors.blueAccent.withOpacity(0.3) : Colors.transparent,
                        foregroundColor: isSelected ? Colors.white : Colors.white70,
                        side: BorderSide(
                          color: isSelected ? Colors.blueAccent : Colors.white30,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Text(season.name),
                    ),
                  );
                },
              ),
            ),
          ),
        
        if (_seasons.isNotEmpty) // 仅当有季节选择器时显示分割线
          const Divider(height: 1, thickness: 1, color: Colors.white12, indent: 16, endIndent: 16),
        
        // 剧集列表
        Expanded(
          child: _buildEpisodesListForSelectedSeason(),
        ),
      ],
    );
  }
  
  Widget _buildEpisodesListForSelectedSeason() {
    if (_selectedSeasonId == null && _seasons.isNotEmpty) { // 如果有季但没有选择，提示选择
      return const Center(
        child: Text('请选择一个季', style: TextStyle(color: Colors.white70)),
      );
    }
    if (_selectedSeasonId == null && _seasons.isEmpty && !_isLoading) { // 如果没有季且不在加载中
        return const Center(
        child: Text('该剧集没有季节信息', style: TextStyle(color: Colors.white70)),
      );
    }
    
    if (_isLoading && (_episodesBySeasonId[_selectedSeasonId ?? ''] == null || _episodesBySeasonId[_selectedSeasonId ?? '']!.isEmpty)) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    
    if (_error != null && _selectedSeasonId != null) { // 仅在尝试加载特定季出错时显示
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('加载剧集失败: $_error', style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              BlurButton(
                icon: Icons.refresh,
                text: '重试',
                onTap: () => _loadEpisodesForSeason(_selectedSeasonId!),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                fontSize: 16,
              ),
            ],
          ),
        ),
      );
    }
    
    final episodes = _episodesBySeasonId[_selectedSeasonId] ?? [];
    
    if (episodes.isEmpty && !_isLoading && _selectedSeasonId != null) { // 确保不是在加载中，并且确实选择了季
      return const Center(
        child: Text('该季没有剧集', style: TextStyle(color: Colors.white70)),
      );
    }
     if (episodes.isEmpty && _isLoading) { // 如果仍在加载，显示加载指示器
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (episodes.isEmpty && _selectedSeasonId == null && _seasons.isEmpty) { // 处理没有季的情况
        return const Center(child: Text('没有可显示的剧集', style: TextStyle(color: Colors.white70)));
    }


    final jellyfinService = JellyfinService.instance;
    
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final episode = episodes[index];
        final episodeImageUrl = episode.imagePrimaryTag != null
            ? jellyfinService.getImageUrl(episode.id, type: 'Primary', width: 300, quality: 90) // 调整图片宽度以适应列表项
            : '';
        
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: SizedBox(
            width: 100, // 调整图片宽度
            height: 60, // 调整图片高度，保持宽高比
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: episodeImageUrl.isNotEmpty
                  ? CachedNetworkImageWidget(
                      key: ValueKey(episode.id), // 为 CachedNetworkImageWidget 添加 Key
                      imageUrl: episodeImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error) {
                        return Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: Icon(
                              Ionicons.image_outline, // 使用 Ionicons
                              size: 24,
                              color: Colors.white30,
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey[800],
                      child: const Center(
                        child: Icon(
                          Ionicons.film_outline, // 使用 Ionicons
                          size: 24,
                          color: Colors.white30,
                        ),
                      ),
                    ),
            ),
          ),
          title: Text(
            episode.indexNumber != null
                ? '${episode.indexNumber}. ${episode.name}'
                : episode.name,
            style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white), // 调整颜色
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (episode.runTimeTicks != null)
                Text(
                  _formatRuntime(episode.runTimeTicks),
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]), // 调整颜色
                ),
              
              if (episode.overview != null && episode.overview!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text(
                    episode.overview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]), // 调整颜色
                  ),
                ),
            ],
          ),
          trailing: const Icon(Ionicons.play_circle_outline, color: Colors.white70, size: 22), // 添加播放按钮指示
          onTap: () async {
            try {
              BlurSnackBar.show(context, '准备播放: ${episode.name}');
              
              // 获取Jellyfin流媒体URL但暂不播放
              final streamUrl = JellyfinDandanplayMatcher.instance.getPlayUrl(episode);
              debugPrint('获取到流媒体URL: $streamUrl');
              
              // 显示加载指示器
              if (mounted) {
                BlurSnackBar.show(context, '正在匹配弹幕信息...');
              }
              
              // 使用JellyfinDandanplayMatcher创建增强的WatchHistoryItem
              // 这一步会显示匹配对话框，阻塞直到用户完成选择或跳过
              final historyItem = await _createWatchHistoryItem(episode);
              if (historyItem == null) return; // 用户关闭弹窗，什么都不做
              
              // 用户已完成匹配选择，现在可以继续播放流程
              debugPrint('成功获取历史记录项: ${historyItem.animeName} - ${historyItem.episodeTitle}, animeId=${historyItem.animeId}, episodeId=${historyItem.episodeId}');
              
              // 调试：检查 historyItem 的弹幕 ID
              if (historyItem.animeId == null || historyItem.episodeId == null) {
                debugPrint('警告: 从 JellyfinDandanplayMatcher 获得的 historyItem 缺少弹幕 ID');
                debugPrint('  animeId: ${historyItem.animeId}');
                debugPrint('  episodeId: ${historyItem.episodeId}');
              } else {
                debugPrint('确认: historyItem 包含有效的弹幕 ID');
                debugPrint('  animeId: ${historyItem.animeId}');
                debugPrint('  episodeId: ${historyItem.episodeId}');
              }
              
              // 显示开始播放的提示
              if (mounted) {
                BlurSnackBar.show(context, '开始播放: ${historyItem.episodeTitle}');
              }
              
              // 获取必要的服务引用
              final videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
              
              // 在页面关闭前，获取TabChangeNotifier
              // 注意：通过listen: false方式获取，避免建立依赖关系
              TabChangeNotifier? tabChangeNotifier;
              try {
                tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
              } catch (e) {
                debugPrint('无法获取TabChangeNotifier: $e');
              }
              
              // 创建一个专门用于流媒体播放的历史记录项，使用稳定的jellyfin://或emby://协议
              final playableHistoryItem = WatchHistoryItem(
                filePath: historyItem.filePath, // 保持稳定的jellyfin://或emby://协议URL
                animeName: historyItem.animeName,
                episodeTitle: historyItem.episodeTitle,
                episodeId: historyItem.episodeId,
                animeId: historyItem.animeId,
                watchProgress: historyItem.watchProgress,
                lastPosition: historyItem.lastPosition,
                duration: historyItem.duration,
                lastWatchTime: historyItem.lastWatchTime,
                thumbnailPath: historyItem.thumbnailPath, 
                isFromScan: false,
                videoHash: historyItem.videoHash, // 确保包含视频哈希值
              );
              
              debugPrint('开始初始化播放器...');
              
              try {
                // *** 关键修改：先初始化播放器，在导航前 ***
                debugPrint('初始化播放器 - 步骤1：开始');
                // 使用稳定的jellyfin://或emby://协议URL作为标识符，临时HTTP URL作为实际播放源
                await videoPlayerState.initializePlayer(
                  historyItem.filePath, // 使用稳定的jellyfin://或emby://协议
                  historyItem: playableHistoryItem,
                  actualPlayUrl: streamUrl, // 临时HTTP流媒体URL仅用于播放
                );
                debugPrint('初始化播放器 - 步骤1：完成');
                
                // 先提前通知TabChangeNotifier
                if (tabChangeNotifier != null) {
                  debugPrint('初始化播放器 - 步骤2：使用TabChangeNotifier切换到播放页面');
                  tabChangeNotifier.changeTab(1); // 提前通知切换到播放页面
                } else {
                  debugPrint('初始化播放器 - 步骤2：TabChangeNotifier为空，无法切换页面');
                }
                
                // 关闭详情页面 - 页面关闭前不再访问context相关内容
                debugPrint('初始化播放器 - 步骤3：准备关闭详情页面');
                Navigator.of(context).pop();
                debugPrint('初始化播放器 - 步骤3：详情页面已关闭');
                
                // 开始播放 - 此时页面已关闭，但播放器已初始化
                debugPrint('初始化播放器 - 步骤4：开始播放视频');
                videoPlayerState.play();
                debugPrint('初始化播放器 - 步骤4：成功开始播放: ${playableHistoryItem.animeName} - ${playableHistoryItem.episodeTitle}');
              } catch (playError) {
                debugPrint('播放流媒体时出错: $playError');
                
                // 确保context还挂载着才显示提示
                if (context.mounted) {
                  BlurSnackBar.show(context, '播放时出错: $playError');
                }
              }
                        } catch (e) {
              BlurSnackBar.show(context, '播放出错: $e');
              debugPrint('播放Jellyfin媒体出错: $e');
            }
          },
        );
      },
    );
  }
}
