import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/widgets/nipaplay_theme/themed_anime_detail.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_anime_card.dart';
import 'package:nipaplay/main.dart';
import 'package:nipaplay/services/search_service.dart';
import 'package:nipaplay/models/search_model.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Fluent UI 风格的新番更新页面
class FluentNewSeriesPage extends StatefulWidget {
  const FluentNewSeriesPage({super.key});

  @override
  State<FluentNewSeriesPage> createState() => _FluentNewSeriesPageState();
}

class _FluentNewSeriesPageState extends State<FluentNewSeriesPage> 
    with AutomaticKeepAliveClientMixin<FluentNewSeriesPage> {
  final BangumiService _bangumiService = BangumiService.instance;
  List<BangumiAnime> _animes = [];
  bool _isLoading = true;
  String? _error;
  bool _isReversed = false;
  String _searchQuery = '';
  
  // 分组状态
  final Map<int, bool> _expansionStates = {};
  
  // 筛选状态
  bool _showOnlyAiring = false;
  double _minRating = 0.0;

  @override
  bool get wantKeepAlive => true;

  // 星期几映射
  static const Map<int, String> _weekdays = {
    0: '周日',
    1: '周一', 
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    -1: '未知时间',
  };

  @override
  void initState() {
    super.initState();
    _loadAnimes();
    
    // 默认展开今天的分组
    final today = DateTime.now().weekday % 7;
    _expansionStates[today] = true;
  }

  @override
  void dispose() {
    // 释放图片资源
    for (var anime in _animes) {
      ImageCacheManager.instance.releaseImage(anime.imageUrl);
    }
    super.dispose();
  }

  Future<void> _loadAnimes({bool forceRefresh = false}) async {
    try {
      if (!mounted) return;
      
      setState(() {
        _isLoading = true;
        _error = null;
      });

      List<BangumiAnime> animes;

      if (kIsWeb) {
        // Web环境：从本地API获取
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
        // 移动端/桌面端环境：从服务获取
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

  /// 按星期几分组番剧并应用筛选
  Map<int, List<BangumiAnime>> _groupAnimesByWeekday() {
    final grouped = <int, List<BangumiAnime>>{};
    
    // 应用筛选条件
    final filteredAnimes = _animes.where((anime) {
      // 基础过滤
      if (anime.imageUrl.isEmpty || anime.imageUrl == 'assets/backempty.png') {
        return false;
      }
      
      // 搜索过滤
      if (_searchQuery.isNotEmpty &&
          !anime.nameCn.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !anime.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      
      // 连载状态过滤
      if (_showOnlyAiring && !(anime.isOnAir ?? false)) {
        return false;
      }
      
      // 评分过滤
      if (_minRating > 0.0 && (anime.rating == null || anime.rating! < _minRating)) {
        return false;
      }
      
      return true;
    }).toList();

    // 处理未知时间的番剧
    final unknownAnimes = filteredAnimes.where((anime) => 
      anime.airWeekday == null || 
      anime.airWeekday == -1 || 
      anime.airWeekday! < 0 || 
      anime.airWeekday! > 6
    ).toList();
    
    if (unknownAnimes.isNotEmpty) {
      grouped[-1] = unknownAnimes;
    }
    
    // 按星期分组
    for (var anime in filteredAnimes) {
      if (anime.airWeekday != null && 
          anime.airWeekday! >= 0 && 
          anime.airWeekday! <= 6) {
        grouped.putIfAbsent(anime.airWeekday!, () => []).add(anime);
      }
    }
    
    return grouped;
  }

  /// 显示番剧详情
  Future<void> _showAnimeDetail(BangumiAnime anime) async {
    final result = await ThemedAnimeDetail.show(context, anime.id);

    if (result is WatchHistoryItem && mounted) {
      _handlePlayEpisode(result);
    }
  }

  /// 处理播放集数
  Future<void> _handlePlayEpisode(WatchHistoryItem historyItem) async {
    if (!mounted) return;

    try {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      await videoState.initializePlayer(historyItem.filePath, historyItem: historyItem);
      
      // 切换到播放页面
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try {
            MainPageState? mainPageState = MainPageState.of(context);
            if (mainPageState?.globalTabController != null) {
              mainPageState!.globalTabController!.animateTo(1);
            }
          } catch (e) {
            debugPrint("Error switching to player tab: $e");
          }
        }
      });
    } catch (e) {
      if (mounted) {
        displayInfoBar(
          context, 
          builder: (context, close) => InfoBar(
            title: const Text('播放失败'),
            content: Text('处理播放请求时出错: $e'),
            severity: InfoBarSeverity.error,
            action: IconButton(
              icon: const Icon(FluentIcons.chrome_close),
              onPressed: close,
            ),
          ),
        );
      }
    }
  }

  /// 切换排序方向
  void _toggleSort() {
    setState(() {
      _isReversed = !_isReversed;
    });
  }

  /// 从日期字符串中提取年份
  int? _extractYearFromDate(String dateStr) {
    try {
      if (dateStr.isEmpty) return null;
      final parts = dateStr.split('-');
      if (parts.isNotEmpty) {
        return int.tryParse(parts[0]);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 显示标签搜索面板
  void _showTagSearchPanel() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _FluentTagSearchDialog(
        onAnimeSelected: (anime) => _showAnimeDetail(anime),
      ),
    );
  }

  /// 显示搜索和筛选面板
  void _showFilterPanel() {
    showDialog(
      context: context,
      builder: (context) => _FilterDialog(
        searchQuery: _searchQuery,
        showOnlyAiring: _showOnlyAiring,
        minRating: _minRating,
        onChanged: (query, airing, rating) {
          setState(() {
            _searchQuery = query;
            _showOnlyAiring = airing;
            _minRating = rating;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = FluentTheme.of(context);
    
    return ScaffoldPage(
      content: Column(
        children: [
          _buildHeader(theme),
          Expanded(
            child: _buildContent(theme),
          ),
        ],
      ),
    );
  }

  /// 构建页面头部
  Widget _buildHeader(FluentThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          // 标题
          Expanded(
            child: Text(
              '新番更新',
              style: theme.typography.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          
          // 右侧按钮组
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Button(
                onPressed: _showTagSearchPanel,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.tag, size: 16),
                    SizedBox(width: 6),
                    Text('标签搜索'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: _showFilterPanel,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.filter, size: 16),
                    SizedBox(width: 6),
                    Text('筛选'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: _toggleSort,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isReversed ? FluentIcons.sort_up : FluentIcons.sort_down,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(_isReversed ? '倒序' : '正序'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isLoading ? null : () => _loadAnimes(forceRefresh: true),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.refresh, size: 16),
                    SizedBox(width: 6),
                    Text('刷新'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建主要内容
  Widget _buildContent(FluentThemeData theme) {
    if (_isLoading && _animes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressRing(),
            SizedBox(height: 16),
            Text('正在加载新番列表...'),
          ],
        ),
      );
    }

    if (_error != null && _animes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.error,
              size: 48,
              color: theme.inactiveColor,
            ),
            const SizedBox(height: 16),
            Text(
              '加载失败: $_error',
              style: theme.typography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _loadAnimes(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final groupedAnimes = _groupAnimesByWeekday();
    
    if (groupedAnimes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.search,
              size: 48,
              color: theme.inactiveColor,
            ),
            const SizedBox(height: 16),
            const Text('没有找到符合条件的番剧'),
            const SizedBox(height: 8),
            HyperlinkButton(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _showOnlyAiring = false;
                  _minRating = 0.0;
                });
              },
              child: const Text('清除筛选条件'),
            ),
          ],
        ),
      );
    }

    return _buildAnimeList(groupedAnimes, theme);
  }

  /// 构建番剧列表
  Widget _buildAnimeList(Map<int, List<BangumiAnime>> groupedAnimes, FluentThemeData theme) {
    final knownWeekdays = groupedAnimes.keys.where((day) => day != -1).toList();
    final unknownWeekdays = groupedAnimes.keys.where((day) => day == -1).toList();

    // 排序已知星期
    knownWeekdays.sort((a, b) {
      final today = DateTime.now().weekday % 7;
      if (a == today) return -1;
      if (b == today) return 1;
      final distA = (a - today + 7) % 7;
      final distB = (b - today + 7) % 7;
      return _isReversed ? distB.compareTo(distA) : distA.compareTo(distB);
    });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        // 已知星期的分组
        ...knownWeekdays.map((weekday) => _buildWeekdaySection(
          weekday, 
          groupedAnimes[weekday]!, 
          theme
        )),
        
        // 未知时间的分组
        if (unknownWeekdays.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildWeekdaySection(-1, groupedAnimes[-1]!, theme),
        ],
      ],
    );
  }

  /// 构建单个星期分组
  Widget _buildWeekdaySection(int weekday, List<BangumiAnime> animes, FluentThemeData theme) {
    _expansionStates.putIfAbsent(weekday, () => weekday == (DateTime.now().weekday % 7));
    final isExpanded = _expansionStates[weekday]!;
    final weekdayName = _weekdays[weekday] ?? '未知';
    final today = DateTime.now().weekday % 7;
    final isToday = weekday == today;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Expander(
        header: Row(
          children: [
            Text(
              weekdayName,
              style: theme.typography.subtitle?.copyWith(
                fontWeight: FontWeight.w600,
                color: isToday ? theme.accentColor : null,
              ),
            ),
            const SizedBox(width: 8),
            if (isToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.accentColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '今天',
                  style: theme.typography.caption?.copyWith(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ),
            const Spacer(),
            Text(
              '${animes.length} 部',
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ],
        ),
        initiallyExpanded: isExpanded,
        onStateChanged: (expanded) {
          setState(() {
            _expansionStates[weekday] = expanded;
          });
        },
        content: _buildAnimeGrid(animes),
      ),
    );
  }

  /// 构建番剧网格
  Widget _buildAnimeGrid(List<BangumiAnime> animes) {
    return Container(
      padding: const EdgeInsets.only(top: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180, // 稍微增大卡片宽度
          childAspectRatio: 0.65, // 保持宽高比
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: animes.length,
        itemBuilder: (context, index) {
          final anime = animes[index];
          return FluentAnimeCard(
            name: anime.nameCn,
            imageUrl: anime.imageUrl,
            isOnAir: anime.isOnAir ?? false,
            source: 'Bangumi',
            rating: anime.rating,
            ratingDetails: anime.ratingDetails,
            year: anime.airDate != null ? _extractYearFromDate(anime.airDate!) : null,
            onTap: () => _showAnimeDetail(anime),
          );
        },
      ),
    );
  }
}

/// 筛选对话框
class _FilterDialog extends StatefulWidget {
  final String searchQuery;
  final bool showOnlyAiring;
  final double minRating;
  final Function(String, bool, double) onChanged;

  const _FilterDialog({
    required this.searchQuery,
    required this.showOnlyAiring,
    required this.minRating,
    required this.onChanged,
  });

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late TextEditingController _searchController;
  late bool _showOnlyAiring;
  late double _minRating;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
    _showOnlyAiring = widget.showOnlyAiring;
    _minRating = widget.minRating;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    return ContentDialog(
      title: const Text('筛选条件'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('搜索', style: theme.typography.subtitle),
          const SizedBox(height: 8),
          TextBox(
            controller: _searchController,
            placeholder: '输入番剧名称...',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(FluentIcons.search, size: 16),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Checkbox(
            checked: _showOnlyAiring,
            onChanged: (value) => setState(() => _showOnlyAiring = value ?? false),
            content: const Text('仅显示连载中'),
          ),
          
          const SizedBox(height: 16),
          
          Text('最低评分: ${_minRating.toStringAsFixed(1)}', style: theme.typography.subtitle),
          const SizedBox(height: 8),
          Slider(
            value: _minRating,
            min: 0.0,
            max: 10.0,
            divisions: 20,
            onChanged: (value) => setState(() => _minRating = value),
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () {
            // 重置所有筛选条件
            setState(() {
              _searchController.clear();
              _showOnlyAiring = false;
              _minRating = 0.0;
            });
          },
          child: const Text('重置'),
        ),
        FilledButton(
          onPressed: () {
            widget.onChanged(_searchController.text, _showOnlyAiring, _minRating);
            Navigator.of(context).pop();
          },
          child: const Text('应用'),
        ),
      ],
    );
  }
}

/// Fluent UI风格的标签搜索对话框
class _FluentTagSearchDialog extends StatefulWidget {
  final Function(BangumiAnime) onAnimeSelected;

  const _FluentTagSearchDialog({
    required this.onAnimeSelected,
  });

  @override
  State<_FluentTagSearchDialog> createState() => _FluentTagSearchDialogState();
}

class _FluentTagSearchDialogState extends State<_FluentTagSearchDialog> {
  final SearchService _searchService = SearchService.instance;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  
  final List<String> _tags = [];
  List<SearchResultAnime> _searchResults = [];
  bool _isSearching = false;
  String _currentSearchMode = 'name'; // 'name' 或 'tags'

  @override
  void dispose() {
    _searchController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  /// 添加标签
  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      if (_tags.length >= 10) {
        _showInfoBar('最多只能添加10个标签', InfoBarSeverity.warning);
        return;
      }
      setState(() {
        _tags.add(tag);
        _tagController.clear();
      });
    }
  }

  /// 删除标签
  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  /// 执行搜索
  Future<void> _performSearch() async {
    if (_currentSearchMode == 'name') {
      final query = _searchController.text.trim();
      if (query.isEmpty) {
        _showInfoBar('请输入搜索关键词', InfoBarSeverity.warning);
        return;
      }
      await _searchByName(query);
    } else {
      if (_tags.isEmpty) {
        _showInfoBar('请至少添加一个标签', InfoBarSeverity.warning);
        return;
      }
      await _searchByTags();
    }
  }

  /// 按名称搜索
  Future<void> _searchByName(String query) async {
    setState(() {
      _isSearching = true;
      _searchResults.clear();
    });

    try {
      final result = await _searchService.searchAnimeAdvanced(keyword: query);
      setState(() {
        _searchResults = result.animes;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      _showInfoBar('搜索失败: $e', InfoBarSeverity.error);
    }
  }

  /// 按标签搜索
  Future<void> _searchByTags() async {
    setState(() {
      _isSearching = true;
      _searchResults.clear();
    });

    try {
      final result = await _searchService.searchAnimeByTags(_tags);
      setState(() {
        _searchResults = result.animes;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      _showInfoBar('搜索失败: $e', InfoBarSeverity.error);
    }
  }

  /// 显示信息条
  void _showInfoBar(String message, InfoBarSeverity severity) {
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: Text(message),
        severity: severity,
        action: IconButton(
          icon: const Icon(FluentIcons.chrome_close),
          onPressed: close,
        ),
      ),
    );
  }

  /// 处理番剧选择
  void _handleAnimeSelection(SearchResultAnime searchAnime) {
    // 转换为BangumiAnime
    final bangumiAnime = BangumiAnime(
      id: searchAnime.animeId,
      name: searchAnime.animeTitle,
      nameCn: searchAnime.animeTitle,
      imageUrl: searchAnime.imageUrl ?? 'assets/backempty.png',
      rating: searchAnime.rating,
      summary: searchAnime.intro,
      typeDescription: searchAnime.typeDescription,
      isOnAir: searchAnime.isOnAir,
    );
    
    Navigator.of(context).pop();
    widget.onAnimeSelected(bangumiAnime);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
      title: const Text('标签搜索'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 搜索模式选择
          Row(
            children: [
              Expanded(
                child: RadioButton(
                  checked: _currentSearchMode == 'name',
                  onChanged: (checked) {
                    if (checked) {
                      setState(() => _currentSearchMode = 'name');
                    }
                  },
                  content: const Text('按名称搜索'),
                ),
              ),
              Expanded(
                child: RadioButton(
                  checked: _currentSearchMode == 'tags',
                  onChanged: (checked) {
                    if (checked) {
                      setState(() => _currentSearchMode = 'tags');
                    }
                  },
                  content: const Text('按标签搜索'),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 搜索输入区域
          if (_currentSearchMode == 'name') ...[
            TextBox(
              controller: _searchController,
              placeholder: '输入番剧名称...',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(FluentIcons.search, size: 16),
              ),
              onSubmitted: (_) => _performSearch(),
            ),
          ] else ...[
            // 标签输入
            Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _tagController,
                    placeholder: '输入标签...',
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(FluentIcons.tag, size: 16),
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: _addTag,
                  child: const Text('添加'),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 标签列表
            if (_tags.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.resources.controlFillColorSecondary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tag,
                          style: theme.typography.caption?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _removeTag(tag),
                          child: Icon(
                            FluentIcons.chrome_close,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
          
          // 搜索按钮
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isSearching ? null : _performSearch,
                  child: _isSearching
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: ProgressRing(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('搜索中...'),
                          ],
                        )
                      : const Text('搜索'),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 搜索结果
          if (_searchResults.isNotEmpty) ...[
            Text(
              '搜索结果 (${_searchResults.length})',
              style: theme.typography.subtitle,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final anime = _searchResults[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: anime.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                anime.imageUrl!,
                                width: 48,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 48,
                                  height: 64,
                                  color: theme.resources.controlStrokeColorSecondary,
                                  child: Icon(
                                    FluentIcons.photo2,
                                    color: theme.inactiveColor,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              width: 48,
                              height: 64,
                              color: theme.resources.controlStrokeColorSecondary,
                              child: Icon(
                                FluentIcons.photo2,
                                color: theme.inactiveColor,
                              ),
                            ),
                      title: Text(
                        anime.animeTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (anime.rating > 0)
                            Text('评分: ${anime.rating.toStringAsFixed(1)}'),
                          if (anime.typeDescription != null && anime.typeDescription!.isNotEmpty)
                            Text(
                              '类型: ${anime.typeDescription}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (anime.intro != null && anime.intro!.isNotEmpty)
                            Text(
                              anime.intro!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.caption?.copyWith(
                                color: theme.inactiveColor,
                              ),
                            ),
                        ],
                      ),
                      onPressed: () => _handleAnimeSelection(anime),
                    ),
                  );
                },
              ),
            ),
          ] else if (!_isSearching && _searchResults.isEmpty && 
                    ((_currentSearchMode == 'name' && _searchController.text.isNotEmpty) ||
                     (_currentSearchMode == 'tags' && _tags.isNotEmpty))) ...[
            Center(
              child: Column(
                children: [
                  Icon(
                    FluentIcons.search,
                    size: 48,
                    color: theme.inactiveColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '没有找到匹配的番剧',
                    style: theme.typography.body,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}