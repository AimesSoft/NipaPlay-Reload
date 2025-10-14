import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
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
import 'package:nipaplay/widgets/nipaplay_theme/switchable_view.dart'; // 添加SwitchableView组件
import 'package:nipaplay/widgets/nipaplay_theme/tag_search_widget.dart'; // 添加标签搜索组件
import 'package:nipaplay/widgets/nipaplay_theme/rating_dialog.dart'; // 添加评分对话框
import 'package:nipaplay/widgets/nipaplay_theme/bangumi_collection_dialog.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:meta/meta.dart';

class AnimeDetailPage extends StatefulWidget {
  final int animeId;
  final SharedRemoteAnimeSummary? sharedSummary;
  final Future<List<SharedRemoteEpisode>> Function()? sharedEpisodeLoader;
  final PlayableItem Function(SharedRemoteEpisode episode)?
      sharedEpisodeBuilder;
  final String? sharedSourceLabel;

  const AnimeDetailPage({
    super.key,
    required this.animeId,
    this.sharedSummary,
    this.sharedEpisodeLoader,
    this.sharedEpisodeBuilder,
    this.sharedSourceLabel,
  });

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();

  static void popIfOpen() {
    if (_AnimeDetailPageState._openPageContext != null &&
        _AnimeDetailPageState._openPageContext!.mounted) {
      Navigator.of(_AnimeDetailPageState._openPageContext!).pop();
      _AnimeDetailPageState._openPageContext = null;
    }
  }

