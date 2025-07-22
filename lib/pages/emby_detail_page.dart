import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/switchable_view.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/emby_dandanplay_matcher.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';

class EmbyDetailPage extends StatefulWidget {
  final String embyId;

  const EmbyDetailPage({super.key, required this.embyId});

  @override
  State<EmbyDetailPage> createState() => _EmbyDetailPageState();
  
  static Future<WatchHistoryItem?> show(BuildContext context, String embyId) {
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
        return EmbyDetailPage(embyId: embyId);
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

class _EmbyDetailPageState extends State<EmbyDetailPage> with SingleTickerProviderStateMixin {
  // 静态Map，用于存储Emby视频的哈希值（ID -> 哈希值）
  static final Map<String, String> _embyVideoHashes = {};
  static final Map<String, Map<String, dynamic>> _embyVideoInfos = {};
  
  EmbyMediaItemDetail? _mediaDetail;
  List<EmbySeasonInfo> _seasons = [];
  Map<String, List<EmbyEpisodeInfo>> _episodesBySeasonId = {};
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
      final embyService = EmbyService.instance;
      
      // 加载媒体详情
      final detail = await embyService.getMediaItemDetails(widget.embyId);
      
      if (mounted) {
        setState(() {
          _mediaDetail = detail;
          _isMovie = detail.type == 'Movie'; // 判断是否为电影

          if (_isMovie) {
            _isLoading = false;
            // 对于电影，我们不需要 TabController
          } else {
            // 对于剧集，初始化 TabController
            _tabController = TabController(length: 2, vsync: this);
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
      final seasons = await embyService.getSeasons(widget.embyId);
      
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
      final embyService = EmbyService.instance;
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
      final episodes = await embyService.getSeasonEpisodes(_mediaDetail!.id, seasonId);
      
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
  
  Future<WatchHistoryItem?> _createWatchHistoryItem(EmbyEpisodeInfo episode) async {
    // 使用EmbyDandanplayMatcher来创建可播放的历史记录项
    try {
      final matcher = EmbyDandanplayMatcher.instance;
      
      // 先进行预计算和预匹配，不阻塞主流程
      matcher.precomputeVideoInfoAndMatch(context, episode).then((preMatchResult) {
        final String? videoHash = preMatchResult['videoHash'] as String?;
        final String? fileName = preMatchResult['fileName'] as String?;
        final int? fileSize = preMatchResult['fileSize'] as int?;
        
        if (videoHash != null && videoHash.isNotEmpty) {
          debugPrint('预计算哈希值成功: $videoHash');
          
          // 需要在播放器创建或历史项创建时使用这个哈希值
          // 由于EmbyEpisodeInfo没有videoHash属性，我们暂时存储在全局变量中
          _embyVideoHashes[episode.id] = videoHash;
          debugPrint('视频哈希值已缓存: ${episode.id} -> $videoHash');
          
          if (fileName != null && fileSize != null) {
            _embyVideoInfos[episode.id] = {
              'fileName': fileName,
              'fileSize': fileSize,
              'videoHash': videoHash,
            };
            debugPrint('视频信息已缓存: ${episode.id} -> $fileName (${fileSize} bytes)');
          }
        }
      });
      
      // 立即创建可播放项并返回，不等待预计算完成
      final playableItem = await matcher.createPlayableHistoryItem(context, episode);
      
      // 如果我们有这个视频的信息，添加到历史项中
      if (playableItem != null) {
        // 添加哈希值
        if (_embyVideoHashes.containsKey(episode.id)) {
          final videoHash = _embyVideoHashes[episode.id];
          playableItem.videoHash = videoHash;
          debugPrint('成功将哈希值 $videoHash 添加到历史记录项');
        }
        
        // 存储完整的视频信息，可用于后续弹幕匹配
        if (_embyVideoInfos.containsKey(episode.id)) {
          final videoInfo = _embyVideoInfos[episode.id]!;
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

    // 将 EmbyMediaItemDetail 转换为 EmbyMovieInfo
    // 这是必要的，因为匹配器需要一个 EmbyMovieInfo 对象
    final movieInfo = EmbyMovieInfo(
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
      final matcher = EmbyDandanplayMatcher.instance;
      final playableItem = await matcher.createPlayableHistoryItemFromMovie(context, movieInfo);
      
      if (mounted && playableItem != null) {
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
    
    // Emby中的RunTimeTicks单位是100纳秒
    final durationInSeconds = runTimeTicks / 10000000;
    final hours = (durationInSeconds / 3600).floor();
    final minutes = ((durationInSeconds % 3600) / 60).floor();
    
    if (hours > 0) {
      return '${hours}小时${minutes}分钟';
    } else {
      return '${minutes}分钟';
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget pageContent;

    if (_isLoading && _mediaDetail == null) { // Match Jellyfin's initial loading condition
      pageContent = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else if (_error != null && _mediaDetail == null) { // Match Jellyfin's error condition
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
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2)),
                onPressed: _loadMediaDetail,
                child: const Text('重试', style: TextStyle(color: Colors.white)),
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
      pageContent = const Center(child: Text('未找到媒体详情', style: TextStyle(color: Colors.white70)));
    } else {
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
              indicatorPadding: const EdgeInsets.only(top: 46, left: 15, right: 15),
              indicator: BoxDecoration(
              color: Colors.amberAccent, // Emby theme color or custom
              borderRadius: BorderRadius.circular(30),
            ),
              indicatorWeight: 3,
              tabs: const [
              Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.info_outline, size: 18), SizedBox(width: 8), Text('简介')])),
              Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.video_library_outlined, size: 18), SizedBox(width: 8), Text('剧集')])),
            ],
          ),
          Expanded(
            child: _isMovie || _tabController == null
              ? RepaintBoundary(child: _buildInfoView(isPortrait)) // 如果是电影，直接显示信息页
              : SwitchableView(
                  currentIndex: _tabController!.index,
                  children: [
                RepaintBoundary(child: _buildInfoView(isPortrait)),
                RepaintBoundary(child: _buildEpisodesView(isPortrait)),
              ],
              enableAnimation: enableAnimation,
                  physics: enableAnimation
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    if (_tabController!.index != index) {
                      _tabController!.animateTo(index);
                }
              },
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding( // Add Padding like Jellyfin
        padding: EdgeInsets.fromLTRB(
            20, MediaQuery.of(context).padding.top + 20, 20, 20),
        child: GlassmorphicContainer(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 15, // Match Jellyfin
          blur: 25, // Match Jellyfin
          alignment: Alignment.center,
          border: 0.5, // Match Jellyfin
          linearGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ // Match Jellyfin's darker theme or use Emby specific
              const Color.fromARGB(255, 50, 70, 50).withOpacity(0.2), // Emby-like green/dark
              const Color.fromARGB(255, 30, 50, 30).withOpacity(0.2), // Darker Emby-like
            ],
            stops: const [0.1, 1],
          ),
          borderGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.15), // Match Jellyfin
              Colors.white.withOpacity(0.15), // Match Jellyfin
            ],
          ),
          child: pageContent,
        ),
      ),
    );
  }

  Widget _buildInfoView(bool isPortrait) {
    if (_mediaDetail == null) return const SizedBox.shrink();

    final embyService = EmbyService.instance;
    final backdropUrl = _mediaDetail!.imageBackdropTag != null
        ? embyService.getImageUrl(_mediaDetail!.id, type: 'Backdrop', width: 1920, height: 1080, quality: 95)
        : '';

    return Stack(
      children: [
        // 背景图片 - 直接使用网络图片，跳过压缩缓存
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
        
        // 渐变覆盖
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.4),
                  Colors.black.withOpacity(0.8),
                ],
              ),
            ),
          ),
        ),
        
        // 内容
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部信息区域（海报 + 基本信息）
              isPortrait
                  ? _buildPortraitHeader()
                  : _buildLandscapeHeader(),
              
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
                      height: 100,
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
                                  backgroundImage: actor.imagePrimaryTag != null && actor.id != null
                                      ? NetworkImage(embyService.getImageUrl(actor.id!, type: 'Primary', tag: actor.imagePrimaryTag, width: 100, height: 100))
                                      : null,
                                  child: actor.imagePrimaryTag == null
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

  Widget _buildPortraitHeader() {
    if (_mediaDetail == null) return const SizedBox.shrink();
    
    final embyService = EmbyService.instance;
    final posterUrl = _mediaDetail!.imagePrimaryTag != null
        ? embyService.getImageUrl(_mediaDetail!.id, type: 'Primary', width: 300)
        : '';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
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
                              Ionicons.image_outline,
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
                          Ionicons.film_outline,
                          size: 40,
                          color: Colors.white30,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        Center(
          child: Text(
            _mediaDetail!.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        
        if (_mediaDetail!.productionYear != null)
          Center(
            child: Text(
              '(${_mediaDetail!.productionYear})',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[300],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        
        const SizedBox(height: 16),
        
        _buildDetailInfo(),
        
        // 如果是电影，在详情信息下方添加播放按钮
        if (_isMovie) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('播放'),
                onPressed: _playMovie,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLandscapeHeader() {
    if (_mediaDetail == null) return const SizedBox.shrink();
    
    final embyService = EmbyService.instance;
    final posterUrl = _mediaDetail!.imagePrimaryTag != null
        ? embyService.getImageUrl(_mediaDetail!.id, type: 'Primary', width: 300)
        : '';
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 180,
          height: 270,
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
                            Ionicons.image_outline,
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
                        Ionicons.film_outline,
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
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              
              if (_mediaDetail!.productionYear != null)
                Text(
                  '(${_mediaDetail!.productionYear})',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[300],
                  ),
                ),
              
              const SizedBox(height: 16),
              
              _buildDetailInfo(),
              
              // 如果是电影，在详情信息下方添加播放按钮
              if (_isMovie) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('播放'),
                      onPressed: _playMovie,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
                Ionicons.star,
                color: Colors.amber,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                _mediaDetail!.communityRating!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
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
                      color: Colors.white70,
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
                Ionicons.time_outline,
                color: Colors.white54,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                _formatRuntime(_mediaDetail!.runTimeTicks),
                style: const TextStyle(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        
        const SizedBox(height: 8),
        
        if (_mediaDetail!.seriesStudio != null && _mediaDetail!.seriesStudio!.isNotEmpty)
          Row(
            children: [
              const Icon(
                Ionicons.business_outline,
                color: Colors.white54,
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _mediaDetail!.seriesStudio!,
                  style: const TextStyle(
                    color: Colors.white70,
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
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  genre,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildEpisodesView(bool isPortrait) {
    return Column(
      children: [
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
        
        if (_seasons.isNotEmpty)
          const Divider(height: 1, thickness: 1, color: Colors.white12, indent: 16, endIndent: 16),
        
        // 剧集列表
        Expanded(
          child: _buildEpisodesListForSelectedSeason(),
        ),
      ],
    );
  }
  
  Widget _buildEpisodesListForSelectedSeason() {
    if (_selectedSeasonId == null && _seasons.isNotEmpty) {
      return const Center(
        child: Text('请选择一个季', style: TextStyle(color: Colors.white70)),
      );
    }
    if (_selectedSeasonId == null && _seasons.isEmpty && !_isLoading) {
        return const Center(
        child: Text('该剧集没有季节信息', style: TextStyle(color: Colors.white70)),
      );
    }
    
    if (_isLoading && (_episodesBySeasonId[_selectedSeasonId ?? ''] == null || _episodesBySeasonId[_selectedSeasonId ?? '']!.isEmpty)) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    
    if (_error != null && _selectedSeasonId != null) {
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
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.2)),
                onPressed: () => _loadEpisodesForSeason(_selectedSeasonId!),
                child: const Text('重试', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    
    final episodes = _episodesBySeasonId[_selectedSeasonId] ?? [];
    
    if (episodes.isEmpty && !_isLoading && _selectedSeasonId != null) {
      return const Center(
        child: Text('该季没有剧集', style: TextStyle(color: Colors.white70)),
      );
    }
     if (episodes.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (episodes.isEmpty && _selectedSeasonId == null && _seasons.isEmpty) {
        return const Center(child: Text('没有可显示的剧集', style: TextStyle(color: Colors.white70)));
    }

    final embyService = EmbyService.instance;
    
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final episode = episodes[index];
        final episodeImageUrl = episode.imagePrimaryTag != null
            ? embyService.getImageUrl(episode.id, type: 'Primary', width: 300)
            : '';
        
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: SizedBox(
            width: 100,
            height: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: episodeImageUrl.isNotEmpty
                  ? CachedNetworkImageWidget(
                      key: ValueKey(episode.id),
                      imageUrl: episodeImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error) {
                        return Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: Icon(
                              Ionicons.image_outline,
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
                          Ionicons.film_outline,
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
            style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (episode.runTimeTicks != null)
                Text(
                  _formatRuntime(episode.runTimeTicks),
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              
              if (episode.overview != null && episode.overview!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text(
                    episode.overview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ),
            ],
          ),
          trailing: const Icon(Ionicons.play_circle_outline, color: Colors.white70, size: 22),
          onTap: () async {
            try {
              BlurSnackBar.show(context, '准备播放: ${episode.name}');
              
              // 获取Emby流媒体URL但暂不播放
              final streamUrl = EmbyDandanplayMatcher.instance.getPlayUrl(episode);
              debugPrint('获取到流媒体URL: $streamUrl');
              
              // 显示加载指示器
              if (mounted) {
                BlurSnackBar.show(context, '正在匹配弹幕信息...');
              }
              
              // 使用EmbyDandanplayMatcher创建增强的WatchHistoryItem
              // 这一步会显示匹配对话框，阻塞直到用户完成选择或跳过
              final historyItem = await _createWatchHistoryItem(episode);
              
              // 用户已完成匹配选择，现在可以继续播放流程
              if (historyItem != null) {
                debugPrint('成功获取历史记录项: ${historyItem.animeName} - ${historyItem.episodeTitle}, animeId=${historyItem.animeId}, episodeId=${historyItem.episodeId}');
                
                // 调试：检查 historyItem 的弹幕 ID
                if (historyItem.animeId == null || historyItem.episodeId == null) {
                  debugPrint('警告: 从 EmbyDandanplayMatcher 获得的 historyItem 缺少弹幕 ID');
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
                TabChangeNotifier? tabChangeNotifier;
                try {
                  tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
                } catch (e) {
                  debugPrint('无法获取TabChangeNotifier: $e');
                }
                
                // 创建一个专门用于流媒体播放的历史记录项，使用稳定的emby://协议
                final playableHistoryItem = WatchHistoryItem(
                  filePath: historyItem.filePath, // 保持稳定的emby://协议URL
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
                  // 使用稳定的emby://协议URL作为标识符，临时HTTP URL作为实际播放源
                  await videoPlayerState.initializePlayer(
                   playableHistoryItem.filePath, // 使用 emby://<itemId> 作为视频路径
                    historyItem: playableHistoryItem, // 使用包含弹幕信息的历史项
                    actualPlayUrl: streamUrl, // 提供实际的HTTP流媒体URL
                  );
                  debugPrint('初始化播放器 - 步骤2：播放器初始化完成');
                  
                  // 初始化成功后，切换到播放器标签页并关闭当前页面
                  tabChangeNotifier?.changeTab(0);
                  debugPrint('初始化播放器 - 步骤3：已切换到播放器标签页');
                  
                  // 关闭详情页面
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
              } else {
                BlurSnackBar.show(context, '无法处理该剧集');
              }
            } catch (e) {
              BlurSnackBar.show(context, '播放出错: $e');
              debugPrint('播放Emby媒体出错: $e');
            }
          },
        );
      },
    );
  }
}
