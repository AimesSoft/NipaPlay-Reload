import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bangumi_service.dart';
import '../models/bangumi_model.dart';
import '../models/watch_history_model.dart';
import '../utils/image_cache_manager.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../widgets/cached_network_image_widget.dart';
import '../widgets/custom_refresh_indicator.dart';
import '../widgets/translation_button.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/dandanplay_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pages/anime_detail_page.dart';
import '../widgets/transparent_page_route.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import '../widgets/loading_overlay.dart';
import 'package:flutter/rendering.dart';
import 'package:nipaplay/widgets/floating_action_glass_button.dart';
import '../widgets/blur_snackbar.dart';
import '../widgets/anime_card.dart';
import 'package:nipaplay/main.dart';
import '../widgets/tag_search_widget.dart';

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
  Map<int, String> _translatedSummaries = {};
  static const String _translationCacheKey = 'bangumi_translation_cache';
  static const Duration _translationCacheDuration = Duration(days: 7);
  final bool _isShowingTranslation = false;
  
  // bool _filterAdultContent = true; // REMOVED
  // static const String _filterAdultContentKey = 'new_series_filter_adult_content'; // REMOVED

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
    // _loadFilterAdultContentPreference(); // REMOVED
    _loadAnimes();
    _loadTranslationCache();
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

  // Future<void> _loadFilterAdultContentPreference() async { // REMOVED
  //   final prefs = await SharedPreferences.getInstance();
  //   // Check if mounted before calling setState, especially if this could complete after dispose
  //   if (mounted) { 
  //     setState(() {
  //       _filterAdultContent = prefs.getBool(_filterAdultContentKey) ?? true; // Default to true
  //       //debugPrint('[NewSeriesPage] Loaded _filterAdultContent preference: $_filterAdultContent');
  //     });
  //     // Important: After loading the preference, we might need to reload animes 
  //     // if the loaded preference is different from the initial default AND _loadAnimes in initState already ran.
  //     // However, the current initState order (_loadFilterAdultContentPreference before _loadAnimes)
  //     // should make _loadAnimes use the correct loaded value. 
  //     // If _loadAnimes was called before this completed, a manual re-trigger might be needed.
  //     // For simplicity now, relying on initState order.
  //   }
  // }

  Future<void> _loadAnimes({bool forceRefresh = false}) async {
    try {
      //debugPrint('[NewSeriesPage _loadAnimes] Called. forceRefresh: $forceRefresh');
      if (!mounted) {
        //debugPrint('[NewSeriesPage _loadAnimes] Not mounted, returning.');
        return;
      }
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final prefs = await SharedPreferences.getInstance();
      // Use the same key defined in general_page.dart. 
      // Ensure this key is consistently available, e.g. by importing the settings file or having a shared constants file.
      // For now, we'll use the literal string, assuming 'global_filter_adult_content' is the key.
      final bool filterAdultContentGlobally = prefs.getBool('global_filter_adult_content') ?? true; 
      //debugPrint('[NewSeriesPage _loadAnimes] Using global NSFW filter: $filterAdultContentGlobally');

      final animes = await _bangumiService.getCalendar(
        forceRefresh: forceRefresh, 
        filterAdultContent: filterAdultContentGlobally // Use the global setting value
      );
      //debugPrint('[NewSeriesPage _loadAnimes] getCalendar returned ${animes.length} animes.');

      if (mounted) {
        //debugPrint('[NewSeriesPage _loadAnimes] Before final setState - animes.length from service: ${animes.length}');
        setState(() {
          _animes = animes;
          _isLoading = false;
        });
        //debugPrint('[NewSeriesPage _loadAnimes] After final setState - _animes.length now: ${_animes.length}, _isLoading: $_isLoading');
      }
      ////debugPrint('番剧数据加载完成');
    } catch (e) {
      ////debugPrint('加载番剧数据时出错: $e');
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

  Future<void> _loadTranslationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedString = prefs.getString(_translationCacheKey);
      
      if (cachedString != null) {
        ////debugPrint('找到翻译缓存数据');
        final data = json.decode(cachedString);
        final timestamp = data['timestamp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        
        ////debugPrint('缓存时间戳: $timestamp');
        ////debugPrint('当前时间戳: $now');
        ////debugPrint('时间差: ${now - timestamp}ms');
        ////debugPrint('缓存有效期: ${_translationCacheDuration.inMilliseconds}ms');
        
        // 检查缓存是否过期
        if (now - timestamp <= _translationCacheDuration.inMilliseconds) {
          final translations = Map<String, String>.from(data['translations']);
          // 将字符串键转换回整数
          final Map<int, String> parsedTranslations = {};
          translations.forEach((key, value) {
            parsedTranslations[int.parse(key)] = value;
          });
          ////debugPrint('从缓存加载翻译，共 ${parsedTranslations.length} 条');
          setState(() {
            _translatedSummaries = parsedTranslations;
          });
        } else {
          ////debugPrint('翻译缓存已过期，清除缓存');
          await prefs.remove(_translationCacheKey);
        }
      } else {
        ////debugPrint('未找到翻译缓存');
      }
    } catch (e) {
      ////debugPrint('加载翻译缓存失败: $e');
    }
  }

  Future<void> _saveTranslationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 确保所有值都是可序列化的字符串
      final Map<String, String> serializableTranslations = {};
      _translatedSummaries.forEach((key, value) {
        serializableTranslations[key.toString()] = value;
      });
      
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'translations': serializableTranslations,
      };
      final jsonString = json.encode(data);
      await prefs.setString(_translationCacheKey, jsonString);
      ////debugPrint('保存翻译到缓存，共 ${_translatedSummaries.length} 条');
      ////debugPrint('缓存数据大小: ${jsonString.length} 字节');
    } catch (e) {
      ////debugPrint('保存翻译缓存失败: $e');
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
              ),
              const SizedBox(height: 16), // 按钮之间的间距
              // 排序按钮
              FloatingActionGlassButton(
                iconData: _isReversed ? Ionicons.chevron_up_outline : Ionicons.chevron_down_outline,
                onPressed: _toggleSort,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnimeCard(BuildContext context, BangumiAnime anime, {Key? key}) {
    return AnimeCard(
      key: key,
      name: _isShowingTranslation && _translatedSummaries.containsKey(anime.id) 
          ? _translatedSummaries[anime.id]! 
          : anime.nameCn,
      imageUrl: anime.imageUrl,
      isOnAir: false,
      onTap: () => _showAnimeDetail(anime),
    );
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

  Future<String?> _translateSummary(String text) async {
    try {
      final appSecret = await DandanplayService.getAppSecret();
      ////debugPrint('开始请求翻译...');
      final response = await http.post(
        Uri.parse('https://nipaplay.aimes-soft.com/tran.php'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'appSecret': appSecret,
          'text': text,
        }),
      );

      if (response.statusCode == 200) {
        ////debugPrint('翻译请求成功');
        return response.body;
      }
      ////debugPrint('翻译请求失败，状态码: ${response.statusCode}');
      return null;
    } catch (e) {
      ////debugPrint('翻译请求异常: $e');
      return null;
    }
  }

  Future<void> _showAnimeDetail(BangumiAnime animeFromList) async {
    // 使用新的静态show方法，而不是TransparentPageRoute
    final result = await AnimeDetailPage.show(context, animeFromList.id);

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
                  if (mainPageState.globalTabController!.index != 0) {
                    mainPageState.globalTabController!.animateTo(0);
                    debugPrint('[NewSeriesPage _handlePlayEpisode] Directly called mainPageState.globalTabController.animateTo(0)');
                  } else {
                    debugPrint('[NewSeriesPage _handlePlayEpisode] mainPageState.globalTabController is already at index 0.');
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

  Future<String?> _translateSummaryWithCache(int animeId, String text) async {
    if (_translatedSummaries.containsKey(animeId) && _isShowingTranslation) { // Check _isShowingTranslation as well
      return _translatedSummaries[animeId];
    }
    // This function is now primarily used by the old logic if any, 
    // TranslationButton has its own _translateSummary.
    // However, keeping it for now. The button's internal logic is preferred.
    final translation = await _translateSummary(text); // _translateSummary is the actual API call
    if (translation != null) {
      // No setState here, the caller (TranslationButton or old logic) should handle state.
      return translation;
    }
    return null;
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
            sigmaX: 25,
            sigmaY: 25,
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