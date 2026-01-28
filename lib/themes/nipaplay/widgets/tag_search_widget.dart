import 'dart:convert';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/services/search_service.dart';
import 'package:nipaplay/models/search_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:nipaplay/main.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/history_like_list_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';

class _TagSearchStyle {
  const _TagSearchStyle({
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.iconColor,
    required this.cardColor,
    required this.borderColor,
    required this.dividerColor,
    required this.chipColor,
    required this.chipSelectedColor,
    required this.chipBorderColor,
    required this.inputFillColor,
    required this.inputBorderColor,
    required this.inputFocusedBorderColor,
    required this.glassGradientStart,
    required this.glassGradientEnd,
    required this.glassBorderStart,
    required this.glassBorderEnd,
    required this.accentColor,
    required this.buttonColor,
    required this.buttonDisabledColor,
    required this.progressColor,
  });

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color iconColor;
  final Color cardColor;
  final Color borderColor;
  final Color dividerColor;
  final Color chipColor;
  final Color chipSelectedColor;
  final Color chipBorderColor;
  final Color inputFillColor;
  final Color inputBorderColor;
  final Color inputFocusedBorderColor;
  final Color glassGradientStart;
  final Color glassGradientEnd;
  final Color glassBorderStart;
  final Color glassBorderEnd;
  final Color accentColor;
  final Color buttonColor;
  final Color buttonDisabledColor;
  final Color progressColor;

  factory _TagSearchStyle.from(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    const accent = Color(0xFFFF2E55);
    final tintBase = isDark ? Colors.white : Colors.black;

    return _TagSearchStyle(
      textPrimary: onSurface,
      textSecondary: onSurface.withOpacity(0.7),
      textMuted: onSurface.withOpacity(0.5),
      iconColor: onSurface.withOpacity(0.7),
      cardColor: isDark
          ? Colors.white.withOpacity(0.08)
          : Colors.black.withOpacity(0.04),
      borderColor: onSurface.withOpacity(isDark ? 0.2 : 0.12),
      dividerColor: onSurface.withOpacity(isDark ? 0.16 : 0.1),
      chipColor: isDark
          ? Colors.white.withOpacity(0.12)
          : Colors.black.withOpacity(0.05),
      chipSelectedColor: accent.withOpacity(isDark ? 0.25 : 0.18),
      chipBorderColor: onSurface.withOpacity(isDark ? 0.22 : 0.14),
      inputFillColor:
          isDark ? Colors.white.withOpacity(0.08) : Colors.white,
      inputBorderColor: onSurface.withOpacity(isDark ? 0.2 : 0.12),
      inputFocusedBorderColor: accent,
      glassGradientStart:
          tintBase.withOpacity(isDark ? 0.2 : 0.04),
      glassGradientEnd: tintBase.withOpacity(isDark ? 0.12 : 0.02),
      glassBorderStart:
          tintBase.withOpacity(isDark ? 0.35 : 0.12),
      glassBorderEnd:
          tintBase.withOpacity(isDark ? 0.2 : 0.08),
      accentColor: accent,
      buttonColor: accent.withOpacity(isDark ? 0.25 : 0.16),
      buttonDisabledColor: onSurface.withOpacity(isDark ? 0.1 : 0.08),
      progressColor: accent,
    );
  }
}

enum _TagSearchMode {
  none,
  text,
  advanced,
}

class TagSearchModal extends StatefulWidget {
  final String? prefilledTag;
  final List<String>? preselectedTags;
  final VoidCallback? onBeforeOpenAnimeDetail;
  final bool useWindow;

  const TagSearchModal({
    super.key, 
    this.prefilledTag, 
    this.preselectedTags,
    this.onBeforeOpenAnimeDetail,
    this.useWindow = false,
  });

  @override
  State<TagSearchModal> createState() => _TagSearchModalState();

