import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/nipaplay/widgets/loading_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/floating_action_glass_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_card.dart';
import 'package:nipaplay/themes/fluent/widgets/fluent_anime_card.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/themes/fluent/pages/fluent_new_series_page.dart';
import 'package:nipaplay/main.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tag_search_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';

class NewSeriesPage extends StatefulWidget {
  const NewSeriesPage({super.key});

  @override
  State<NewSeriesPage> createState() => _NewSeriesPageState();
}

class _NewSeriesPageState extends State<NewSeriesPage> with AutomaticKeepAliveClientMixin<NewSeriesPage> {
  final BangumiService _bangumiService = BangumiService.instance;
  List<BangumiAnime> _animes = [];
  bool _isLoading = true;
  String? _error;
  bool _isReversed = false;
  
  // States for loading video from detail page
  bool _isLoadingVideoFromDetail = false;
  String _loadingMessageForDetail = '正在加载视频...';

  // Override wantKeepAlive for AutomaticKeepAliveClientMixin
  @override
  bool get wantKeepAlive => true;

  // 切换排序方向
  void _toggleSort() {
    setState(() {
      _isReversed = !_isReversed;
    });
  }

  // 显示搜索模态框
  void _showSearchModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TagSearchModal(),
    );
  }

  // 添加星期几的映射
  static const Map<int, String> _weekdays = {
    0: '周日',
    1: '周一',
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    -1: '未知', // For animes with null or invalid airWeekday
  };

  @override
  void initState() {
    super.initState();
    _loadAnimes();
  }

  @override
  void dispose() {
    // 释放所有图片资源
    for (var anime in _animes) {
      ImageCacheManager.instance.releaseImage(anime.imageUrl);
    }
    super.dispose();
  }

  Future<void> _loadAnimes({bool forceRefresh = false}) async {
    try {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = true;
        _error = null;
      });

      List<BangumiAnime> animes;

      if (kIsWeb) {
        // Web environment: fetch from the local API
        try {
          final response = await http.get(Uri.parse('/api/bangumi/calendar'));
          if (response.statusCode == 200) {
            final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
            animes = data.map((d) => BangumiAnime.fromJson(d as Map<String, dynamic>)).toList();
          } else {
            throw Exception('Failed to load from API: ${response.statusCode}');
          }
        } catch (e) {
          throw Exception('Failed to connect to the local API: $e');
        }
      } else {
        // Mobile/Desktop environment: fetch from the service
        final prefs = await SharedPreferences.getInstance();
        final bool filterAdultContentGlobally = prefs.getBool('global_filter_adult_content') ?? true; 
        animes = await _bangumiService.getCalendar(
          forceRefresh: forceRefresh,
          filterAdultContent: filterAdultContentGlobally
        );
      }
      
      if (mounted) {
        setState(() {
          _animes = animes;
          _isLoading = false;
        });
      }
    } catch (e) {
      String errorMsg = e.toString();
      if (e is TimeoutException) {
        errorMsg = '网络请求超时，请检查网络连接后重试';
      } else if (errorMsg.contains('SocketException')) {
        errorMsg = '网络连接失败，请检查网络设置';
      } else if (errorMsg.contains('HttpException')) {
        errorMsg = '服务器无法连接，请稍后重试';
      } else if (errorMsg.contains('FormatException')) {
        errorMsg = '服务器返回数据格式错误';
      }
      
      if (mounted) {
        setState(() {
          _error = errorMsg;
          _isLoading = false;
        });
      }
    }
  }

  // 按星期几分组番剧
  Map<int, List<BangumiAnime>> _groupAnimesByWeekday() {
    final grouped = <int, List<BangumiAnime>>{};
    // Restore original filter
    final validAnimes = _animes.where((anime) => 
      anime.imageUrl.isNotEmpty && 
      anime.imageUrl != 'assets/backempty.png'
      // && anime.nameCn.isNotEmpty && // Temporarily removed to allow display even if names are empty
      // && anime.name.isNotEmpty       // Temporarily removed
    ).toList();
    // final validAnimes = _animes.toList(); // Test: Show all animes from cache (Reverted)
    
    final unknownAnimes = validAnimes.where((anime) => 
      anime.airWeekday == null || 
      anime.airWeekday == -1 || 
      anime.airWeekday! < 0 || 
      anime.airWeekday! > 6 // Dandanplay airDay is 0-6
    ).toList();
    
    if (unknownAnimes.isNotEmpty) {
      grouped[-1] = unknownAnimes;
    }
    
    for (var anime in validAnimes) {
      if (anime.airWeekday != null && 
          anime.airWeekday! >= 0 && 
          anime.airWeekday! <= 6) { // Dandanplay airDay is 0-6
        grouped.putIfAbsent(anime.airWeekday!, () => []).add(anime);
      }
    }
    return grouped;
  }

  SliverPadding _buildAnimeGridSliver(List<BangumiAnime> animes, int weekdayKey) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      sliver: SliverGrid(
        key: ValueKey<String>('sliver_grid_for_weekday_$weekdayKey'),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 500,
          mainAxisExtent: 140,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final anime = animes[index];
            return FutureBuilder<BangumiAnime>(
              future: _bangumiService.getAnimeDetails(anime.id),
              builder: (context, snapshot) {
                String? summary;
                if (snapshot.hasData && snapshot.data!.summary != null) {
                  summary = snapshot.data!.summary;
                }
                return HorizontalAnimeCard(
                  imageUrl: anime.imageUrl,
                  title: anime.nameCn.isNotEmpty ? anime.nameCn : anime.name,
                  rating: anime.rating,
                  isOnAir: anime.isOnAir ?? false,
                  onTap: () => _showAnimeDetail(anime),
                  summary: summary,
                );
              },
            );
          },
          childCount: animes.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
        ),
      ),
    );
  }

  SliverPadding _buildWeekdayHeaderSliver(
    BuildContext context, {
    required String title,
    required int weekdayKey,
    required int count,
    required bool isToday,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      sliver: SliverToBoxAdapter(
        child: Align(
          alignment: Alignment.centerLeft,
          child: _buildWeekdayHeader(
            context,
            title: title,
            weekdayKey: weekdayKey,
            count: count,
            isToday: isToday,
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildEmptyDaySliver() {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
        child: Center(
          child: Text(
            "本日无新番",
            locale: Locale("zh-Hans", "zh"),
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Added for AutomaticKeepAliveClientMixin
    
    final uiThemeProvider = Provider.of<UIThemeProvider>(context, listen: false);
    
    // 如果是Fluent UI主题，使用专门的Fluent UI页面
    if (uiThemeProvider.isFluentUITheme) {
      return const FluentNewSeriesPage();
    }
    
    //debugPrint('[NewSeriesPage build] START - isLoading: $_isLoading, error: $_error, animes.length: ${_animes.length}');
    
    // Outer Stack to handle the new LoadingOverlay for video loading
    return Stack(
      children: [
        // Original content based on _isLoading for anime list
        _buildMainContent(context), // Extracted original content to a new method
        if (_isLoadingVideoFromDetail)
          LoadingOverlay(
            messages: [_loadingMessageForDetail], // LoadingOverlay expects a list of messages
            backgroundOpacity: 0.7, // Optional: customize opacity
            animeTitle: null,
            episodeTitle: null,
            fileName: null,
          ),
      ],
    );
  }

  // Extracted original build content into a new method
  Widget _buildMainContent(BuildContext context) {
    if (_isLoading && _animes.isEmpty) {
      //debugPrint('[NewSeriesPage build] Showing loading indicator.');
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _animes.isEmpty) {
      //debugPrint('[NewSeriesPage build] Showing error message: $_error');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('加载失败: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadAnimes(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final groupedAnimes = _groupAnimesByWeekday();
    final knownWeekdays = groupedAnimes.keys.where((day) => day != -1).toList();

    knownWeekdays.sort((a, b) {
      final today = DateTime.now().weekday % 7;
      if (a == today) return -1;
      if (b == today) return 1;
      final distA = (a - today + 7) % 7;
      final distB = (b - today + 7) % 7;
      return _isReversed ? distB.compareTo(distA) : distA.compareTo(distB);
    });

    final today = DateTime.now().weekday % 7;
    final unknownAnimes = groupedAnimes[-1] ?? const <BangumiAnime>[];

    return Stack(
      children: [
        CustomScrollView(
          key: const PageStorageKey<String>('new_series_scroll_view'),
          slivers: [
            for (final weekday in knownWeekdays) ...[
              _buildWeekdayHeaderSliver(
                context,
                title: _weekdays[weekday] ?? '未知',
                weekdayKey: weekday,
                count: groupedAnimes[weekday]?.length ?? 0,
                isToday: weekday == today,
              ),
              if ((groupedAnimes[weekday]?.isNotEmpty ?? false))
                _buildAnimeGridSliver(groupedAnimes[weekday]!, weekday)
              else
                _buildEmptyDaySliver(),
            ],
            if (unknownAnimes.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              const SliverToBoxAdapter(
                child: Divider(color: Colors.white24, indent: 16, endIndent: 16),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              _buildWeekdayHeaderSliver(
                context,
                title: '更新时间未定',
                weekdayKey: -1,
                count: unknownAnimes.length,
                isToday: false,
              ),
              _buildAnimeGridSliver(unknownAnimes, -1),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 搜索按钮
              FloatingActionGlassButton(
                iconData: Ionicons.search_outline,
                onPressed: _showSearchModal,
                description: '搜索新番\n按标签、类型快速筛选\n查找你感兴趣的新番',
              ),
              const SizedBox(height: 16), // 按钮之间的间距
              // 排序按钮
              FloatingActionGlassButton(
                iconData: _isReversed ? Ionicons.chevron_up_outline : Ionicons.chevron_down_outline,
                onPressed: _toggleSort,
                description: _isReversed ? '切换为正序显示\n今天的新番排在最前' : '切换为倒序显示\n今天的新番排在最后',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnimeCard(BuildContext context, BangumiAnime anime, {Key? key}) {
    final uiThemeProvider = Provider.of<UIThemeProvider>(context, listen: false);
    
    if (uiThemeProvider.isFluentUITheme) {
      // 使用 FluentUI 版本
      return FluentAnimeCard(
        key: key,
        name: anime.nameCn,
        imageUrl: anime.imageUrl,
        isOnAir: false,
        source: 'Bangumi',
        rating: anime.rating,
        ratingDetails: anime.ratingDetails,
        onTap: () => _showAnimeDetail(anime),
      );
    } else {
      // 使用 Material 版本（保持原有逻辑）
      return AnimeCard(
        key: key,
        name: anime.nameCn,
        imageUrl: anime.imageUrl,
        isOnAir: false,
        source: 'Bangumi',
        rating: anime.rating,
        ratingDetails: anime.ratingDetails,
        enableBackdropImage: false,
        enableBackgroundBlur: false,
        enableShadow: false,
        onTap: () => _showAnimeDetail(anime),
      );
    }
  }

  Future<void> _showAnimeDetail(BangumiAnime animeFromList) async {
    // 使用主题适配的显示方法
    final result = await ThemedAnimeDetail.show(context, animeFromList.id);

    if (result is WatchHistoryItem) {
      // If a WatchHistoryItem is returned, handle playing the episode
      if (mounted) { // Ensure widget is still mounted
        _handlePlayEpisode(result);
      }
    }
  }

  Future<void> _handlePlayEpisode(WatchHistoryItem historyItem) async {
    if (!mounted) return;

    setState(() {
      _isLoadingVideoFromDetail = true;
      _loadingMessageForDetail = '正在初始化播放器...';
    });

    bool tabChangeLogicExecutedInDetail = false;

    try {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);

      late VoidCallback statusListener;
      statusListener = () {
        if (!mounted) {
          videoState.removeListener(statusListener);
          return;
        }
        
        if ((videoState.status == PlayerStatus.ready || videoState.status == PlayerStatus.playing) && !tabChangeLogicExecutedInDetail) {
          tabChangeLogicExecutedInDetail = true;
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isLoadingVideoFromDetail = false;
              });
              
              debugPrint('[NewSeriesPage _handlePlayEpisode] Player ready/playing. Attempting to switch tab.');
              try {
                MainPageState? mainPageState = MainPageState.of(context);
                if (mainPageState != null && mainPageState.globalTabController != null) {
                  if (mainPageState.globalTabController!.index != 1) {
                    mainPageState.globalTabController!.animateTo(1);
                    debugPrint('[NewSeriesPage _handlePlayEpisode] Directly called mainPageState.globalTabController.animateTo(1)');
                  } else {
                    debugPrint('[NewSeriesPage _handlePlayEpisode] mainPageState.globalTabController is already at index 1.');
                  }
                } else {
                  debugPrint('[NewSeriesPage _handlePlayEpisode] Could not find MainPageState or globalTabController.');
                }
              } catch (e) {
                debugPrint("[NewSeriesPage _handlePlayEpisode] Error directly changing tab: $e");
              }
              videoState.removeListener(statusListener);
            } else {
               videoState.removeListener(statusListener);
            }
          });
        } else if (videoState.status == PlayerStatus.error) {
            videoState.removeListener(statusListener);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _isLoadingVideoFromDetail = false;
                });
                BlurSnackBar.show(context, '播放器加载失败: ${videoState.error ?? '未知错误'}');
              }
            });
        } else if (tabChangeLogicExecutedInDetail && (videoState.status == PlayerStatus.ready || videoState.status == PlayerStatus.playing)) {
            debugPrint('[NewSeriesPage _handlePlayEpisode] Tab logic executed, player still ready/playing. Ensuring listener removed.');
            videoState.removeListener(statusListener);
        }
      };

      videoState.addListener(statusListener);
      await videoState.initializePlayer(historyItem.filePath, historyItem: historyItem);

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingVideoFromDetail = false;
          _loadingMessageForDetail = '发生错误: $e';
        });
        BlurSnackBar.show(context, '处理播放请求时出错: $e');
      }
    }
  }

  Widget _buildWeekdayHeader(
    BuildContext context, {
    required String title,
    required int weekdayKey,
    required int count,
    required bool isToday,
  }) {
    final String countText = '$count 部动画';

    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: isToday ? Colors.white : Colors.white.withValues(alpha: 0.9),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            countText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isToday ? Colors.white.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
