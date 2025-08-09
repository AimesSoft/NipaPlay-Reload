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
import 'package:nipaplay/widgets/nipaplay_theme/themed_anime_detail.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/nipaplay_theme/loading_overlay.dart';
import 'package:nipaplay/widgets/nipaplay_theme/floating_action_glass_button.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_anime_card.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/pages/fluent_new_series_page.dart';
import 'package:nipaplay/main.dart';
import 'package:nipaplay/widgets/nipaplay_theme/tag_search_widget.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nipaplay/providers/appearance_settings_provider.dart';

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

  final Map<int, bool> _expansionStates = {}; // For weekday expansion state
  final Map<int, bool> _hoverStates = {}; // For weekday header hover state

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
    // final today = DateTime.now().weekday % 7; // 旧的初始化方式移除
    // _expansionStates[today] = true; 
    // _expansionStates and _hoverStates will be initialized on-demand in build
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

  // Modified to accept weekdayKey for PageStorageKey
  Widget _buildAnimeSection(List<BangumiAnime> animes, int weekdayKey) {
    if (animes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: Text("本日无新番", style: TextStyle(color: Colors.white70))),
      );
    }
    return GridView.builder(
      key: PageStorageKey<String>('gridview_for_weekday_$weekdayKey'), // Added unique PageStorageKey
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8.0, bottom: 16.0, left: 16.0, right: 16.0), // Add padding around the grid
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 7/12,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20, // Added mainAxisSpacing for vertical gap
      ),
      itemCount: animes.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      itemBuilder: (context, index) {
        final anime = animes[index];
        return _buildAnimeCard(context, anime, key: ValueKey(anime.id));
      },
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
    final unknownWeekdays = groupedAnimes.keys.where((day) => day == -1).toList();

    knownWeekdays.sort((a, b) {
      final today = DateTime.now().weekday % 7;
      if (a == today) return -1;
      if (b == today) return 1;
      final distA = (a - today + 7) % 7;
      final distB = (b - today + 7) % 7;
      return _isReversed ? distB.compareTo(distA) : distA.compareTo(distB);
    });

    return Stack(
      children: [
        CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    ...knownWeekdays.map((weekday) {
                      // Initialize states if not present
                      _expansionStates.putIfAbsent(weekday, () => weekday == (DateTime.now().weekday % 7));
                      _hoverStates.putIfAbsent(weekday, () => false);

                      bool isExpanded = _expansionStates[weekday]!;
                      bool isHovering = _hoverStates[weekday]!;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Column( // Changed from ExpansionTile to Column
                          children: [
                            MouseRegion(
                              onEnter: (_) => setState(() => _hoverStates[weekday] = true),
                              onExit: (_) => setState(() => _hoverStates[weekday] = false),
                              child: _buildCollapsibleSectionHeader(context, _weekdays[weekday] ?? '未知', weekday, isExpanded, isHovering),
                            ),
                            // Conditional rendering of children with animation
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: Visibility(
                                visible: isExpanded,
                                // maintainState: true, // Consider if state should be kept for hidden children
                                child: _buildAnimeSection(groupedAnimes[weekday]!, weekday),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (unknownWeekdays.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Divider(color: Colors.white24, indent: 16, endIndent: 16),
                      const SizedBox(height: 12),
                      _buildCollapsibleSectionHeader(context, '更新时间未定', -1, false, false), // isHovering is false as it's not interactive
                      // For non-interactive 'unknown' section, direct visibility or no animation
                      if (groupedAnimes[-1] != null && groupedAnimes[-1]!.isNotEmpty) // Ensure there are animes to show
                         _buildAnimeSection(groupedAnimes[-1]!, -1),
                    ],
                  ]),
                ),
              ),
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
        onTap: () => _showAnimeDetail(anime),
      );
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) {
      return '';
    }
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        return '${parts[0]}年${parts[1]}月${parts[2]}日';
      }
      //////debugPrint('日期格式不正确: $dateStr');
      return dateStr;
    } catch (e) {
      //////debugPrint('格式化日期出错: $e');
      return dateStr;
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

  // New method for the custom collapsible section header
  Widget _buildCollapsibleSectionHeader(BuildContext context, String title, int weekdayKey, bool isExpanded, bool isHovering) {
    // 根据悬停状态调整颜色
    final Color backgroundColor = isHovering
        ? Colors.white.withOpacity(0.2)
        : Colors.white.withOpacity(0.1);
    
    final Color borderColor = isHovering
        ? Colors.white.withOpacity(0.3)
        : Colors.white.withOpacity(0.2);

    return GestureDetector(
      onTap: () {
        setState(() {
          _expansionStates[weekdayKey] = !isExpanded;
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25.0 : 0.0,
            sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25.0 : 0.0,
          ),
          child: Container(
            width: double.infinity,
            height: 48,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Ionicons.chevron_down_outline,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 