  static Future<WatchHistoryItem?> show(
    BuildContext context,
    int animeId, {
    SharedRemoteAnimeSummary? sharedSummary,
    Future<List<SharedRemoteEpisode>> Function()? sharedEpisodeLoader,
    PlayableItem Function(SharedRemoteEpisode episode)? sharedEpisodeBuilder,
    String? sharedSourceLabel,
  }) {
    // 获取外观设置Provider
    final appearanceSettings =
        Provider.of<AppearanceSettingsProvider>(context, listen: false);
    final enableAnimation = appearanceSettings.enablePageAnimation;

    return showGeneralDialog<WatchHistoryItem>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierLabel: '关闭详情页',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return AnimeDetailPage(
          animeId: animeId,
          sharedSummary: sharedSummary,
          sharedEpisodeLoader: sharedEpisodeLoader,
          sharedEpisodeBuilder: sharedEpisodeBuilder,
          sharedSourceLabel: sharedSourceLabel,
        );
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
  SharedRemoteAnimeSummary? _sharedSummary;
  String? _sharedSourceLabel;
  Future<List<SharedRemoteEpisode>> Function()? _sharedEpisodeLoader;
  PlayableItem Function(SharedRemoteEpisode episode)? _sharedEpisodeBuilder;
  final Map<int, SharedRemoteEpisode> _sharedEpisodeMap = {};
  final Map<int, PlayableItem> _sharedPlayableMap = {};
  bool _isLoadingSharedEpisodes = false;
  String? _sharedEpisodesError;
  bool _isLoading = true;
  String? _error;
  TabController? _tabController;
  // 添加外观设置
  AppearanceSettingsProvider? _appearanceSettings;

  // 弹弹play观看状态相关
  /// 存储弹弹play的观看状态
  Map<int, bool> _dandanplayWatchStatus = {};

  /// 是否正在加载弹弹play状态
  bool _isLoadingDandanplayStatus = false;

  // 弹弹play收藏状态相关
  /// 是否已收藏
  bool _isFavorited = false;

  /// 是否正在加载收藏状态
  bool _isLoadingFavoriteStatus = false;

  /// 是否正在切换收藏状态
  bool _isTogglingFavorite = false;

  // 弹弹play用户评分相关
  int _userRating = 0; // 用户评分（0-10，0代表未评分）
  bool _isLoadingUserRating = false; // 是否正在加载用户评分
  bool _isSubmittingRating = false; // 是否正在提交评分

  // Bangumi云端收藏相关
  int? _bangumiSubjectId;
  String? _bangumiComment;
  bool _isLoadingBangumiCollection = false;
  bool _hasBangumiCollection = false;
  int _bangumiUserRating = 0;
  int _bangumiCollectionType = 0;
  int _bangumiEpisodeStatus = 0;
  bool _isSavingBangumiCollection = false;

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

  static const Map<int, String> _collectionTypeLabels = {
    1: '想看',
    2: '已看',
    3: '在看',
    4: '搁置',
    5: '抛弃',
  };

  @override
  void initState() {
    super.initState();
    _openPageContext = context;
    _tabController = TabController(
        length: 2,
        vsync: this,
        initialIndex:
            Provider.of<AppearanceSettingsProvider>(context, listen: false)
                        .animeCardAction ==
                    AnimeCardAction.synopsis
                ? 0
                : 1);

    _sharedSummary = widget.sharedSummary;
    _sharedSourceLabel = widget.sharedSourceLabel;
    _sharedEpisodeLoader = widget.sharedEpisodeLoader;
    _sharedEpisodeBuilder = widget.sharedEpisodeBuilder;

    if (_sharedEpisodeLoader != null && _sharedEpisodeBuilder != null) {
      _loadSharedEpisodes();
    }

    // 添加TabController监听
    _tabController!.addListener(_handleTabChange);

    // 启动时异步清理过期缓存
    _bangumiService.cleanExpiredDetailCache().then((_) {
      debugPrint("[番剧详情] 已清理过期的番剧详情缓存");
    });
    _fetchAnimeDetails().then((_) {
      // 如果初始化时默认打开剧集列表，立即获取云同步状态
      if (_detailedAnime != null &&
          _tabController!.index == 1 &&
          DandanplayService.isLoggedIn) {
        _fetchDandanplayWatchStatus(_detailedAnime!);
      }
    });
  }

  Future<void> _loadSharedEpisodes() async {
    if (_sharedEpisodeLoader == null || _sharedEpisodeBuilder == null) {
      return;
    }
    setState(() {
      _isLoadingSharedEpisodes = true;
      _sharedEpisodesError = null;
      _sharedEpisodeMap.clear();
      _sharedPlayableMap.clear();
    });
    try {
      final episodes = await _sharedEpisodeLoader!.call();
      if (mounted) {
        setState(() {
          for (final episode in episodes) {
            final episodeId = episode.episodeId;
            if (episodeId == null) continue;
            _sharedEpisodeMap[episodeId] = episode;
            final playableItem = _sharedEpisodeBuilder!.call(episode);
            _sharedPlayableMap[episodeId] = playableItem;
          }
          _isLoadingSharedEpisodes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sharedEpisodesError = e.toString();
          _isLoadingSharedEpisodes = false;
          _sharedEpisodeMap.clear();
          _sharedPlayableMap.clear();
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 获取外观设置provider
    _appearanceSettings =
        Provider.of<AppearanceSettingsProvider>(context, listen: false);
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
      if (_tabController!.index == 1 &&
          _detailedAnime != null &&
          DandanplayService.isLoggedIn) {
        // 只有在没有加载过状态时才获取
        if (_dandanplayWatchStatus.isEmpty) {
          _fetchDandanplayWatchStatus(_detailedAnime!);
        }
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
      _bangumiSubjectId = null;
      _bangumiComment = null;
      _isLoadingBangumiCollection = false;
      _hasBangumiCollection = false;
      _bangumiUserRating = 0;
      _bangumiCollectionType = 0;
      _bangumiEpisodeStatus = 0;
      _isSavingBangumiCollection = false;
    });
    try {
      BangumiAnime anime;

      if (kIsWeb) {
        // Web environment: fetch from local API
        try {
          final response = await http
              .get(Uri.parse('/api/bangumi/detail/${widget.animeId}'));
          if (response.statusCode == 200) {
            final data = json.decode(utf8.decode(response.bodyBytes));
            anime = BangumiAnime.fromJson(data as Map<String, dynamic>);
          } else {
            throw Exception(
                'Failed to load details from API: ${response.statusCode}');
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

        _loadBangumiUserData(anime);
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
    if (!DandanplayService.isLoggedIn ||
        anime.episodeList == null ||
        anime.episodeList!.isEmpty) {
      // 重置加载状态
      setState(() {
        _isLoadingDandanplayStatus = false;
        _isLoadingFavoriteStatus = false;
        _isLoadingUserRating = false;
      });
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

      final Future<bool> favoriteStatusFuture =
          DandanplayService.isAnimeFavorited(anime.id);
      final Future<int> userRatingFuture =
          DandanplayService.getUserRatingForAnime(anime.id);

      final results = await Future.wait(
          [watchStatusFuture, favoriteStatusFuture, userRatingFuture]);
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

  int? _extractBangumiSubjectId(BangumiAnime anime) {
    final url = anime.bangumiUrl;
    if (url == null || url.isEmpty) {
      return null;
    }

    final directMatch = RegExp(r'/subject/(\d+)').firstMatch(url);
    if (directMatch != null) {
      return int.tryParse(directMatch.group(1)!);
    }

    final uri = Uri.tryParse(url);
    if (uri != null) {
      if (uri.queryParameters.containsKey('subject_id')) {
        final parsed = int.tryParse(uri.queryParameters['subject_id'] ?? '');
        if (parsed != null) {
          return parsed;
        }
      }

      for (var i = uri.pathSegments.length - 1; i >= 0; i--) {
        final segment = uri.pathSegments[i];
        final parsed = int.tryParse(segment);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    RegExpMatch? lastMatch;
    for (final match in RegExp(r'(\d+)').allMatches(url)) {
      lastMatch = match;
    }
    if (lastMatch != null) {
      return int.tryParse(lastMatch.group(1)!);
    }

    return null;
  }

  Future<void> _loadBangumiUserData(BangumiAnime anime) async {
    if (!BangumiApiService.isLoggedIn) {
      try {
        await BangumiApiService.initialize();
      } catch (e) {
        debugPrint('[番剧详情] 初始化Bangumi API失败: $e');
      }
    }

    if (!BangumiApiService.isLoggedIn) {
      if (mounted) {
        setState(() {
          _bangumiSubjectId = null;
          _bangumiComment = null;
          _isLoadingBangumiCollection = false;
          _hasBangumiCollection = false;
          _bangumiUserRating = 0;
          _bangumiCollectionType = 0;
          _bangumiEpisodeStatus = 0;
        });
      }
      return;
    }

    final subjectId = _extractBangumiSubjectId(anime);
    if (subjectId == null) {
      if (mounted) {
        setState(() {
          _bangumiSubjectId = null;
          _bangumiComment = null;
          _isLoadingBangumiCollection = false;
          _hasBangumiCollection = false;
          _bangumiUserRating = 0;
          _bangumiCollectionType = 0;
          _bangumiEpisodeStatus = 0;
        });
      }
      debugPrint('[番剧详情] 未能解析Bangumi条目ID: ${anime.bangumiUrl}');
      return;
    }

    if (mounted) {
      setState(() {
        _bangumiSubjectId = subjectId;
        _bangumiComment = null;
        _isLoadingBangumiCollection = true;
        _hasBangumiCollection = false;
        _bangumiUserRating = 0;
        _bangumiCollectionType = 0;
        _bangumiEpisodeStatus = 0;
      });
    }

    try {
      final result = await BangumiApiService.getUserCollection(subjectId);

      if (!mounted) return;

      if (result['success'] == true) {
        Map<String, dynamic>? data;
        if (result['data'] is Map) {
          data = Map<String, dynamic>.from(result['data'] as Map);
        }

        if (data == null) {
          setState(() {
            _bangumiSubjectId = subjectId;
            _bangumiComment = null;
            _isLoadingBangumiCollection = false;
            _hasBangumiCollection = false;
            _bangumiUserRating = 0;
            _bangumiCollectionType = 0;
            _bangumiEpisodeStatus = 0;
          });
          return;
        }

        int userRating = 0;
        final ratingData = data['rating'];
        if (ratingData is Map && ratingData['score'] is num) {
          userRating = (ratingData['score'] as num).round();
        } else if (ratingData is num) {
          userRating = ratingData.round();
        }

        int collectionType = 0;
        final typeData = data['type'];
        if (typeData is int) {
          collectionType = typeData;
        }

        int episodeStatus = 0;
        final epStatusData = data['ep_status'];
        if (epStatusData is int) {
          episodeStatus = epStatusData;
        }

        String? comment;
        final rawComment = data['comment'];
        if (rawComment is String) {
          final trimmed = rawComment.trim();
          if (trimmed.isNotEmpty) {
            comment = trimmed;
          }
        }

        setState(() {
          _bangumiSubjectId = subjectId;
          _hasBangumiCollection = true;
          _bangumiComment = comment;
          _bangumiUserRating = userRating;
          _bangumiCollectionType = collectionType;
          _bangumiEpisodeStatus = episodeStatus;
          _isLoadingBangumiCollection = false;
        });
      } else {
        setState(() {
          _bangumiSubjectId = subjectId;
          _bangumiComment = null;
          _isLoadingBangumiCollection = false;
          _hasBangumiCollection = false;
          _bangumiUserRating = 0;
          _bangumiCollectionType = 0;
          _bangumiEpisodeStatus = 0;
        });

        if (result['statusCode'] != 404) {
          debugPrint('[番剧详情] 获取Bangumi收藏信息失败: ${result['message']}');
        }
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[番剧详情] 获取Bangumi评论失败: $e');
      setState(() {
        _bangumiSubjectId = subjectId;
        _isLoadingBangumiCollection = false;
      });
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      // 移除 T00:00:00 部分
      dateStr = dateStr.replaceAll(RegExp(r'T\d{2}:\d{2}:\d{2}'), '');

      final parts = dateStr.split('-');
      if (parts.length >= 3) return '${parts[0]}年${parts[1]}月${parts[2]}日';
      return dateStr;
    } catch (e) {
      return dateStr ?? '';
    }
  }

  String _collectionTypeLabel(int type) {
    return _collectionTypeLabels[type] ?? '未收藏';
  }

  int _getTotalEpisodeCount(BangumiAnime anime) {
    if (anime.totalEpisodes != null && anime.totalEpisodes! > 0) {
      return anime.totalEpisodes!;
    }
    if (anime.episodeList != null && anime.episodeList!.isNotEmpty) {
      return anime.episodeList!.length;
    }
    return 0;
  }

  String _formatEpisodeTotal(BangumiAnime anime) {
    final total = _getTotalEpisodeCount(anime);
    return total > 0 ? total.toString() : '-';
  }

  Future<bool> _syncBangumiCollection({
    int? rating,
    int? collectionType,
    String? comment,
  }) async {
    if (_detailedAnime == null) return false;

    if (!BangumiApiService.isLoggedIn) {
      try {
        await BangumiApiService.initialize();
      } catch (e) {
        debugPrint('[番剧详情] 初始化Bangumi API失败: $e');
      }
    }

    if (!BangumiApiService.isLoggedIn) {
      return false;
    }

    final subjectId =
        _bangumiSubjectId ?? _extractBangumiSubjectId(_detailedAnime!);
    if (subjectId == null) {
      return false;
    }

    final int normalizedType;
    if (collectionType != null && collectionType >= 1 && collectionType <= 5) {
      normalizedType = collectionType;
    } else {
      normalizedType = _bangumiCollectionType != 0 ? _bangumiCollectionType : 3;
    }

    final int? ratingPayload =
        (rating != null && rating >= 1 && rating <= 10) ? rating : null;
    final String? commentPayload = comment == null ? null : comment.trim();

    try {
      Map<String, dynamic> result;
      if (_hasBangumiCollection) {
        result = await BangumiApiService.updateUserCollection(
          subjectId,
          type: normalizedType,
          comment: commentPayload,
        );
      } else {
        result = await BangumiApiService.addUserCollection(
          subjectId,
          normalizedType,
          comment: commentPayload,
        );
      }

      if (result['success'] == true) {
        if (mounted) {
          setState(() {
            _bangumiSubjectId = subjectId;
            _hasBangumiCollection = true;
            _bangumiCollectionType = normalizedType;
            if (commentPayload != null) {
              _bangumiComment =
                  commentPayload.isNotEmpty ? commentPayload : null;
            }
          });
        }
        if (ratingPayload != null) {
          debugPrint('[番剧详情] 跳过Bangumi评分同步，评分仅同步到弹弹play');
        }
        return true;
      }

      debugPrint('[番剧详情] Bangumi收藏更新失败: ${result['message']}');
    } catch (e) {
      debugPrint('[番剧详情] Bangumi收藏更新异常: $e');
    }

    return false;
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
    final sharedSummary = _sharedSummary;
    final String summaryText = (sharedSummary?.summary?.isNotEmpty == true
            ? sharedSummary!.summary!
            : (anime.summary ?? '暂无简介'))
        .replaceAll('<br>', ' ')
        .replaceAll('<br/>', ' ')
        .replaceAll('<br />', ' ');
    final airWeekday = anime.airWeekday;
    final String weekdayString =
        airWeekday != null && _weekdays.containsKey(airWeekday)
            ? _weekdays[airWeekday]!
            : '待定';

    // -- 开始修改 --
    String coverImageUrl = sharedSummary?.imageUrl ?? anime.imageUrl;
    if (kIsWeb) {
      final encodedUrl = base64Url.encode(utf8.encode(coverImageUrl));
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(summaryText, style: valueStyle),
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
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(
                      color: Colors.yellow[600],
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              TextSpan(
                  text: bangumiEvaluationText,
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 12))
            ])),
            const SizedBox(height: 6),
          ],

          // Bangumi云端收藏信息
          if (BangumiApiService.isLoggedIn) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_isLoadingBangumiCollection)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withOpacity(0.8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '正在加载Bangumi收藏信息...',
                        style: valueStyle.copyWith(fontSize: 12),
                      ),
                    ],
                  )
                else
                  RichText(
                    text: TextSpan(
                      style: valueStyle.copyWith(fontSize: 12),
                      children: [
                        const TextSpan(
                          text: '我的Bangumi评分: ',
                          style: TextStyle(
                              color: Colors.lightBlueAccent,
                              fontWeight: FontWeight.bold),
                        ),
                        if (_bangumiUserRating > 0) ...[
                          TextSpan(
                            text: '$_bangumiUserRating 分',
                            style: const TextStyle(
                              color: Colors.lightBlueAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          TextSpan(
                            text: _ratingEvaluationMap[_bangumiUserRating] !=
                                    null
                                ? ' (${_ratingEvaluationMap[_bangumiUserRating]})'
                                : '',
                            style: TextStyle(
                              color: Colors.lightBlueAccent.withOpacity(0.75),
                              fontSize: 12,
                            ),
                          ),
                        ] else
                          const TextSpan(
                            text: '未评分',
                            style: TextStyle(color: Colors.white70),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: (_isLoadingBangumiCollection ||
                          _isSavingBangumiCollection)
                      ? null
                      : _showRatingDialog,
                  icon: _isSavingBangumiCollection
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary),
                          ),
                        )
                      : const Icon(Icons.edit, size: 16),
                  label: const Text(
                    '编辑Bangumi收藏',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (!_isLoadingBangumiCollection && _hasBangumiCollection) ...[
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    '收藏状态: ${_collectionTypeLabel(_bangumiCollectionType)}',
                    style: valueStyle.copyWith(fontSize: 12),
                  ),
                  Text(
                    '观看进度: ${_bangumiEpisodeStatus}/${_formatEpisodeTotal(anime)}',
                    style: valueStyle.copyWith(fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ] else if (!_isLoadingBangumiCollection) ...[
              Text(
                '尚未在Bangumi收藏此番剧',
                style: valueStyle.copyWith(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 6),
            ],
            if (!_isLoadingBangumiCollection)
              Builder(builder: (context) {
                if (_bangumiComment != null && _bangumiComment!.isNotEmpty) {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6.0),
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '我的Bangumi短评',
                          style: boldWhiteKeyStyle.copyWith(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _bangumiComment!,
                          style: valueStyle.copyWith(fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  );
                }
                if (_hasBangumiCollection) {
                  return Text(
                    '暂无Bangumi短评',
                    style: valueStyle.copyWith(
                        fontSize: 12, color: Colors.white70),
                  );
                }
                return const SizedBox.shrink();
              }),
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
                                locale: Locale("zh-Hans", "zh"),
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
          if ((sharedSummary?.episodeCount ?? anime.totalEpisodes) != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  const TextSpan(text: '话数: ', style: boldWhiteKeyStyle),
                  TextSpan(
                      text:
                          '${(sharedSummary?.episodeCount ?? anime.totalEpisodes)}话')
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
    final bool hasSharedEpisodes =
        _sharedEpisodeBuilder != null && _sharedEpisodeMap.isNotEmpty;

    if (_sharedEpisodeBuilder != null && _isLoadingSharedEpisodes) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_sharedEpisodeBuilder != null && _sharedEpisodesError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Ionicons.alert_circle_outline,
                  color: Colors.orangeAccent, size: 42),
              const SizedBox(height: 12),
              Text(
                _sharedEpisodesError!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                ),
                onPressed: _loadSharedEpisodes,
                child: const Text(
                  '重新加载',
                  locale: Locale('zh', 'CN'),
                  style: TextStyle(color: Colors.white),
                ),
              )
            ],
          ),
        ),
      );
    }

    if (anime.episodeList == null || anime.episodeList!.isEmpty) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Text('暂无剧集信息',
            locale: Locale('zh-Hans', 'zh'),
            style: TextStyle(color: Colors.white70)),
      ));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      itemCount: anime.episodeList!.length,
      itemBuilder: (context, index) {
        final episode = anime.episodeList![index];
        final sharedEpisode =
            hasSharedEpisodes ? _sharedEpisodeMap[episode.id] : null;
        final sharedPlayable =
            sharedEpisode != null ? _sharedPlayableMap[episode.id] : null;
        final bool sharedPlayableAvailable = sharedEpisode != null &&
            sharedPlayable != null &&
            sharedEpisode.fileExists;

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

            double progress = sharedEpisode?.progress ?? 0.0;
            bool progressFromHistory = false;
            bool isFromScan = false;
            final historyItem =
                historySnapshot.connectionState == ConnectionState.done
                    ? historySnapshot.data
                    : null;

            if (historyItem != null) {
              final historyProgress = historyItem.watchProgress;
              if (historyProgress >= progress) {
                progress = historyProgress;
                progressFromHistory = true;
              }
              isFromScan = historyItem.isFromScan;
            }

            if (progress > 0.95) {
              leadingIcon = Icon(Ionicons.checkmark_circle,
                  color: Colors.greenAccent.withOpacity(0.8), size: 16);
              tileColor = Colors.white.withOpacity(0.03);
              progressText = '已看完';
            } else if (progress > 0.01) {
              leadingIcon = Icon(Ionicons.play_circle_outline,
                  color: iconColor, size: 16);
              progressText = '${(progress * 100).toStringAsFixed(0)}%';
            } else if (isFromScan) {
              leadingIcon = Icon(Ionicons.play_circle_outline,
                  color: Colors.greenAccent.withOpacity(0.8), size: 16);
              progressText = '未播放';
            } else if (sharedPlayableAvailable) {
              leadingIcon = Icon(Ionicons.play_circle_outline,
                  color: Colors.blueAccent.withOpacity(0.8), size: 16);
              progressText = '共享媒体';
            } else if (historySnapshot.connectionState ==
                    ConnectionState.done &&
                historyItem == null) {
              leadingIcon = const Icon(Ionicons.play_circle_outline,
                  color: Colors.white38, size: 16);
              progressText = '未找到';
            }

            return Material(
              color: tileColor ?? Colors.transparent,
              child: ListTile(
                dense: true,
                leading: leadingIcon,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(episode.title,
                          locale: const Locale('zh-Hans', 'zh'),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (DandanplayService.isLoggedIn &&
                        _dandanplayWatchStatus.containsKey(episode.id))
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_dandanplayWatchStatus[episode.id] == true)
                              Icon(
                                Ionicons.cloud,
                                color: Colors.green.withOpacity(0.9),
                                size: 12,
                              ),
                            if (_dandanplayWatchStatus[episode.id] == true)
                              const SizedBox(width: 4),
                            Text(
                              _dandanplayWatchStatus[episode.id] == true
                                  ? '已看'
                                  : '',
                              locale: const Locale('zh-Hans', 'zh'),
                              style: TextStyle(
                                color: Colors.green.withOpacity(0.9),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                trailing: progressText != null
                    ? Text(
                        progressText,
                        locale: const Locale('zh-Hans', 'zh'),
                        style: TextStyle(
                          color: progress > 0.95
                              ? Colors.greenAccent.withOpacity(0.9)
                              : (progress > 0.01
                                  ? (progressFromHistory
                                      ? Colors.orangeAccent
                                      : Colors.orangeAccent.withOpacity(0.9))
                                  : (progressText == '未播放'
                                      ? Colors.greenAccent.withOpacity(0.9)
                                      : (progressText == '共享媒体'
                                          ? Colors.blueAccent.withOpacity(0.85)
                                          : Colors.white54))),
                          fontSize: 11,
                        ),
                      )
                    : null,
                onTap: () async {
                  if (sharedPlayableAvailable) {
                    await PlaybackService().play(sharedPlayable!);
                    if (mounted) Navigator.pop(context);
                    return;
                  }

                  if (historySnapshot.connectionState == ConnectionState.done &&
                      historyItem != null &&
                      historyItem.filePath.isNotEmpty) {
                    final file = File(historyItem.filePath);
                    if (await file.exists()) {
                      final playableItem = PlayableItem(
                        videoPath: historyItem.filePath,
                        title: anime.nameCn,
                        subtitle: episode.title,
                        animeId: anime.id,
                        episodeId: episode.id,
                        historyItem: historyItem,
                      );
                      await PlaybackService().play(playableItem);
                      if (mounted) Navigator.pop(context);
                    } else {
                      BlurSnackBar.show(
                          context, '文件已不存在于: ${historyItem.filePath}');
                    }
                  } else {
                    BlurSnackBar.show(context, '媒体库中找不到此剧集的视频文件');
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
                  locale: Locale("zh-Hans", "zh"),
                  style: TextStyle(color: Colors.white.withOpacity(0.8))),
              const SizedBox(height: 8),
              Text(
                _error ?? '未知错误',
                locale: Locale("zh-Hans", "zh"),
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2)),
                onPressed: _fetchAnimeDetails,
                child: const Text('重试',
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭',
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
    }

    final anime = _detailedAnime!;
    final displayTitle = (_sharedSummary?.nameCn?.isNotEmpty == true)
        ? _sharedSummary!.nameCn!
        : anime.nameCn;
    final displaySubTitle = (_sharedSummary?.name?.isNotEmpty == true)
        ? _sharedSummary!.name
        : anime.name;
    // 获取是否启用页面切换动画
    final enableAnimation = _appearanceSettings?.enablePageAnimation ?? false;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  displayTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (displaySubTitle != null &&
                  displaySubTitle.isNotEmpty &&
                  displaySubTitle != displayTitle)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    displaySubTitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white60),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (_sharedSourceLabel != null)
                Container(
                  margin: const EdgeInsets.only(right: 8.0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Ionicons.cloud_outline,
                          size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        _sharedSourceLabel!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
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
                          _isFavorited
                              ? Ionicons.heart
                              : Ionicons.heart_outline,
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
            color: Colors.white, // 设置指示器的颜色

            borderRadius: BorderRadius.circular(30), // 设置圆角矩形的圆角半径
          ),
          indicatorWeight: 3,
          tabs: const [
            Tab(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Ionicons.document_text_outline, size: 18),
                  SizedBox(width: 8),
                  Text('简介')
                ])),
            Tab(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Ionicons.film_outline, size: 18),
                  SizedBox(width: 8),
                  Text('剧集')
                ])),
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
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.3),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
            20, MediaQuery.of(context).padding.top + 20, 20, 20),
        child: GlassmorphicContainer(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 15,
          blur: 25,
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

    if (BangumiApiService.isLoggedIn) {
      final initialRating =
          _bangumiUserRating > 0 ? _bangumiUserRating : _userRating;
      final initialType =
          _bangumiCollectionType != 0 ? _bangumiCollectionType : 3;

      BangumiCollectionDialog.show(
        context: context,
        animeTitle: _detailedAnime!.nameCn,
        initialRating: initialRating,
        initialCollectionType: initialType,
        initialComment: _bangumiComment,
        onSubmit: _handleBangumiCollectionSubmitted,
      );
    } else {
      RatingDialog.show(
        context: context,
        animeTitle: _detailedAnime!.nameCn,
        initialRating: _userRating,
        onRatingSubmitted: _handleRatingSubmitted,
      );
    }
  }

  Future<void> _handleBangumiCollectionSubmitted(
    BangumiCollectionSubmitResult result,
  ) async {
    if (_detailedAnime == null) return;

    setState(() {
      _isSavingBangumiCollection = true;
    });

    final int rating = result.rating;
    final int collectionType = result.collectionType;
    final String comment = result.comment.trim();

    bool bangumiSuccess = false;
    Object? bangumiError;

    final bool shouldSyncDandan = DandanplayService.isLoggedIn && rating >= 1;
    bool dandanSuccess = !shouldSyncDandan;
    Object? dandanError;

    try {
      bangumiSuccess = await _syncBangumiCollection(
        rating: rating,
        collectionType: collectionType,
        comment: comment,
      );
      if (!bangumiSuccess) {
        bangumiError = '未知错误';
      }
    } catch (e) {
      bangumiSuccess = false;
      bangumiError = e;
    }

    if (shouldSyncDandan) {
      try {
        await DandanplayService.submitUserRating(
          animeId: _detailedAnime!.id,
          rating: rating,
        );
        dandanSuccess = true;
        if (mounted) {
          setState(() {
            _userRating = rating;
          });
        }
      } catch (e) {
        dandanError = e;
      }
    } else if (mounted) {
      setState(() {
        _userRating = rating;
      });
    }

    if (mounted) {
      setState(() {
        _isSavingBangumiCollection = false;
      });

      if (bangumiSuccess && dandanSuccess) {
        final String message = shouldSyncDandan
            ? 'Bangumi收藏已更新，评分已同步到弹弹play'
            : 'Bangumi收藏已更新';
        _showBlurSnackBar(context, message);
      } else {
        final List<String> parts = [];
        if (!bangumiSuccess) {
          parts.add('Bangumi: ${bangumiError ?? '更新失败'}');
        }
        if (!dandanSuccess) {
          parts.add('弹弹play: ${dandanError ?? '评分同步失败'}');
        }
        _showBlurSnackBar(context, parts.join('；'));
      }
    }
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

      final bool bangumiSynced = await _syncBangumiCollection(rating: rating);

      if (mounted) {
        setState(() {
          _userRating = rating;
          _isSubmittingRating = false;
        });
        if (bangumiSynced) {
          _showBlurSnackBar(context, '评分提交成功，已同步Bangumi');
        } else {
          _showBlurSnackBar(context, '评分提交成功');
        }
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
                blur: 20,
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
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      fontSize: 12,
                      color: _isHovered
                          ? Colors.white
                          : Colors.white.withOpacity(0.9),
                      fontWeight:
                          _isHovered ? FontWeight.w600 : FontWeight.w500,
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