  static Future<void> show(
    BuildContext context, {
    String? prefilledTag,
    List<String>? preselectedTags,
    VoidCallback? onBeforeOpenAnimeDetail,
  }) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    return NipaplayWindow.show<void>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      child: Builder(
        builder: (BuildContext dialogContext) {
          final screenSize = MediaQuery.of(dialogContext).size;
          final maxWidth = (screenSize.width * 0.95).clamp(320.0, 1100.0);

          return NipaplayWindowScaffold(
            maxWidth: maxWidth,
            maxHeightFactor: 0.9,
            onClose: () => Navigator.of(dialogContext).maybePop(),
            child: TagSearchModal(
              prefilledTag: prefilledTag,
              preselectedTags: preselectedTags,
              onBeforeOpenAnimeDetail: onBeforeOpenAnimeDetail,
              useWindow: true,
            ),
          );
        },
      ),
    );
  }
}

class _TagSearchModalState extends State<TagSearchModal> {
  static const double _desktopWidthThreshold = 900;
  static const double _desktopSidebarWidth = 320;

  final SearchService _searchService = SearchService.instance;
  _TagSearchMode _lastSearchMode = _TagSearchMode.none;
  bool _isAddTagHovered = false;

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

    // 只为高级搜索添加滚动监听器
    _advancedScrollController.addListener(_onAdvancedScroll);

