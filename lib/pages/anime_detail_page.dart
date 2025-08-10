import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/widgets/nipaplay_theme/cached_network_image_widget.dart';
// import 'package:nipaplay/widgets/nipaplay_theme/translation_button.dart'; // Removed
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
// import 'dart:convert'; // No longer needed for local translation state
// import 'package:http/http.dart' as http; // No longer needed for local translation state
import 'package:nipaplay/services/dandanplay_service.dart'; // 重新添加DandanplayService导入
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart'; // Added for blur snackbar
import 'package:provider/provider.dart'; // 重新添加
// import 'package:nipaplay/utils/video_player_state.dart'; // Removed from here
import 'dart:io'; // Added for File operations
// import 'package:nipaplay/utils/tab_change_notifier.dart'; // Removed from here
import '../providers/appearance_settings_provider.dart'; // 添加外观设置Provider
import 'package:nipaplay/widgets/nipaplay_theme/switchable_view.dart'; // 添加SwitchableView组件
import 'package:nipaplay/widgets/nipaplay_theme/tag_search_widget.dart'; // 添加标签搜索组件
import 'package:nipaplay/widgets/nipaplay_theme/rating_dialog.dart'; // 添加评分对话框
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:nipaplay/pages/fluent_anime_detail_page.dart';

class AnimeDetailPage extends StatefulWidget {
  final int animeId;

  const AnimeDetailPage({super.key, required this.animeId});

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
  
  static void popIfOpen() {
    if (_AnimeDetailPageState._openPageContext != null && _AnimeDetailPageState._openPageContext!.mounted) {
      Navigator.of(_AnimeDetailPageState._openPageContext!).pop();
      _AnimeDetailPageState._openPageContext = null;
    }
  }
  
  static Future<WatchHistoryItem?> show(BuildContext context, int animeId) {
    // 检查当前UI主题，自动选择适合的版本
    final uiThemeProvider = Provider.of<UIThemeProvider>(context, listen: false);
    
    if (uiThemeProvider.isFluentUITheme) {
      // 使用 Fluent UI 版本
      return fluent.showDialog<WatchHistoryItem>(
        context: context,
        barrierDismissible: true,
        builder: (context) => FluentAnimeDetailPage(animeId: animeId),
      );
    } else {
      // 使用 Material 版本（保持原有逻辑）
      return _showMaterialDialog(context, animeId);
    }
  }
  
