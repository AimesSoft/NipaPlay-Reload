import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import '../services/search_service.dart';
import '../models/search_model.dart';
import '../models/watch_history_model.dart';
import '../widgets/cached_network_image_widget.dart';
import '../widgets/blur_snackbar.dart';
import '../pages/anime_detail_page.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../main.dart';
import '../utils/tab_change_notifier.dart';
import '../widgets/blur_dropdown.dart';

class TagSearchModal extends StatefulWidget {
  final String? prefilledTag;
  final List<String>? preselectedTags;
  final VoidCallback? onBeforeOpenAnimeDetail;

  const TagSearchModal({
    super.key, 
    this.prefilledTag, 
    this.preselectedTags,
    this.onBeforeOpenAnimeDetail,
  });

  @override
  State<TagSearchModal> createState() => _TagSearchModalState();
}

class _TagSearchModalState extends State<TagSearchModal>
    with TickerProviderStateMixin {
  final SearchService _searchService = SearchService.instance;
  late TabController _tabController;

  // 文本标签搜索相关
  final TextEditingController _textTagController = TextEditingController();
  final List<String> _textTags = [];
  List<SearchResultAnime> _textSearchResults = [];
  List<SearchResultAnime> _displayedTextResults = []; // 当前显示的结果
  bool _isTextSearching = false;

  // 高级搜索相关
  SearchConfig? _searchConfig;
  final TextEditingController _keywordController = TextEditingController();
  final List<int> _selectedTagIds = [];
  final List<ConfigItem> _selectedTags = [];
  int? _selectedType;
  int? _selectedYear;
  double _minRating = 0.0;
  double _maxRating = 10.0;
  final int _sortOption = 0;
  List<SearchResultAnime> _advancedSearchResults = [];
  List<SearchResultAnime> _displayedAdvancedResults = []; // 当前显示的结果
  bool _isAdvancedSearching = false;
  bool _isLoadingConfig = false;

  // 分页相关
  static const int _pageSize = 20; // 每页显示的数量
  int _currentTextPage = 0;
  int _currentAdvancedPage = 0;
  bool _isLoadingMoreText = false;
  bool _isLoadingMoreAdvanced = false;

  // 滚动控制器
  final ScrollController _advancedScrollController = ScrollController();

  // 年份筛选的GlobalKey
  final GlobalKey _yearDropdownKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 只为高级搜索添加滚动监听器
    _advancedScrollController.addListener(_onAdvancedScroll);

    // 如果有预填充标签，直接添加并搜索
    if (widget.prefilledTag != null) {
      _textTags.add(widget.prefilledTag!);
      _performTextSearch();
    }
    // 如果有预选择的标签，不自动添加到搜索标签中，只显示在"当前标签"区域
    else if (widget.preselectedTags != null && widget.preselectedTags!.isNotEmpty) {
      // 切换到文本标签搜索tab
      _tabController.index = 0;
      // 仍需要加载搜索配置，以防用户切换到高级搜索
      _loadSearchConfig();
    } else {
      _loadSearchConfig();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textTagController.dispose();
    _keywordController.dispose();
    // 只dispose高级搜索的滚动控制器
    _advancedScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSearchConfig() async {
    setState(() {
      _isLoadingConfig = true;
    });

    try {
      final config = await _searchService.getSearchConfig();
      setState(() {
        _searchConfig = config;
        _isLoadingConfig = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingConfig = false;
      });
      _showErrorSnackBar('加载搜索配置失败: $e');
    }
  }

  // 文本标签搜索方法
  void _addTextTag() {
    final text = _textTagController.text.trim();
    if (text.isNotEmpty && !_textTags.contains(text)) {
      if (_textTags.length >= 10) {
        _showErrorSnackBar('最多只能添加10个标签');
        return;
      }
      if (text.length > 50) {
        _showErrorSnackBar('单个标签长度不能超过50个字符');
        return;
      }
      setState(() {
        _textTags.add(text);
        _textTagController.clear();
      });
    }
  }

  void _removeTextTag(String tag) {
    setState(() {
      _textTags.remove(tag);
    });
  }

  Future<void> _performTextSearch() async {
    if (_textTags.isEmpty) {
      _showErrorSnackBar('请至少添加一个标签');
      return;
    }

    setState(() {
      _isTextSearching = true;
      _textSearchResults.clear();
      _displayedTextResults.clear();
      _currentTextPage = 0;
    });

    try {
      final result = await _searchService.searchAnimeByTags(_textTags);
      setState(() {
        _textSearchResults = result.animes;
        _isTextSearching = false;

        // 显示第一页结果
        _currentTextPage = 1;
        final endIndex = (_pageSize).clamp(0, _textSearchResults.length);
        _displayedTextResults = _textSearchResults.sublist(0, endIndex);
      });
    } catch (e) {
      setState(() {
        _isTextSearching = false;
      });
      _showErrorSnackBar('搜索失败: $e');
    }
  }

  // 高级搜索方法
  void _toggleTag(ConfigItem tag) {
    setState(() {
      if (_selectedTagIds.contains(tag.key)) {
        _selectedTagIds.remove(tag.key);
        _selectedTags.removeWhere((t) => t.key == tag.key);
      } else {
        _selectedTagIds.add(tag.key);
        _selectedTags.add(tag);
      }
    });
  }

  Future<void> _performAdvancedSearch() async {
    setState(() {
      _isAdvancedSearching = true;
      _advancedSearchResults.clear();
      _displayedAdvancedResults.clear();
      _currentAdvancedPage = 0;
    });

    try {
      final result = await _searchService.searchAnimeAdvanced(
        keyword: _keywordController.text.trim().isEmpty
            ? null
            : _keywordController.text.trim(),
        type: _selectedType,
        tagIds: _selectedTagIds.isEmpty ? null : _selectedTagIds,
        year: _selectedYear,
        minRate: _minRating.round(),
        maxRate: _maxRating.round(),
        sort: _sortOption,
      );
      setState(() {
        _advancedSearchResults = result.animes;
        _isAdvancedSearching = false;

        // 显示第一页结果
        _currentAdvancedPage = 1;
        final endIndex = (_pageSize).clamp(0, _advancedSearchResults.length);
        _displayedAdvancedResults = _advancedSearchResults.sublist(0, endIndex);
      });
    } catch (e) {
      setState(() {
        _isAdvancedSearching = false;
      });
      _showErrorSnackBar('高级搜索失败: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    BlurSnackBar.show(
      context,
      message,
    );
  }

  void _openAnimeDetail(int animeId) {
    // 先关闭搜索弹出框
    Navigator.pop(context);
    
    // 如果有回调，先执行回调（通常是关闭当前番剧详情页面）
    if (widget.onBeforeOpenAnimeDetail != null) {
      widget.onBeforeOpenAnimeDetail!();
    }
    
    // 延迟一帧后打开新的番剧详情页面，确保之前的页面已关闭
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 检查widget是否仍然挂载
      if (!mounted) return;
      
      // 如果没有提供回调，使用默认的关闭逻辑（用于从其他地方调用）
      if (widget.onBeforeOpenAnimeDetail == null) {
        // 查找并关闭可能存在的番剧详情页面（DialogRoute类型）
        Navigator.of(context).popUntil((route) {
          // 检查是否是对话框路由（番剧详情页面使用showGeneralDialog创建）
          if (route is DialogRoute) {
            return false; // 关闭这个对话框路由
          }
          return true; // 保留其他路由
        });
      }
      
      // 打开新的番剧详情页面，并处理返回的播放历史记录
      AnimeDetailPage.show(context, animeId).then((historyItem) {
        // 检查widget是否仍然挂载，避免在widget销毁后访问context
        if (!mounted) return;
        
        if (historyItem != null) {
          _handlePlayEpisode(historyItem);
        }
      });
    });
  }

  // 新增：处理播放剧集的方法，与其他页面保持一致
  void _handlePlayEpisode(WatchHistoryItem historyItem) {
    if (!mounted) return;

    debugPrint('[TagSearchWidget] _handlePlayEpisode: 开始处理播放请求');
    debugPrint('[TagSearchWidget] 文件路径: ${historyItem.filePath}');

    // 检查文件是否存在
    final videoFile = File(historyItem.filePath);
    if (!videoFile.existsSync()) {
      debugPrint('[TagSearchWidget] 文件不存在: ${historyItem.filePath}');
      BlurSnackBar.show(context, '文件不存在或无法访问: ${path.basename(historyItem.filePath)}');
      return;
    }

    bool tabChangeLogicExecuted = false;

    try {
      // 获取视频播放状态
      final videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
      debugPrint('[TagSearchWidget] 获取到VideoPlayerState，当前状态: ${videoPlayerState.status}');

      late VoidCallback statusListener;
      statusListener = () {
        if (!mounted) {
          debugPrint('[TagSearchWidget] Widget已销毁，移除监听器');
          videoPlayerState.removeListener(statusListener);
          return;
        }
        
        debugPrint('[TagSearchWidget] 播放器状态变化: ${videoPlayerState.status}');
        
        if ((videoPlayerState.status == PlayerStatus.ready || 
             videoPlayerState.status == PlayerStatus.playing) && 
            !tabChangeLogicExecuted) {
          tabChangeLogicExecuted = true;
          debugPrint('[TagSearchWidget] 播放器准备就绪，开始切换页面');
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              try {
                // 首先尝试通过Navigator找到根context
                final rootContext = Navigator.of(context, rootNavigator: true).context;
                debugPrint('[TagSearchWidget] 尝试使用根context切换页面');
                
                // 尝试从根context获取MainPageState
                MainPageState? mainPageState;
                try {
                  mainPageState = MainPageState.of(rootContext);
                } catch (e) {
                  debugPrint('[TagSearchWidget] 从根context获取MainPageState失败: $e');
                  // 如果失败，尝试从当前context获取
                  try {
                    mainPageState = MainPageState.of(context);
                  } catch (e2) {
                    debugPrint('[TagSearchWidget] 从当前context获取MainPageState也失败: $e2');
                  }
                }
                
                if (mainPageState != null && mainPageState.globalTabController != null) {
                  if (mainPageState.globalTabController!.index != 0) {
                    mainPageState.globalTabController!.animateTo(0);
                    debugPrint('[TagSearchWidget] 成功切换到播放页面 (tab 0)');
                  } else {
                    debugPrint('[TagSearchWidget] 已经在播放页面 (tab 0)');
                  }
                } else {
                  debugPrint('[TagSearchWidget] 无法获取MainPageState，尝试备用方案');
                  // 备用方案：使用TabChangeNotifier
                  try {
                    final tabNotifier = Provider.of<TabChangeNotifier>(rootContext, listen: false);
                    tabNotifier.changeTab(0);
                    debugPrint('[TagSearchWidget] 使用TabChangeNotifier成功切换页面');
                  } catch (e) {
                    debugPrint('[TagSearchWidget] TabChangeNotifier也失败: $e');
                    // 最后的备用方案：直接关闭所有模态对话框
                    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
                    debugPrint('[TagSearchWidget] 关闭所有模态对话框作为备用方案');
                  }
                }
              } catch (e) {
                debugPrint("[TagSearchWidget] 切换页面时出错: $e");
              }
              videoPlayerState.removeListener(statusListener);
            } else {
              videoPlayerState.removeListener(statusListener);
            }
          });
        } else if (videoPlayerState.status == PlayerStatus.error) {
          videoPlayerState.removeListener(statusListener);
          debugPrint('[TagSearchWidget] 播放器错误: ${videoPlayerState.error}');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              BlurSnackBar.show(context, '播放器加载失败: ${videoPlayerState.error ?? '未知错误'}');
            }
          });
        }
      };

      videoPlayerState.addListener(statusListener);
      debugPrint('[TagSearchWidget] 添加状态监听器，开始初始化播放器');
      
      // 启动视频播放
      videoPlayerState.initializePlayer(historyItem.filePath, historyItem: historyItem);
      
    } catch (e) {
      debugPrint('[TagSearchWidget] 播放器初始化异常: $e');
      if (mounted) {
        BlurSnackBar.show(context, '播放器初始化失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: GlassmorphicContainer(
        width: double.infinity,
        height: double.infinity,
        borderRadius: 20,
        blur: 20,
        alignment: Alignment.center,
        border: 1,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.3),
            Colors.white.withOpacity(0.25),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.5),
            Colors.white.withOpacity(0.5),
          ],
        ),
        child: Column(
          children: [
            // 拖拽指示器
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 标题
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                widget.prefilledTag != null
                    ? '标签搜索: ${widget.prefilledTag}'
                    : (widget.preselectedTags != null && widget.preselectedTags!.isNotEmpty)
                        ? '标签搜索 (从 ${widget.preselectedTags!.length} 个当前标签中选择)'
                        : '标签搜索',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Tab栏（仅在无预填充标签时显示）
            if (widget.prefilledTag == null) ...[
              TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                dividerHeight: 3.0,
                dividerColor: const Color.fromARGB(59, 255, 255, 255),
                indicatorPadding: const EdgeInsets.only(
              top: 45, left: 0, right: 0),
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                unselectedLabelColor: Colors.white.withOpacity(0.7),
                tabs: const [
                  Tab(text: '文本标签搜索'),
                  Tab(text: '高级搜索'),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // 内容区域
            Expanded(
              child: widget.prefilledTag != null
                  ? _buildPrefilledTagSearch()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTextSearchTab(),
                        _buildAdvancedSearchTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrefilledTagSearch() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 显示当前搜索的标签
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Ionicons.pricetag, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    widget.prefilledTag!,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 搜索结果标题
          if (_displayedTextResults.isNotEmpty || _isTextSearching) ...[
            const Text(
              '搜索结果',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 搜索结果列表
          ..._buildScrollableSearchResults(
              _displayedTextResults,
              _isTextSearching,
              _isLoadingMoreText,
              _textSearchResults.length),
        ],
      ),
    );
  }

  Widget _buildTextSearchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当前标签区域（预选标签菜单）
          if (widget.preselectedTags != null && widget.preselectedTags!.isNotEmpty) ...[
            Container(
              width: double.infinity, // 确保顶满宽度
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '当前标签 (点击添加到搜索)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.preselectedTags!
                        .map((tag) => GestureDetector(
                              onTap: () {
                                // 从当前标签添加到已添加标签
                                if (!_textTags.contains(tag)) {
                                  setState(() {
                                    _textTags.add(tag);
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _textTags.contains(tag) 
                                      ? Colors.white.withOpacity(0.3)  // 已添加的标签显示更亮的白色
                                      : Colors.white.withOpacity(0.15), // 未添加的标签显示较暗的白色
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_textTags.contains(tag))
                                      const Icon(
                                        Ionicons.checkmark_circle,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    if (_textTags.contains(tag))
                                      const SizedBox(width: 4),
                                    Text(
                                      tag,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 标签输入区域
          Container(
            width: double.infinity, // 确保顶满宽度
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '添加标签',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textTagController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '输入标签名称',
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.7)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.white),
                          ),
                        ),
                        onSubmitted: (_) => _addTextTag(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _addTextTag,
                      icon:
                          const Icon(Ionicons.add_circle, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_textTags.isNotEmpty) ...[
                  const Text(
                    '已添加标签 (用于搜索):',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _textTags
                        .map((tag) => GestureDetector(
                              onTap: () {
                                // 点击标签填充到输入框
                                _textTagController.text = tag;
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      tag,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () => _removeTextTag(tag),
                                      child: const Icon(
                                        Ionicons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isTextSearching ? null : _performTextSearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      foregroundColor: Colors.white,
                      elevation: 0, // 去掉阴影
                      shadowColor: Colors.transparent, // 确保阴影完全透明
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isTextSearching
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('搜索'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 搜索结果标题
          if (_displayedTextResults.isNotEmpty || _isTextSearching) ...[
            const Text(
              '搜索结果',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 搜索结果列表
          ..._buildScrollableSearchResults(
              _displayedTextResults,
              _isTextSearching,
              _isLoadingMoreText,
              _textSearchResults.length),
        ],
      ),
    );
  }

  // 构建可滚动的搜索结果列表
  List<Widget> _buildScrollableSearchResults(List<SearchResultAnime> results, bool isLoading,
      bool isLoadingMore, int totalResults) {
    List<Widget> widgets = [];

    if (isLoading && results.isEmpty) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
      return widgets;
    }

    if (results.isEmpty && !isLoading) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Ionicons.search,
                  size: 64,
                  color: Colors.white.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无搜索结果',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return widgets;
    }

    // 添加搜索结果项
    for (int index = 0; index < results.length; index++) {
      final anime = results[index];
      widgets.add(
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Card(
            color: Colors.white.withOpacity(0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () => _openAnimeDetail(anime.animeId),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 120, // 固定卡片高度
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 封面图片 - 左侧
                    Container(
                      width: 80, // 固定宽度
                      height: double.infinity, // 顶满高度
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white.withOpacity(0.1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: anime.imageUrl != null
                            ? CachedNetworkImageWidget(
                                imageUrl: kIsWeb
                                    ? '/api/image_proxy?url=${base64Url.encode(utf8.encode(anime.imageUrl!))}'
                                    : anime.imageUrl!,
                                fit: BoxFit.cover,
                              )
                            : const Icon(
                                Ionicons.image,
                                color: Colors.white,
                                size: 32,
                              ),
                      ),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // 内容区域 - 右侧
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 标题
                          Text(
                            anime.animeTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          
                          // 类型描述
                          if (anime.typeDescription != null)
                            Text(
                              anime.typeDescription!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          
                          // 评分和集数
                          Row(
                            children: [
                              Icon(
                                Ionicons.star,
                                size: 16,
                                color: Colors.yellow[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                anime.rating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                '${anime.episodeCount} 集',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // 箭头图标
                    const Icon(
                      Ionicons.chevron_forward,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 添加加载更多指示器
    if (isLoadingMore) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    // 添加加载更多按钮（如果还有更多内容且当前没在加载）
    if (!isLoadingMore && results.length < totalResults) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Center(
            child: ElevatedButton(
              onPressed: _loadMoreTextResults,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.2),
                foregroundColor: Colors.white,
                elevation: 0,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('加载更多 (还有${totalResults - results.length}个结果)'),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildAdvancedSearchTab() {
    if (_isLoadingConfig) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    if (_searchConfig == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Ionicons.warning, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            const Text(
              '加载搜索配置失败',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSearchConfig,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 关键词搜索
          _buildAdvancedSearchSection(
            '关键词',
            TextField(
              controller: _keywordController,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _performAdvancedSearch(),
              decoration: InputDecoration(
                hintText: '输入作品标题关键词',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white),
                ),
              ),
            ),
          ),

          // 评分范围
          _buildAdvancedSearchSection(
            '评分范围 (${_minRating.round()} - ${_maxRating.round()})',
            RangeSlider(
              values: RangeValues(_minRating, _maxRating),
              min: 0,
              max: 10,
              divisions: 10,
              labels:
                  RangeLabels('${_minRating.round()}', '${_maxRating.round()}'),
              onChanged: (values) {
                setState(() {
                  _minRating = values.start;
                  _maxRating = values.end;
                });
              },
              activeColor: Colors.white,
              inactiveColor: Colors.white.withOpacity(0.3),
            ),
          ),

          // 年份选择 - 一行布局，使用毛玻璃样式
          if (_searchConfig != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    // 左边的标签
                    const Text(
                      '年份',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // 右边的下拉菜单
                    BlurDropdown<int?>(
                      dropdownKey: _yearDropdownKey,
                      items: [
                        DropdownMenuItemData<int?>(
                          title: '全部年份',
                          value: null,
                          isSelected: _selectedYear == null,
                        ),
                        ...List.generate(
                          _searchConfig!.maxYear - _searchConfig!.minYear + 1,
                          (index) => _searchConfig!.maxYear - index,
                        ).map((year) => DropdownMenuItemData<int?>(
                              title: '$year',
                              value: year,
                              isSelected: _selectedYear == year,
                            )),
                      ],
                      onItemSelected: (value) {
                        setState(() {
                          _selectedYear = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

          // 搜索按钮
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isAdvancedSearching ? null : _performAdvancedSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.2),
                foregroundColor: Colors.white,
                elevation: 0, // 去掉阴影
                shadowColor: Colors.transparent, // 确保阴影完全透明
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isAdvancedSearching
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('开始搜索', style: TextStyle(fontSize: 16)),
            ),
          ),

          const SizedBox(height: 16),

          // 搜索结果
          SizedBox(
            height: 400, // 固定高度避免布局问题
            child: _buildSearchResults(
                _displayedAdvancedResults,
                _isAdvancedSearching,
                _advancedScrollController,
                _isLoadingMoreAdvanced,
                _advancedSearchResults.length),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSearchSection(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(List<SearchResultAnime> results, bool isLoading,
      ScrollController scrollController, bool isLoadingMore, int totalResults) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Ionicons.search,
              size: 64,
              color: Colors.white.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无搜索结果',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: results.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // 如果是加载指示器
        if (index >= results.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          );
        }

        final anime = results[index];
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Card(
            color: Colors.white.withOpacity(0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () => _openAnimeDetail(anime.animeId),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 120, // 固定卡片高度
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 封面图片 - 左侧
                    Container(
                      width: 80, // 固定宽度
                      height: double.infinity, // 顶满高度
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white.withOpacity(0.1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: anime.imageUrl != null
                            ? CachedNetworkImageWidget(
                                imageUrl: kIsWeb
                                    ? '/api/image_proxy?url=${base64Url.encode(utf8.encode(anime.imageUrl!))}'
                                    : anime.imageUrl!,
                                fit: BoxFit.cover,
                              )
                            : const Icon(
                                Ionicons.image,
                                color: Colors.white,
                                size: 32,
                              ),
                      ),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // 内容区域 - 右侧
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 标题
                          Text(
                            anime.animeTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          
                          // 类型描述
                          if (anime.typeDescription != null)
                            Text(
                              anime.typeDescription!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          
                          // 评分和集数
                          Row(
                            children: [
                              Icon(
                                Ionicons.star,
                                size: 16,
                                color: Colors.yellow[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                anime.rating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                '${anime.episodeCount} 集',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // 箭头图标
                    const Icon(
                      Ionicons.chevron_forward,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 高级搜索滚动监听
  void _onAdvancedScroll() {
    if (_advancedScrollController.position.pixels >=
        _advancedScrollController.position.maxScrollExtent - 200) {
      _loadMoreAdvancedResults();
    }
  }

  // 加载更多文本搜索结果
  void _loadMoreTextResults() {
    if (_isLoadingMoreText ||
        _currentTextPage * _pageSize >= _textSearchResults.length) {
      return;
    }

    setState(() {
      _isLoadingMoreText = true;
    });

    // 模拟异步加载
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _currentTextPage++;
          final startIndex = (_currentTextPage - 1) * _pageSize;
          final endIndex = (_currentTextPage * _pageSize)
              .clamp(0, _textSearchResults.length);
          _displayedTextResults
              .addAll(_textSearchResults.sublist(startIndex, endIndex));
          _isLoadingMoreText = false;
        });
      }
    });
  }

  // 加载更多高级搜索结果
  void _loadMoreAdvancedResults() {
    if (_isLoadingMoreAdvanced ||
        _currentAdvancedPage * _pageSize >= _advancedSearchResults.length) {
      return;
    }

    setState(() {
      _isLoadingMoreAdvanced = true;
    });

    // 模拟异步加载
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _currentAdvancedPage++;
          final startIndex = (_currentAdvancedPage - 1) * _pageSize;
          final endIndex = (_currentAdvancedPage * _pageSize)
              .clamp(0, _advancedSearchResults.length);
          _displayedAdvancedResults
              .addAll(_advancedSearchResults.sublist(startIndex, endIndex));
          _isLoadingMoreAdvanced = false;
        });
      }
    });
  }
}