    // 如果有预填充标签，直接添加并搜索
    if (widget.prefilledTag != null) {
      _textTags.add(widget.prefilledTag!);
      _performTextSearch();
    }
    // 如果有预选择的标签，不自动添加到搜索标签中，只显示在"当前标签"区域
    else if (widget.preselectedTags != null && widget.preselectedTags!.isNotEmpty) {
      // 仍需要加载搜索配置，以防用户切换到高级搜索
      _loadSearchConfig();
    } else {
      _loadSearchConfig();
    }
  }

  @override
  void dispose() {
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

  bool get _hasAdvancedCriteria {
    final keyword = _keywordController.text.trim();
    final ratingChanged = _minRating > 0 || _maxRating < 10;
    return keyword.isNotEmpty ||
        ratingChanged ||
        _selectedYear != null ||
        _selectedType != null ||
        _selectedTagIds.isNotEmpty;
  }

  Future<void> _performSmartSearch() async {
    if (_isTextSearching || _isAdvancedSearching) return;

    if (_hasAdvancedCriteria) {
      await _performAdvancedSearch();
      return;
    }

    if (_textTags.isNotEmpty) {
      await _performTextSearch();
      return;
    }

    _showErrorSnackBar('请添加标签或设置筛选条件');
  }

  Future<void> _performTextSearch() async {
    if (_textTags.isEmpty) {
      _showErrorSnackBar('请至少添加一个标签');
      return;
    }

    setState(() {
      _lastSearchMode = _TagSearchMode.text;
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
      _lastSearchMode = _TagSearchMode.advanced;
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
      ThemedAnimeDetail.show(context, animeId).then((historyItem) {
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
                  if (mainPageState.globalTabController!.index != 1) {
                    mainPageState.globalTabController!.animateTo(1);
                    debugPrint('[TagSearchWidget] 成功切换到播放页面 (tab 1)');
                  } else {
                    debugPrint('[TagSearchWidget] 已经在播放页面 (tab 1)');
                  }
                } else {
                  debugPrint('[TagSearchWidget] 无法获取MainPageState，尝试备用方案');
                  // 备用方案：使用TabChangeNotifier
                  try {
                    final tabNotifier = Provider.of<TabChangeNotifier>(rootContext, listen: false);
                    tabNotifier.changeTab(1);
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
    final style = _TagSearchStyle.from(context);
    final borderRadius = widget.useWindow
        ? BorderRadius.circular(20)
        : const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          );

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopLayout =
            constraints.maxWidth >= _desktopWidthThreshold;
        const titleText = '搜索';

        return Column(
          children: [
            if (!widget.useWindow)
              // 拖拽指示器
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: style.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            if (widget.useWindow) const SizedBox(height: 12),

            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  titleText,
                  style: TextStyle(
                    color: style.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // 内容区域
            Expanded(
              child: _buildContent(style, isDesktopLayout),
            ),
          ],
        );
      },
    );

    return Container(
      height: widget.useWindow
          ? double.infinity
          : MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: borderRadius,
      ),
      child: widget.useWindow
          ? content
          : GlassmorphicContainer(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 20,
              blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 20 : 0,
              alignment: Alignment.center,
              border: 1,
              linearGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  style.glassGradientStart,
                  style.glassGradientEnd,
                ],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  style.glassBorderStart,
                  style.glassBorderEnd,
                ],
              ),
              child: content,
            ),
    );
  }

  Widget _buildContent(_TagSearchStyle style, bool isDesktopLayout) {
    if (widget.prefilledTag != null) {
      return isDesktopLayout
          ? _buildDesktopPrefilledTagSearch(style)
          : _buildPrefilledTagSearch(style);
    }

    return isDesktopLayout
        ? _buildDesktopCombinedSearch(style)
        : _buildCombinedSearch(style);
  }

  Widget _buildPrefilledTagInfo(_TagSearchStyle style) {
    return _buildPanel(
      style,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Ionicons.pricetag, color: style.iconColor, size: 20),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: style.chipSelectedColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: style.chipBorderColor),
            ),
            child: Text(
              widget.prefilledTag!,
              style: TextStyle(color: style.textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrefilledTagSearch(_TagSearchStyle style) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 显示当前搜索的标签
          _buildPrefilledTagInfo(style),
          const SizedBox(height: 16),

          // 搜索结果标题
          if (_displayedTextResults.isNotEmpty || _isTextSearching) ...[
            Text(
              '搜索结果',
              style: TextStyle(
                color: style.textPrimary,
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
            _textSearchResults.length,
            style,
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedSearch(_TagSearchStyle style) {
    final showHeader = _shouldShowResultsHeader();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCombinedFilters(style),
          const SizedBox(height: 16),

          if (showHeader) ...[
            Text(
              '搜索结果',
              style: TextStyle(
                color: style.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
          ],

          _buildCombinedResultsSection(style),
        ],
      ),
    );
  }

  List<Widget> _buildTextSearchFilterSections(_TagSearchStyle style) {
    final List<Widget> sections = [];

    if (widget.preselectedTags != null && widget.preselectedTags!.isNotEmpty) {
      sections.add(
        _buildPanel(
          style,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前标签 (点击添加到搜索)',
                style: TextStyle(
                  color: style.textPrimary,
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
                                  ? style.chipSelectedColor
                                  : style.chipColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: style.chipBorderColor,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_textTags.contains(tag))
                                  Icon(
                                    Ionicons.checkmark_circle,
                                    color: style.accentColor,
                                    size: 14,
                                  ),
                                if (_textTags.contains(tag))
                                  const SizedBox(width: 4),
                                Text(
                                  tag,
                                  style: TextStyle(
                                    color: style.textPrimary,
                                    fontSize: 12,
                                  ),
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
      );
      sections.add(const SizedBox(height: 16));
    }

    sections.add(
      _buildPanel(
        style,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '添加标签',
              style: TextStyle(
                color: style.textPrimary,
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
                    style: TextStyle(color: style.textPrimary),
                    cursorColor: style.accentColor,
                    decoration: InputDecoration(
                      hintText: '输入标签名称',
                      hintStyle: TextStyle(color: style.textMuted),
                      filled: true,
                      fillColor: style.inputFillColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: style.inputBorderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: style.inputBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: style.inputFocusedBorderColor),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addTextTag(),
                  ),
                ),
                const SizedBox(width: 8),
                MouseRegion(
                  onEnter: (_) => setState(() => _isAddTagHovered = true),
                  onExit: (_) => setState(() => _isAddTagHovered = false),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _addTextTag,
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedScale(
                      scale: _isAddTagHovered ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Ionicons.add_circle,
                          color: style.accentColor,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_textTags.isNotEmpty) ...[
              Text(
                '已添加标签 (用于搜索):',
                style: TextStyle(color: style.textSecondary, fontSize: 14),
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
                              color: style.chipColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: style.chipBorderColor,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tag,
                                  style: TextStyle(
                                    color: style.textPrimary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => _removeTextTag(tag),
                                  child: Icon(
                                    Ionicons.close,
                                    color: style.textSecondary,
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
          ],
        ),
      ),
    );

    return sections;
  }

  Widget _buildPanel(
    _TagSearchStyle style, {
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
    Color? backgroundColor,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? style.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: style.borderColor),
      ),
      child: child,
    );
  }

  Widget _buildDesktopPrefilledTagSearch(_TagSearchStyle style) {
    return Row(
      children: [
        SizedBox(
          width: _desktopSidebarWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
            child: _buildPrefilledTagInfo(style),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: style.dividerColor,
        ),
        Expanded(
          child: _buildTextSearchResultsPanel(style),
        ),
      ],
    );
  }

  Widget _buildDesktopCombinedSearch(_TagSearchStyle style) {
    return Row(
      children: [
        SizedBox(
          width: _desktopSidebarWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
            child: _buildCombinedFilters(style),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: style.dividerColor,
        ),
        Expanded(
          child: _buildCombinedResultsPanel(style),
        ),
      ],
    );
  }

  bool _shouldShowResultsHeader() {
    if (_lastSearchMode == _TagSearchMode.advanced) {
      return _displayedAdvancedResults.isNotEmpty || _isAdvancedSearching;
    }
    return _displayedTextResults.isNotEmpty || _isTextSearching;
  }

  Widget _buildCombinedResultsPanel(_TagSearchStyle style) {
    if (_lastSearchMode == _TagSearchMode.advanced) {
      if (_isLoadingConfig) {
        return _buildLoadingState(style);
      }
      if (_searchConfig == null) {
        return _buildAdvancedSearchError(style);
      }
      return _buildAdvancedResultsPanel(style);
    }
    return _buildTextSearchResultsPanel(style);
  }

  Widget _buildCombinedResultsSection(_TagSearchStyle style) {
    if (_lastSearchMode == _TagSearchMode.advanced) {
      if (_isLoadingConfig) {
        return _buildLoadingState(style);
      }
      if (_searchConfig == null) {
        return _buildAdvancedSearchError(style);
      }
      return SizedBox(
        height: 400,
        child: _buildSearchResults(
          _displayedAdvancedResults,
          _isAdvancedSearching,
          _advancedScrollController,
          _isLoadingMoreAdvanced,
          _advancedSearchResults.length,
          style,
        ),
      );
    }

    return Column(
      children: _buildScrollableSearchResults(
        _displayedTextResults,
        _isTextSearching,
        _isLoadingMoreText,
        _textSearchResults.length,
        style,
      ),
    );
  }

  Widget _buildTextSearchResultsPanel(_TagSearchStyle style) {
    final showHeader = _displayedTextResults.isNotEmpty || _isTextSearching;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Text(
              '搜索结果',
              style: TextStyle(
                color: style.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _buildTextResultsBody(style),
          ),
        ],
      ),
    );
  }

  Widget _buildTextResultsBody(_TagSearchStyle style) {
    if (_isTextSearching && _displayedTextResults.isEmpty) {
      return _buildLoadingState(style);
    }
    if (!_isTextSearching && _displayedTextResults.isEmpty) {
      return _buildEmptyState(style);
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: _buildScrollableSearchResults(
        _displayedTextResults,
        _isTextSearching,
        _isLoadingMoreText,
        _textSearchResults.length,
        style,
      ),
    );
  }

  Widget _buildAdvancedResultsPanel(_TagSearchStyle style) {
    final showHeader =
        _displayedAdvancedResults.isNotEmpty || _isAdvancedSearching;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Text(
              '搜索结果',
              style: TextStyle(
                color: style.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _buildSearchResults(
              _displayedAdvancedResults,
              _isAdvancedSearching,
              _advancedScrollController,
              _isLoadingMoreAdvanced,
              _advancedSearchResults.length,
              style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(_TagSearchStyle style) {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(style.progressColor),
      ),
    );
  }

  Widget _buildEmptyState(_TagSearchStyle style) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Ionicons.search,
            size: 64,
            color: style.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无搜索结果',
            style: TextStyle(
              color: style.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  // 构建可滚动的搜索结果列表
  List<Widget> _buildScrollableSearchResults(
    List<SearchResultAnime> results,
    bool isLoading,
    bool isLoadingMore,
    int totalResults,
    _TagSearchStyle style,
  ) {
    List<Widget> widgets = [];

    if (isLoading && results.isEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(style.progressColor),
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
                  color: style.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无搜索结果',
                  style: TextStyle(
                    color: style.textSecondary,
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
      widgets.add(_buildSearchResultCard(anime, style));
    }

    // 添加加载更多指示器
    if (isLoadingMore) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(style.progressColor),
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
                backgroundColor: style.buttonColor,
                foregroundColor: style.textPrimary,
                disabledBackgroundColor: style.buttonDisabledColor,
                disabledForegroundColor: style.textMuted,
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

  Widget _buildAdvancedSearchError(_TagSearchStyle style) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Ionicons.warning, color: style.textPrimary, size: 48),
          const SizedBox(height: 16),
          Text(
            '加载搜索配置失败',
            style: TextStyle(color: style.textPrimary, fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadSearchConfig,
            style: ElevatedButton.styleFrom(
              backgroundColor: style.buttonColor,
              foregroundColor: style.textPrimary,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSearchFilters(_TagSearchStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 关键词搜索
        _buildAdvancedSearchSection(
          '关键词',
          TextField(
            controller: _keywordController,
            style: TextStyle(color: style.textPrimary),
            onSubmitted: (_) => _performSmartSearch(),
            cursorColor: style.accentColor,
            decoration: InputDecoration(
              hintText: '输入作品标题关键词',
              hintStyle: TextStyle(color: style.textMuted),
              filled: true,
              fillColor: style.inputFillColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: style.inputBorderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: style.inputBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: style.inputFocusedBorderColor),
              ),
            ),
          ),
          style,
        ),

        // 评分范围
        _buildAdvancedSearchSection(
          '评分范围 (${_minRating.round()} - ${_maxRating.round()})',
          Column(
            children: [
              _buildRatingSliderRow(
                label: '最低评分',
                value: _minRating,
                onChanged: (value) {
                  setState(() {
                    _minRating = value;
                    if (_minRating > _maxRating) {
                      _maxRating = _minRating;
                    }
                  });
                },
                style: style,
              ),
              const SizedBox(height: 12),
              _buildRatingSliderRow(
                label: '最高评分',
                value: _maxRating,
                onChanged: (value) {
                  setState(() {
                    _maxRating = value;
                    if (_maxRating < _minRating) {
                      _minRating = _maxRating;
                    }
                  });
                },
                style: style,
              ),
            ],
          ),
          style,
        ),

        // 年份选择 - 一行布局
        if (_searchConfig != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: style.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: style.borderColor),
              ),
              child: Row(
                children: [
                  Text(
                    '年份',
                    style: TextStyle(
                      color: style.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  BlurDropdown<int?>(
                    dropdownKey: _yearDropdownKey,
                    items: [
                      DropdownMenuItemData<int?>(
                        title: '全部年份',
                        value: null,
                        isSelected: _selectedYear == null,
                      ),
                      ...List.generate(
                        _searchConfig!.maxYear -
                            _searchConfig!.minYear +
                            1,
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
      ],
    );
  }

  Widget _buildSearchButton(_TagSearchStyle style) {
    final isSearching = _isTextSearching || _isAdvancedSearching;
    const searchColor = Color(0xFFFF2E55);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isSearching ? null : _performSmartSearch,
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith<Color>(
            (states) {
              if (states.contains(MaterialState.disabled)) {
                return searchColor.withOpacity(0.5);
              }
              return searchColor;
            },
          ),
          foregroundColor: MaterialStateProperty.all<Color>(Colors.white),
          overlayColor: MaterialStateProperty.all<Color>(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          elevation: MaterialStateProperty.all<double>(0),
          shadowColor: MaterialStateProperty.all<Color>(Colors.transparent),
          padding: MaterialStateProperty.all<EdgeInsets>(
            const EdgeInsets.symmetric(vertical: 16),
          ),
          shape: MaterialStateProperty.all<RoundedRectangleBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        child: isSearching
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text('搜索', style: TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _buildCombinedFilters(_TagSearchStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._buildTextSearchFilterSections(style),
        const SizedBox(height: 16),
        _buildAdvancedSearchFilters(style),
        const SizedBox(height: 16),
        _buildSearchButton(style),
      ],
    );
  }

  Widget _buildAdvancedSearchSection(
    String title,
    Widget child,
    _TagSearchStyle style,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: style.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: style.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: style.textPrimary,
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

  Widget _buildRatingSliderRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required _TagSearchStyle style,
  }) {
    const searchColor = Color(0xFFFF2E55);
    final sliderStyle = fluent.SliderThemeData(
      activeColor: fluent.WidgetStatePropertyAll(style.accentColor),
      thumbColor: fluent.WidgetStatePropertyAll(style.accentColor),
      inactiveColor: fluent.WidgetStatePropertyAll(
        style.accentColor.withOpacity(0.25),
      ),
      trackHeight: const fluent.WidgetStatePropertyAll(3.5),
    );
    final fluentTheme = fluent.FluentThemeData(
      brightness: Theme.of(context).brightness,
      accentColor: fluent.ColorExtension(searchColor).toAccentColor(),
      sliderTheme: sliderStyle,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: style.textSecondary,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              value.round().toString(),
              style: TextStyle(
                color: style.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        fluent.FluentTheme(
          data: fluentTheme,
          child: fluent.Slider(
            value: value,
            min: 0,
            max: 10,
            divisions: 10,
            label: value.round().toString(),
            style: sliderStyle,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  String _buildSearchResultSubtitle(SearchResultAnime anime) {
    final parts = <String>[];
    if (anime.typeDescription != null && anime.typeDescription!.isNotEmpty) {
      parts.add(anime.typeDescription!);
    }
    if (anime.rating > 0) {
      parts.add('评分 ${anime.rating.toStringAsFixed(1)}');
    }
    if (anime.episodeCount > 0) {
      parts.add('${anime.episodeCount} 集');
    }
    if (parts.isEmpty) {
      return '暂无简介';
    }
    return parts.join(' · ');
  }

  Widget _buildSearchThumbnail(SearchResultAnime anime, _TagSearchStyle style) {
    final placeholder = Container(
      width: 80,
      height: 45,
      decoration: BoxDecoration(
        color: style.textMuted.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Ionicons.image,
        color: style.textMuted,
        size: 20,
      ),
    );

    if (anime.imageUrl == null || anime.imageUrl!.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 80,
        height: 45,
        child: CachedNetworkImageWidget(
          imageUrl: kIsWeb
              ? '/api/image_proxy?url=${base64Url.encode(utf8.encode(anime.imageUrl!))}'
              : anime.imageUrl!,
          fit: BoxFit.cover,
          loadMode: CachedImageLoadMode.legacy,
          errorBuilder: (context, error) => placeholder,
        ),
      ),
    );
  }

  Widget _buildSearchResultCard(
    SearchResultAnime anime,
    _TagSearchStyle style,
  ) {
    final subtitle = _buildSearchResultSubtitle(anime);
    return HistoryLikeListCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      onTap: () => _openAnimeDetail(anime.animeId),
      child: Row(
        children: [
          _buildSearchThumbnail(anime, style),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  anime.animeTitle,
                  style: TextStyle(
                    color: style.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: style.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(List<SearchResultAnime> results, bool isLoading,
      ScrollController scrollController, bool isLoadingMore, int totalResults,
      _TagSearchStyle style) {
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(style.progressColor),
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
              color: style.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无搜索结果',
              style: TextStyle(
                color: style.textSecondary,
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
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(style.progressColor),
              ),
            ),
          );
        }

        final anime = results[index];
        return _buildSearchResultCard(anime, style);
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