  static Future<WatchHistoryItem?> _showMaterialDialog(BuildContext context, int animeId) {
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
        return AnimeDetailPage(animeId: animeId);
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

class _AnimeDetailPageState extends State<AnimeDetailPage>
    with SingleTickerProviderStateMixin {
  static BuildContext? _openPageContext;
  final BangumiService _bangumiService = BangumiService.instance;
  BangumiAnime? _detailedAnime;
  bool _isLoading = true;
  String? _error;
  TabController? _tabController;
  // 添加外观设置
  AppearanceSettingsProvider? _appearanceSettings;
  
  // 弹弹play观看状态相关
  Map<int, bool> _dandanplayWatchStatus = {}; // 存储弹弹play的观看状态
  bool _isLoadingDandanplayStatus = false; // 是否正在加载弹弹play状态
  
  // 弹弹play收藏状态相关
  bool _isFavorited = false; // 是否已收藏
  bool _isLoadingFavoriteStatus = false; // 是否正在加载收藏状态
  bool _isTogglingFavorite = false; // 是否正在切换收藏状态

  // 弹弹play用户评分相关
  int _userRating = 0; // 用户评分（0-10，0代表未评分）
  bool _isLoadingUserRating = false; // 是否正在加载用户评分
  bool _isSubmittingRating = false; // 是否正在提交评分

  // 新增：评分到评价文本的映射
  static const Map<int, String> _ratingEvaluationMap = {
    1: '不忍直视',
    2: '很差',
    3: '差',
    4: '较差',
    5: '不过不失',
    6: '还行',
    7: '推荐',
    8: '力荐',
    9: '神作',
    10: '超神作',
  };

  @override
  void initState() {
    super.initState();
    _openPageContext = context;
    _tabController = TabController(length: 2, vsync: this);
    
    // 添加TabController监听
    _tabController!.addListener(_handleTabChange);
    
    // 启动时异步清理过期缓存
    _bangumiService.cleanExpiredDetailCache().then((_) {
      debugPrint("[番剧详情] 已清理过期的番剧详情缓存");
    });
    _fetchAnimeDetails();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 获取外观设置provider
    _appearanceSettings = Provider.of<AppearanceSettingsProvider>(context, listen: false);
  }

  @override
  void dispose() {
    if (_openPageContext == context) {
      _openPageContext = null;
    }
    _tabController?.removeListener(_handleTabChange);
    _tabController?.dispose();
    super.dispose();
  }
  
  // 处理标签切换
  void _handleTabChange() {
    if (_tabController!.indexIsChanging) {
      // 当切换到剧集列表标签（索引1）时，刷新观看状态
      if (_tabController!.index == 1 && _detailedAnime != null && DandanplayService.isLoggedIn) {
        _fetchDandanplayWatchStatus(_detailedAnime!);
      }
      setState(() {
        // 更新UI以显示新的页面
      });
    }
  }

  Future<void> _fetchAnimeDetails() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      BangumiAnime anime;

      if (kIsWeb) {
        // Web environment: fetch from local API
        try {
          final response = await http.get(Uri.parse('/api/bangumi/detail/${widget.animeId}'));
          if (response.statusCode == 200) {
            final data = json.decode(utf8.decode(response.bodyBytes));
            anime = BangumiAnime.fromJson(data as Map<String, dynamic>);
          } else {
            throw Exception('Failed to load details from API: ${response.statusCode}');
          }
        } catch (e) {
          throw Exception('Failed to connect to the local details API: $e');
        }
      } else {
        // Mobile/Desktop environment: fetch from service
        anime = await BangumiService.instance.getAnimeDetails(widget.animeId);
      }
      
      if (mounted) {
        setState(() {
          _detailedAnime = anime;
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

  // 获取弹弹play观看状态
  Future<void> _fetchDandanplayWatchStatus(BangumiAnime anime) async {
    // 如果未登录弹弹play或没有剧集信息，跳过
    if (!DandanplayService.isLoggedIn || anime.episodeList == null || anime.episodeList!.isEmpty) {
      return;
    }
    
    setState(() {
      _isLoadingDandanplayStatus = true;
      _isLoadingFavoriteStatus = true;
      _isLoadingUserRating = true;
    });
    
    try {
      // 提取所有剧集的episodeId（使用id属性）
      final List<int> episodeIds = anime.episodeList!
          .where((episode) => episode.id > 0) // 确保id有效
          .map((episode) => episode.id)
          .toList();
      
      // 并行获取观看状态、收藏状态和用户评分
      final Future<Map<int, bool>> watchStatusFuture = episodeIds.isNotEmpty 
          ? DandanplayService.getEpisodesWatchStatus(episodeIds)
          : Future.value(<int, bool>{});
          
      final Future<bool> favoriteStatusFuture = DandanplayService.isAnimeFavorited(anime.id);
      final Future<int> userRatingFuture = DandanplayService.getUserRatingForAnime(anime.id);
      
      final results = await Future.wait([watchStatusFuture, favoriteStatusFuture, userRatingFuture]);
      final watchStatus = results[0] as Map<int, bool>;
      final isFavorited = results[1] as bool;
      final userRating = results[2] as int;
      
      if (mounted) {
        setState(() {
          _dandanplayWatchStatus = watchStatus;
          _isFavorited = isFavorited;
          _userRating = userRating;
          _isLoadingDandanplayStatus = false;
          _isLoadingFavoriteStatus = false;
          _isLoadingUserRating = false;
        });
      }
    } catch (e) {
      debugPrint('[番剧详情] 获取弹弹play状态失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingDandanplayStatus = false;
          _isLoadingFavoriteStatus = false;
          _isLoadingUserRating = false;
        });
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) return '${parts[0]}年${parts[1]}月${parts[2]}日';
      return dateStr;
    } catch (e) {
      return dateStr;
    }
  }

  static const Map<int, String> _weekdays = {
    0: '周日',
    1: '周一',
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    -1: '未知',
  };

  // 新增：构建星星评分的 Widget
  Widget _buildRatingStars(double? rating) {
    if (rating == null || rating < 0 || rating > 10) {
      return Text('N/A',
          style:
              TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13));
    }

    List<Widget> stars = [];
    int fullStars = rating.floor();
    bool halfStar = (rating - fullStars) >= 0.5;

    for (int i = 0; i < 10; i++) {
      if (i < fullStars) {
        stars.add(Icon(Ionicons.star, color: Colors.yellow[600], size: 16));
      } else if (i == fullStars && halfStar) {
        stars
            .add(Icon(Ionicons.star_half, color: Colors.yellow[600], size: 16));
      } else {
        stars.add(Icon(Ionicons.star_outline,
            color: Colors.yellow[600]?.withOpacity(0.7), size: 16));
      }
      if (i < 9) {
        stars.add(const SizedBox(width: 1)); // 星星之间的小间距
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }

  Widget _buildSummaryView(BangumiAnime anime) {
    final String summaryText = anime.summary ?? '暂无简介';
    final airWeekday = anime.airWeekday;
    final String weekdayString =
        airWeekday != null && _weekdays.containsKey(airWeekday)
            ? _weekdays[airWeekday]!
            : '待定';
    
    // -- 开始修改 --
    String coverImageUrl = anime.imageUrl;
    if (kIsWeb) {
      final encodedUrl = base64Url.encode(utf8.encode(anime.imageUrl));
      coverImageUrl = '/api/image_proxy?url=$encodedUrl';
    }
    // -- 结束修改 --

    final bangumiRatingValue = anime.ratingDetails?['Bangumi评分'];
    String bangumiEvaluationText = '';
    if (bangumiRatingValue is num &&
        _ratingEvaluationMap.containsKey(bangumiRatingValue.round())) {
      bangumiEvaluationText =
          '(${_ratingEvaluationMap[bangumiRatingValue.round()]!})';
    }

    final valueStyle = TextStyle(
        color: Colors.white.withOpacity(0.85), fontSize: 13, height: 1.5);
    const boldWhiteKeyStyle = TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 13,
        height: 1.5);
    final sectionTitleStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold);

    List<Widget> metadataWidgets = [];
    if (anime.metadata != null && anime.metadata!.isNotEmpty) {
      metadataWidgets.add(const SizedBox(height: 8));
      metadataWidgets.add(Text('制作信息:', style: sectionTitleStyle));
      for (String item in anime.metadata!) {
        if (item.trim().startsWith('别名:') || item.trim().startsWith('别名：')) {
          continue;
        }
        var parts = item.split(RegExp(r'[:：]'));
        if (parts.length == 2) {
          metadataWidgets.add(Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: RichText(
                  text: TextSpan(
                      style: valueStyle.copyWith(height: 1.3),
                      children: [
                    TextSpan(
                        text: '${parts[0].trim()}: ',
                        style: boldWhiteKeyStyle.copyWith(
                            fontWeight: FontWeight.w600)),
                    TextSpan(text: parts[1].trim())
                  ]))));
        } else {
          metadataWidgets
              .add(Text(item, style: valueStyle.copyWith(height: 1.3)));
        }
      }
    }

    List<Widget> titlesWidgets = [];
    if (anime.titles != null && anime.titles!.isNotEmpty) {
      titlesWidgets.add(const SizedBox(height: 8));
      titlesWidgets.add(Text('其他标题:', style: sectionTitleStyle));
      titlesWidgets.add(const SizedBox(height: 4));
      TextStyle aliasTextStyle =
          TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12);
      for (var titleEntry in anime.titles!) {
        String titleText = titleEntry['title'] ?? '未知标题';
        String languageText = '';
        if (titleEntry['language'] != null &&
            titleEntry['language']!.isNotEmpty) {
          languageText = ' (${titleEntry['language']})';
        }
        titlesWidgets.add(Padding(
            padding: const EdgeInsets.only(top: 3.0, left: 8.0),
            child: Text(
              '$titleText$languageText',
              style: aliasTextStyle,
            )));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (anime.name != anime.nameCn)
            Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(anime.name,
                    style: valueStyle.copyWith(
                        fontSize: 14, fontStyle: FontStyle.italic))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (anime.imageUrl.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(right: 16.0, bottom: 8.0),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImageWidget(
                          imageUrl: coverImageUrl, // 使用处理后的URL
                          width: 130,
                          height: 195,
                          fit: BoxFit.cover))),
            Expanded(
              child: SizedBox(
                height: 195,
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(summaryText, style: valueStyle),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          if (bangumiRatingValue is num && bangumiRatingValue > 0) ...[
            RichText(
                text: TextSpan(children: [
              const TextSpan(text: 'Bangumi评分: ', style: boldWhiteKeyStyle),
              WidgetSpan(
                  child: _buildRatingStars(bangumiRatingValue.toDouble())),
              TextSpan(
                  text: ' ${bangumiRatingValue.toStringAsFixed(1)} ',
                  style: TextStyle(
                      color: Colors.yellow[600],
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              TextSpan(
                  text: bangumiEvaluationText,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 12))
            ])),
            const SizedBox(height: 6),
          ],
          
          // 弹弹play用户评分区域（仅在登录时显示）
          if (DandanplayService.isLoggedIn) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 我的打分显示
                if (_userRating > 0) ...[
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(text: '我的打分: ', style: boldWhiteKeyStyle.copyWith(color: Colors.blue)),
                      TextSpan(
                        text: '$_userRating 分 ',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      TextSpan(
                        text: '(${_ratingEvaluationMap[_userRating] ?? ''})',
                        style: TextStyle(
                          color: Colors.blue.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                ],
                
                // 我要打分按钮
                GestureDetector(
                  onTap: _isSubmittingRating ? null : _showRatingDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      border: Border.all(
                        color: Colors.blue.withOpacity(0.6),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isLoadingUserRating || _isSubmittingRating) ...[
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ] else
                          Icon(
                            _userRating > 0 ? Ionicons.star : Ionicons.star_outline,
                            color: Colors.blue,
                            size: 14,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          _userRating > 0 ? '修改评分' : '我要打分',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          if (anime.ratingDetails != null &&
              anime.ratingDetails!.entries.any((entry) =>
                  entry.key != 'Bangumi评分' &&
                  entry.value is num &&
                  (entry.value as num) > 0))
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0, top: 2.0),
                child: Wrap(
                    spacing: 12.0,
                    runSpacing: 4.0,
                    children: anime.ratingDetails!.entries
                        .where((entry) =>
                            entry.key != 'Bangumi评分' &&
                            entry.value is num &&
                            (entry.value as num) > 0)
                        .map((entry) {
                      String siteName = entry.key;
                      if (siteName.endsWith('评分')) {
                        siteName = siteName.substring(0, siteName.length - 2);
                      }
                      final score = entry.value as num;
                      return RichText(
                          text: TextSpan(
                              style: valueStyle.copyWith(fontSize: 12),
                              children: [
                            TextSpan(
                                text: '$siteName: ',
                                style: boldWhiteKeyStyle.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal)),
                            TextSpan(
                                text: score.toStringAsFixed(1),
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.95)))
                          ]));
                    }).toList())),
          Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: RichText(
                  text: TextSpan(style: valueStyle, children: [
                const TextSpan(text: '开播: ', style: boldWhiteKeyStyle),
                TextSpan(text: '${_formatDate(anime.airDate)} ($weekdayString)')
              ]))),
          if (anime.typeDescription != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  const TextSpan(text: '类型: ', style: boldWhiteKeyStyle),
                  TextSpan(text: anime.typeDescription)
                ]))),
          if (anime.totalEpisodes != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  const TextSpan(text: '话数: ', style: boldWhiteKeyStyle),
                  TextSpan(text: '${anime.totalEpisodes}话')
                ]))),
          if (anime.isOnAir != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  const TextSpan(text: '状态: ', style: boldWhiteKeyStyle),
                  TextSpan(text: anime.isOnAir! ? '连载中' : '已完结')
                ]))),
          Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: RichText(
                  text: TextSpan(style: valueStyle, children: [
                TextSpan(
                    text: '追番状态: ',
                    style:
                        boldWhiteKeyStyle.copyWith(color: Colors.orangeAccent)),
                TextSpan(
                    text: anime.isFavorited! ? '已追' : '未追',
                    style:
                        TextStyle(color: Colors.orangeAccent.withOpacity(0.85)))
              ]))),
          if (anime.isNSFW ?? false)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  TextSpan(
                      text: '限制内容: ',
                      style:
                          boldWhiteKeyStyle.copyWith(color: Colors.redAccent)),
                  TextSpan(
                      text: '是',
                      style:
                          TextStyle(color: Colors.redAccent.withOpacity(0.85)))
                ]))),
          ...metadataWidgets,
          ...titlesWidgets,
          if (anime.tags != null && anime.tags!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('标签:', style: sectionTitleStyle),
                IconButton(
                  onPressed: () => _openTagSearch(),
                  icon: const Icon(
                    Ionicons.search,
                    color: Colors.white70,
                    size: 20,
                  ),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: anime.tags!
                    .map((tag) => _HoverableTag(
                          tag: tag,
                          onTap: () => _searchByTag(tag),
                        ))
                    .toList())
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEpisodesListView(BangumiAnime anime) {
    if (anime.episodeList == null || anime.episodeList!.isEmpty) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Text('暂无剧集信息', style: TextStyle(color: Colors.white70)),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      itemCount: anime.episodeList!.length,
      itemBuilder: (context, index) {
        final episode = anime.episodeList![index];

        return FutureBuilder<WatchHistoryItem?>(
          future:
              WatchHistoryManager.getHistoryItemByEpisode(anime.id, episode.id),
          builder: (context, historySnapshot) {
            Widget leadingIcon =
                const SizedBox(width: 20); // Default empty space
            String? progressText;
            Color? tileColor;
            Color iconColor =
                Colors.orangeAccent.withOpacity(0.8); // Default for playing
            double progress = 0.0;

            if (historySnapshot.connectionState == ConnectionState.done) {
              if (historySnapshot.hasData && historySnapshot.data != null) {
                final historyItem = historySnapshot.data!;
                progress = historyItem.watchProgress;
                if (progress > 0.95) {
                  // Watched
                  leadingIcon = Icon(Ionicons.checkmark_circle,
                      color: Colors.greenAccent.withOpacity(0.8), size: 16);
                  tileColor = Colors.white.withOpacity(0.03);
                  progressText = '已看完';
                } else if (progress > 0.01) {
                  // Watching
                  leadingIcon = Icon(Ionicons.play_circle_outline,
                      color: iconColor, size: 16);
                  progressText = '${(progress * 100).toStringAsFixed(0)}%';
                } else if (historyItem.isFromScan) {
                  // Scanned but not (really) watched
                  leadingIcon = Icon(Ionicons.play_circle_outline,
                      color: Colors.greenAccent.withOpacity(0.8), size: 16);
                  progressText = '未播放';
                } else {
                  // Exists in history, 0 progress, not from scan - unlikely state, treat as not found or specific icon?
                  // For now, let it fall through to the "Not Found in History" case or define a specific state.
                  // To treat as not found for icon/text:
                  leadingIcon = const Icon(Ionicons.play_circle_outline,
                      color: Colors.white38, size: 16);
                  progressText = '未找到';
                }
              } else {
                // No data in snapshot, even if connection is done (means not found in WatchHistoryManager)
                leadingIcon = const Icon(Ionicons.play_circle_outline,
                    color: Colors.white38, size: 16); // Grey play icon
                progressText = '未找到'; // Text indicating "Not Found"
              }
            }
            // Optional: Show a loading indicator while waiting for history data
            // else if (historySnapshot.connectionState == ConnectionState.waiting) {
            //   leadingIcon = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
            // }

            return Material(
              color: tileColor ?? Colors.transparent,
              child: ListTile(
                dense: true,
                leading: leadingIcon,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(episode.title,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.9), fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    // 显示弹弹play观看状态标注
                    if (DandanplayService.isLoggedIn && _dandanplayWatchStatus.containsKey(episode.id))
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _dandanplayWatchStatus[episode.id] == true 
                              ? Colors.green.withOpacity(0.2)
                              : Colors.transparent,
                          border: Border.all(
                            color: _dandanplayWatchStatus[episode.id] == true 
                                ? Colors.green.withOpacity(0.6)
                                : Colors.transparent,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _dandanplayWatchStatus[episode.id] == true ? '已看' : '',
                          style: TextStyle(
                            color: Colors.green.withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                trailing: progressText != null
                    ? Text(progressText,
                        style: TextStyle(
                            color: progress > 0.95
                                ? Colors.greenAccent
                                    .withOpacity(0.9) // Green for "已看完"
                                : (progress > 0.01
                                    ? Colors.orangeAccent
                                    : (progressText == '未播放'
                                        ? Colors.greenAccent.withOpacity(0.9)
                                        : Colors
                                            .white54)), // Grey for "未找到" or other 0-progress cases
                            fontSize: 11))
                    : null,
                onTap: () async {
                  final WatchHistoryItem? historyItemToPlay;
                  if (historySnapshot.connectionState == ConnectionState.done &&
                      historySnapshot.data != null) {
                    historyItemToPlay = historySnapshot.data!;
                  } else {
                    BlurSnackBar.show(context, '媒体库中找不到此剧集的视频文件');
                    return;
                  }

                  if (historyItemToPlay.filePath.isNotEmpty) {
                    final file = File(historyItemToPlay.filePath);
                    if (await file.exists()) {
                      // ** NEW LOGIC **
                      // 使用 PlaybackService 播放
                      final playableItem = PlayableItem(
                        videoPath: historyItemToPlay.filePath,
                        title: anime.nameCn,
                        subtitle: episode.title,
                        animeId: anime.id,
                        episodeId: episode.id,
                        historyItem: historyItemToPlay,
                      );
                      await PlaybackService().play(playableItem);

                      // 关闭详情页
                      if (mounted) Navigator.pop(context);
                    } else {
                      BlurSnackBar.show(
                          context, '文件已不存在于: ${historyItemToPlay.filePath}');
                    }
                  } else {
                    BlurSnackBar.show(context, '该剧集记录缺少文件路径');
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null || _detailedAnime == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载详情失败:',
                  style: TextStyle(color: Colors.white.withOpacity(0.8))),
              const SizedBox(height: 8),
              Text(
                _error ?? '未知错误',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2)),
                onPressed: _fetchAnimeDetails,
                child: const Text('重试', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child:
                    const Text('关闭', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
    }

    final anime = _detailedAnime!;
    // 获取是否启用页面切换动画
    final enableAnimation = _appearanceSettings?.enablePageAnimation ?? false;
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: 
              Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  anime.nameCn,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              // 收藏按钮（仅当登录弹弹play时显示）
              if (DandanplayService.isLoggedIn) ...[
                IconButton(
                  icon: _isTogglingFavorite
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        )
                      : Icon(
                          _isFavorited ? Ionicons.heart : Ionicons.heart_outline,
                          color: _isFavorited ? Colors.red : Colors.white70,
                          size: 24,
                        ),
                  onPressed: _isTogglingFavorite ? null : _toggleFavorite,
                ),
              ],
              
              IconButton(
                icon: const Icon(Ionicons.close_circle_outline,
                    color: Colors.white70, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          dividerColor: const Color.fromARGB(59, 255, 255, 255),
          dividerHeight: 3.0,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.only(top: 46, left: 15, right: 15),
          indicator: BoxDecoration(
            color: Colors.greenAccent, // 设置指示器的颜色

            borderRadius: BorderRadius.circular(30), // 设置圆角矩形的圆角半径
          ),
          indicatorWeight: 3,
          tabs: const [
            Tab(text: '简介'),
            Tab(text: '剧集'),
          ],
        ),
        Expanded(
          child: SwitchableView(
            enableAnimation: enableAnimation, // 使用外观设置的动画开关
            currentIndex: _tabController?.index ?? 0,
            physics: enableAnimation 
                ? const PageScrollPhysics() // 开启动画时使用页面滑动物理效果
                : const NeverScrollableScrollPhysics(), // 关闭动画时禁止滑动
            onPageChanged: (index) {
              if ((_tabController?.index ?? 0) != index) {
                _tabController?.animateTo(index);
              }
            },
            children: [
              // 使用RepaintBoundary隔离绘制边界，减少重绘范围
              RepaintBoundary(child: _buildSummaryView(anime)),
              RepaintBoundary(child: _buildEpisodesListView(anime)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool enableBlur = _appearanceSettings?.enableWidgetBlurEffect ?? true;
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.3),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
            20, MediaQuery.of(context).padding.top + 20, 20, 20),
        child: GlassmorphicContainer(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 15,
          blur: enableBlur ? 25 : 0,
          alignment: Alignment.center,
          border: 0.5,
          linearGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color.fromARGB(255, 219, 219, 219).withOpacity(0.2),
              const Color.fromARGB(255, 208, 208, 208).withOpacity(0.2),
            ],
            stops: const [0.1, 1],
          ),
          borderGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.15),
              Colors.white.withOpacity(0.15),
            ],
          ),
          child: _buildContent(),
        ),
      ),
    );
  }

  // 打开标签搜索页面
  void _openTagSearch() {
    // 获取当前番剧的标签列表
    final currentTags = _detailedAnime?.tags ?? [];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => TagSearchModal(
        preselectedTags: currentTags,
        onBeforeOpenAnimeDetail: () {
          // 关闭当前的番剧详情页面
          Navigator.of(context).pop();
        },
      ),
    );
  }

  // 通过单个标签搜索
  void _searchByTag(String tag) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => TagSearchModal(
        prefilledTag: tag,
        onBeforeOpenAnimeDetail: () {
          // 关闭当前的番剧详情页面
          Navigator.of(context).pop();
        },
      ),
    );
  }

  // 切换收藏状态
  Future<void> _toggleFavorite() async {
    if (!DandanplayService.isLoggedIn) {
      _showBlurSnackBar(context, '请先登录弹弹play账号');
      return;
    }

    if (_detailedAnime == null || _isTogglingFavorite) {
      return;
    }

    setState(() {
      _isTogglingFavorite = true;
    });

    try {
      if (_isFavorited) {
        // 取消收藏
        await DandanplayService.removeFavorite(_detailedAnime!.id);
        _showBlurSnackBar(context, '已取消收藏');
      } else {
        // 添加收藏
        await DandanplayService.addFavorite(
          animeId: _detailedAnime!.id,
          favoriteStatus: 'favorited',
        );
        _showBlurSnackBar(context, '已添加到收藏');
      }

      // 更新本地状态
      setState(() {
        _isFavorited = !_isFavorited;
      });
    } catch (e) {
      debugPrint('[番剧详情] 切换收藏状态失败: $e');
      _showBlurSnackBar(context, '操作失败: ${e.toString()}');
    } finally {
      setState(() {
        _isTogglingFavorite = false;
      });
    }
  }

  // 显示模糊Snackbar
  void _showBlurSnackBar(BuildContext context, String message) {
    BlurSnackBar.show(context, message);
  }

  // 显示评分对话框
  void _showRatingDialog() {
    if (_detailedAnime == null) return;
    
    RatingDialog.show(
      context: context,
      animeTitle: _detailedAnime!.nameCn,
      initialRating: _userRating,
      onRatingSubmitted: _handleRatingSubmitted,
    );
  }

  // 处理评分提交
  Future<void> _handleRatingSubmitted(int rating) async {
    if (_detailedAnime == null) return;
    
    setState(() {
      _isSubmittingRating = true;
    });

    try {
      await DandanplayService.submitUserRating(
        animeId: _detailedAnime!.id,
        rating: rating,
      );
      
      if (mounted) {
        setState(() {
          _userRating = rating;
          _isSubmittingRating = false;
        });
        _showBlurSnackBar(context, '评分提交成功');
      }
    } catch (e) {
      debugPrint('[番剧详情] 提交评分失败: $e');
      if (mounted) {
        setState(() {
          _isSubmittingRating = false;
        });
        _showBlurSnackBar(context, '评分提交失败: ${e.toString()}');
      }
    }
  }
}

// 可悬浮的标签widget
class _HoverableTag extends StatefulWidget {
  final String tag;
  final VoidCallback onTap;

  const _HoverableTag({
    required this.tag,
    required this.onTap,
  });

  @override
  State<_HoverableTag> createState() => _HoverableTagState();
}

class _HoverableTagState extends State<_HoverableTag> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context, listen: false);
    final bool enableBlur = appearanceSettings.enableWidgetBlurEffect;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: IntrinsicWidth(
            child: IntrinsicHeight(
              child: GlassmorphicContainer(
                width: double.infinity,
                height: double.infinity,
                borderRadius: 20,
                blur: enableBlur ? 20 : 0,
                alignment: Alignment.center,
                border: 1,
                linearGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isHovered 
                      ? [
                          Colors.white.withOpacity(0.25),
                          Colors.white.withOpacity(0.15),
                        ]
                      : [
                          Colors.white.withOpacity(0.1),
                          Colors.white.withOpacity(0.05),
                        ],
                ),
                borderGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isHovered
                      ? [
                          Colors.white.withOpacity(0.8),
                          Colors.white.withOpacity(0.4),
                        ]
                      : [
                          Colors.white.withOpacity(0.5),
                          Colors.white.withOpacity(0.2),
                        ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    widget.tag,
                    style: TextStyle(
                      fontSize: 12,
                      color: _isHovered 
                          ? Colors.white 
                          : Colors.white.withOpacity(0.9),
                      fontWeight: _isHovered 
                          ? FontWeight.w600 
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
