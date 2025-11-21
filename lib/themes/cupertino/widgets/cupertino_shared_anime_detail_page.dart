import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/models/anime_detail_display_mode.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/bangumi_collection_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/rating_dialog.dart';

class CupertinoSharedAnimeDetailPage extends StatefulWidget {
  const CupertinoSharedAnimeDetailPage({
    super.key,
    required this.anime,
    this.hideBackButton = false,
    this.displayModeOverride,
    this.showCloseButton = true,
    this.customEpisodeLoader,
    this.customPlayableBuilder,
    this.sourceLabelOverride,
  });

  final SharedRemoteAnimeSummary anime;
  final bool hideBackButton;
  final AnimeDetailDisplayMode? displayModeOverride;
  final bool showCloseButton;
  final Future<List<SharedRemoteEpisode>> Function({bool force})?
      customEpisodeLoader;
  final Future<PlayableItem> Function(
      BuildContext context, SharedRemoteEpisode episode)? customPlayableBuilder;
  final String? sourceLabelOverride;

  @override
  State<CupertinoSharedAnimeDetailPage> createState() =>
      _CupertinoSharedAnimeDetailPageState();
}

class _CupertinoSharedAnimeDetailPageState
    extends State<CupertinoSharedAnimeDetailPage> {
  static const int _infoSegment = 0;
  static final Map<int, String> _coverCache = {};
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

  final ScrollController _scrollController = ScrollController();
  final DateFormat _timeFormatter = DateFormat('MM-dd HH:mm');

  int _currentSegment = _infoSegment;
  List<SharedRemoteEpisode>? _episodes;
  bool _isLoadingEpisodes = false;
  
  // Bangumi详细信息
  BangumiAnime? _bangumiAnime;
  bool _isLoadingBangumiAnime = false;
  String? _bangumiAnimeError;

  // 用户评分相关
  int _userRating = 0;
  bool _isLoadingUserRating = false;
  bool _isSubmittingRating = false;

  // Bangumi收藏/短评相关
  int? _bangumiSubjectId;
  bool _isLoadingBangumiCollection = false;
  bool _hasBangumiCollection = false;
  int _bangumiUserRating = 0;
  int _bangumiCollectionType = 0;
  int _bangumiEpisodeStatus = 0;
  String? _bangumiComment;
  bool _isSavingBangumiCollection = false;

  // 云端观看状态
  Map<int, bool> _episodeWatchStatus = {};
  bool _isLoadingWatchStatus = false;
  bool _isSynopsisExpanded = false;
  String? _vividCoverUrl;
  bool _isLoadingCover = false;

  SharedRemoteLibraryProvider? _maybeReadProvider() {
    try {
      return context.read<SharedRemoteLibraryProvider>();
    } catch (_) {
      return null;
    }
  }

  SharedRemoteLibraryProvider? _maybeWatchProvider(BuildContext watchContext) {
    try {
      return watchContext.watch<SharedRemoteLibraryProvider>();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadEpisodes();
      _loadBangumiAnime();
      _maybeLoadVividCover();
    });
  }

  @override
  void didUpdateWidget(covariant CupertinoSharedAnimeDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anime.animeId != widget.anime.animeId ||
        oldWidget.displayModeOverride != widget.displayModeOverride) {
      _vividCoverUrl = null;
      _isLoadingCover = false;
      _maybeLoadVividCover(force: true);
    }
  }

  Future<void> _loadEpisodes({bool force = false}) async {
    setState(() {
      _isLoadingEpisodes = true;
    });

    try {
      List<SharedRemoteEpisode> episodes;
      final customLoader = widget.customEpisodeLoader;
      if (customLoader != null) {
        episodes = await customLoader(force: force);
      } else {
        final provider = _maybeReadProvider();
        if (provider == null) {
          throw '未找到媒体库数据源';
        }
        episodes = await provider.loadAnimeEpisodes(
          widget.anime.animeId,
          force: force,
        );
      }
      if (!mounted) return;
      setState(() {
        _episodes = episodes;
      });
    } catch (e) {
      if (!mounted) return;
      // 错误处理:可以在这里添加错误提示
      debugPrint('[共享番剧详情] 加载剧集失败: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingEpisodes = false;
      });
    }
  }

  Future<void> _loadBangumiAnime({bool force = false}) async {
    if (force && mounted) {
      setState(() {
        _bangumiAnime = null;
        _bangumiAnimeError = null;
        _bangumiSubjectId = null;
        _bangumiComment = null;
        _bangumiUserRating = 0;
        _bangumiCollectionType = 0;
        _bangumiEpisodeStatus = 0;
        _hasBangumiCollection = false;
      });
    }

    setState(() {
      _isLoadingBangumiAnime = true;
      _bangumiAnimeError = null;
    });

    try {
      final anime = await BangumiService.instance.getAnimeDetails(widget.anime.animeId);
      if (!mounted) return;
      setState(() {
        _bangumiAnime = anime;
      });

      // 加载完Bangumi信息后，加载观看状态
      _loadWatchStatus();
      _loadBangumiUserData(anime);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bangumiAnimeError = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingBangumiAnime = false;
      });
    }
  }

  Future<void> _loadWatchStatus() async {
    final bangumiAnime = _bangumiAnime;
    if (bangumiAnime?.episodeList == null || bangumiAnime!.episodeList!.isEmpty) {
      return;
    }

    setState(() {
      _isLoadingWatchStatus = true;
      _isLoadingUserRating = true;
    });

    try {
      // 获取所有剧集的ID
      final episodeIds = bangumiAnime.episodeList!
          .map((episode) => episode.id)
          .toList();

      final results = await Future.wait([
        DandanplayService.getEpisodesWatchStatus(episodeIds),
        DandanplayService.getUserRatingForAnime(bangumiAnime.id),
      ]);

      final watchStatus = results[0] as Map<int, bool>;
      final int userRating = results[1] as int;

      if (!mounted) return;
      setState(() {
        _episodeWatchStatus = watchStatus;
        _userRating = userRating;
      });
    } catch (e) {
      debugPrint('[共享番剧详情] 加载观看状态失败: $e');
      // 出错时设置为空状态，不阻塞UI显示
      if (!mounted) return;
      setState(() {
        _episodeWatchStatus = {};
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingWatchStatus = false;
        _isLoadingUserRating = false;
      });
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
      final subjectId = uri.queryParameters['subject_id'];
      if (subjectId != null) {
        final parsed = int.tryParse(subjectId);
        if (parsed != null) {
          return parsed;
        }
      }

      for (final segment in uri.pathSegments.reversed) {
        final parsed = int.tryParse(segment);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    RegExpMatch? fallback;
    for (final match in RegExp(r'(\d+)').allMatches(url)) {
      fallback = match;
    }
    if (fallback != null) {
      return int.tryParse(fallback.group(1)!);
    }

    return null;
  }

  Future<void> _loadBangumiUserData(BangumiAnime anime) async {
    if (!BangumiApiService.isLoggedIn) {
      try {
        await BangumiApiService.initialize();
      } catch (e) {
        debugPrint('[共享番剧详情] 初始化Bangumi API失败: $e');
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
      debugPrint('[共享番剧详情] 未能解析Bangumi条目ID: ${anime.bangumiUrl}');
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
        } else {
          final rateValue = data['rate'];
          if (rateValue is num) {
            userRating = rateValue.round();
          }
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
          debugPrint('[共享番剧详情] 获取Bangumi收藏信息失败: ${result['message']}');
        }
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[共享番剧详情] 获取Bangumi收藏信息失败: $e');
      setState(() {
        _bangumiSubjectId = subjectId;
        _isLoadingBangumiCollection = false;
      });
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
    int? episodeStatus,
  }) async {
    final bangumiAnime = _bangumiAnime;
    if (bangumiAnime == null) {
      return false;
    }

    if (!BangumiApiService.isLoggedIn) {
      try {
        await BangumiApiService.initialize();
      } catch (e) {
        debugPrint('[共享番剧详情] 初始化Bangumi API失败: $e');
      }
    }

    if (!BangumiApiService.isLoggedIn) {
      return false;
    }

    final subjectId =
        _bangumiSubjectId ?? _extractBangumiSubjectId(bangumiAnime);
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
          rate: ratingPayload,
        );
      } else {
        result = await BangumiApiService.addUserCollection(
          subjectId,
          normalizedType,
          rate: ratingPayload,
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
            if (ratingPayload != null) {
              _bangumiUserRating = ratingPayload;
            }
          });
        }

        if (episodeStatus != null) {
          if (episodeStatus != _bangumiEpisodeStatus) {
            await _syncBangumiEpisodeProgress(subjectId, episodeStatus);
          } else if (mounted) {
            setState(() {
              _bangumiEpisodeStatus = episodeStatus;
            });
          }
        }
        return true;
      }

      debugPrint('[共享番剧详情] 同步Bangumi收藏失败: ${result['message']}');
    } catch (e) {
      debugPrint('[共享番剧详情] 同步Bangumi收藏异常: $e');
    }

    return false;
  }

  Future<void> _syncBangumiEpisodeProgress(
      int subjectId, int desiredStatus) async {
    final bangumiAnime = _bangumiAnime;
    if (bangumiAnime == null) {
      return;
    }

    final episodes = bangumiAnime.episodeList;
    final totalEpisodes = _getTotalEpisodeCount(bangumiAnime);
    final int clampedTarget = totalEpisodes > 0
        ? desiredStatus.clamp(0, totalEpisodes)
        : desiredStatus.clamp(0, 999);

    if (episodes == null || episodes.isEmpty) {
      if (mounted) {
        setState(() {
          _bangumiEpisodeStatus = clampedTarget;
        });
      }
      return;
    }

    try {
      final episodesResult = await BangumiApiService.getSubjectEpisodes(
        subjectId,
        type: 0,
        limit: 200,
      );

      if (episodesResult['success'] != true ||
          episodesResult['data'] == null ||
          episodesResult['data']['data'] == null) {
        debugPrint('[共享番剧详情] 获取Bangumi episodes失败');
        return;
      }

      final bangumiEpisodes =
          List<Map<String, dynamic>>.from(episodesResult['data']['data']);

      if (bangumiEpisodes.isEmpty) {
        debugPrint('[共享番剧详情] Bangumi episodes为空');
        return;
      }

      final List<Map<String, dynamic>> payload = [];
      for (int index = 0;
          index < clampedTarget && index < bangumiEpisodes.length;
          index++) {
        final bangumiEpisodeId = bangumiEpisodes[index]['id'] as int?;
        if (bangumiEpisodeId != null) {
          payload.add({'id': bangumiEpisodeId, 'type': 2});
        }
      }

      if (payload.isEmpty) {
        if (mounted) {
          setState(() {
            _bangumiEpisodeStatus = clampedTarget;
          });
        }
        return;
      }

      final result = await BangumiApiService.batchUpdateEpisodeCollections(
        subjectId,
        payload,
      );

      if (result['success'] == true) {
        if (mounted) {
          setState(() {
            _bangumiEpisodeStatus = clampedTarget;
          });
        }
      } else {
        final message = result['message'] ?? '进度同步失败';
        throw Exception(message);
      }
    } catch (e) {
      debugPrint('[共享番剧详情] Bangumi进度同步异常: $e');
      rethrow;
    }
  }

  void _showRatingDialog() {
    final bangumiAnime = _bangumiAnime;
    if (bangumiAnime == null) {
      return;
    }

    final animeTitle = bangumiAnime.nameCn.isNotEmpty
        ? bangumiAnime.nameCn
        : bangumiAnime.name;

    if (BangumiApiService.isLoggedIn) {
      BangumiCollectionDialog.show(
        context: context,
        animeTitle: animeTitle,
        initialRating: _bangumiUserRating > 0 ? _bangumiUserRating : _userRating,
        initialCollectionType:
            _bangumiCollectionType != 0 ? _bangumiCollectionType : 3,
        initialComment: _bangumiComment,
        initialEpisodeStatus: _bangumiEpisodeStatus,
        totalEpisodes: _getTotalEpisodeCount(bangumiAnime),
        onSubmit: _handleBangumiCollectionSubmitted,
      );
    } else {
      RatingDialog.show(
        context: context,
        animeTitle: animeTitle,
        initialRating: _userRating,
        onRatingSubmitted: _handleRatingSubmitted,
      );
    }
  }

  Future<void> _handleBangumiCollectionSubmitted(
    BangumiCollectionSubmitResult result,
  ) async {
    final bangumiAnime = _bangumiAnime;
    if (bangumiAnime == null) {
      return;
    }

    setState(() {
      _isSavingBangumiCollection = true;
    });

    final int rating = result.rating;
    final int collectionType = result.collectionType;
    final String comment = result.comment.trim();
    final int episodeStatus = result.episodeStatus;

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
        episodeStatus: episodeStatus,
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
          animeId: bangumiAnime.id,
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

    if (!mounted) {
      return;
    }

    setState(() {
      _isSavingBangumiCollection = false;
    });

    if (bangumiSuccess && dandanSuccess) {
      _showSnack(
        shouldSyncDandan ? 'Bangumi收藏、评分与进度已同步' : 'Bangumi收藏已更新',
        type: AdaptiveSnackBarType.success,
      );
    } else {
      final parts = <String>[];
      if (!bangumiSuccess) {
        parts.add('Bangumi: ${bangumiError ?? '更新失败'}');
      }
      if (!dandanSuccess) {
        parts.add('弹弹play: ${dandanError ?? '评分同步失败'}');
      }
      _showSnack(parts.join('；'), type: AdaptiveSnackBarType.error);
    }
  }

  Future<void> _handleRatingSubmitted(int rating) async {
    final bangumiAnime = _bangumiAnime;
    if (bangumiAnime == null) {
      return;
    }

    setState(() {
      _isSubmittingRating = true;
    });

    try {
      await DandanplayService.submitUserRating(
        animeId: bangumiAnime.id,
        rating: rating,
      );

      final bool bangumiSynced = await _syncBangumiCollection(rating: rating);

      if (!mounted) {
        return;
      }

      setState(() {
        _userRating = rating;
        _isSubmittingRating = false;
      });

      _showSnack(
        bangumiSynced ? '评分提交成功，已同步Bangumi' : '评分提交成功',
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      debugPrint('[共享番剧详情] 提交评分失败: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmittingRating = false;
      });
      _showSnack('评分提交失败: ${e.toString()}',
          type: AdaptiveSnackBarType.error);
    }
  }

  void _showSnack(String message,
      {AdaptiveSnackBarType type = AdaptiveSnackBarType.info}) {
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: type,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier?>();
    final displayMode = widget.displayModeOverride ??
        themeNotifier?.animeDetailDisplayMode ??
        AnimeDetailDisplayMode.simple;

    if (displayMode == AnimeDetailDisplayMode.vivid) {
      _maybeLoadVividCover();
      return _buildVividLayout(context);
    }
    return _buildSimpleLayout(context);
  }

  void _maybeLoadVividCover({bool force = false}) {
    final themeNotifier = context.read<ThemeNotifier?>();
    final mode = widget.displayModeOverride ??
        themeNotifier?.animeDetailDisplayMode ??
        AnimeDetailDisplayMode.simple;
    if (mode != AnimeDetailDisplayMode.vivid) {
      return;
    }

    if (!force && _coverCache.containsKey(widget.anime.animeId)) {
      _vividCoverUrl = _coverCache[widget.anime.animeId];
      return;
    }

    if (!force && (_vividCoverUrl != null || _isLoadingCover)) {
      return;
    }
    _fetchHighQualityCover();
  }

  Future<void> _fetchHighQualityCover() async {
    if (_isLoadingCover) return;
    debugPrint('[共享番剧详情] 开始获取高清封面 animeId=${widget.anime.animeId}');
    setState(() {
      _isLoadingCover = true;
    });

    String? coverUrl;
    try {
      BangumiAnime? animeDetail = _bangumiAnime;
      animeDetail ??= await BangumiService.instance
          .getAnimeDetails(widget.anime.animeId);

      final bangumiId = _parseBangumiIdFromUrl(animeDetail?.bangumiUrl);
      if (bangumiId != null) {
        coverUrl = await _requestBangumiHighQualityImage(bangumiId);
        debugPrint('[共享番剧详情] Bangumi高清封面: $coverUrl');
      }

      coverUrl ??= animeDetail?.imageUrl;
      debugPrint('[共享番剧详情] 回落封面: $coverUrl');
    } catch (e) {
      debugPrint('[共享番剧详情] 获取高清封面失败: $e');
    }

    coverUrl ??= _resolveImageUrl(_maybeReadProvider());

    if (!mounted) return;
    setState(() {
      _vividCoverUrl = coverUrl;
      _isLoadingCover = false;
    });

    if (coverUrl != null && coverUrl.isNotEmpty) {
      _coverCache[widget.anime.animeId] = coverUrl;
    }
  }

  Widget _buildSimpleLayout(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );

    return Stack(
      children: [
        CupertinoBottomSheetContentLayout(
          controller: _scrollController,
          backgroundColor: backgroundColor,
          floatingTitleOpacity: 0,
          sliversBuilder: (context, topSpacing) {
            final provider = _maybeWatchProvider(context);
            final hostName =
                widget.sourceLabelOverride ?? provider?.activeHost?.displayName;
            return [
              SliverToBoxAdapter(
                child: _buildHeader(context, topSpacing, hostName),
              ),
              SliverToBoxAdapter(
                child: _buildSegmentedControl(context),
              ),
              if (_currentSegment == _infoSegment)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: _buildInfoSection(context, hostName),
                  ),
                )
              else
                ..._buildEpisodeSlivers(context),
            ];
          },
        ),
        if (!widget.hideBackButton)
          Positioned(
            top: 0,
            left: 0,
            child: Padding(
              padding: EdgeInsets.all(_toolbarPadding),
              child: _buildBackButton(context),
            ),
          ),
        if (widget.showCloseButton)
          Positioned(
            top: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.all(_toolbarPadding),
              child: _buildCloseButton(context),
            ),
          ),
      ],
    );
  }

  Widget _buildVividLayout(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );

    final provider = _maybeWatchProvider(context);
    final hostName =
        widget.sourceLabelOverride ?? provider?.activeHost?.displayName;

    return Stack(
      children: [
        CupertinoBottomSheetContentLayout(
          controller: _scrollController,
          backgroundColor: backgroundColor,
          floatingTitleOpacity: 0,
          sliversBuilder: (context, topSpacing) {
            final ratingSection = _buildRatingSection(context);
            return [
              SliverToBoxAdapter(
                child: _buildVividHeader(context, hostName),
              ),
              SliverToBoxAdapter(
                child: _buildVividPlayButton(context),
              ),
              SliverToBoxAdapter(
                child: _buildVividSynopsisSection(context),
              ),
              if (ratingSection != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: ratingSection,
                  ),
                ),
              ..._buildVividEpisodeSlivers(context),
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ];
          },
        ),
        if (!widget.hideBackButton)
          Positioned(
            top: 0,
            left: 0,
            child: Padding(
              padding: EdgeInsets.all(_toolbarPadding),
              child: _buildBackButton(context),
            ),
          ),
        if (widget.showCloseButton)
          Positioned(
            top: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.all(_toolbarPadding),
              child: _buildCloseButton(context),
            ),
          ),
      ],
    );
  }

  String? get _cleanSummary {
    final summary = widget.anime.summary?.trim();
    if (summary == null || summary.isEmpty) {
      return null;
    }
    return summary
        .replaceAll('<br>', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll('<br />', '\n')
        .replaceAll('```', '')
        .trim();
  }

  SharedRemoteEpisode? get _firstPlayableEpisode {
    if (_episodes == null) return null;
    for (final episode in _episodes!) {
      if (episode.fileExists) {
        return episode;
      }
    }
    return null;
  }

  Widget _buildVividHeader(BuildContext context, String? hostName) {
    final surfaceColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final maskColor = surfaceColor;
    final highlightColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final detailColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final fallbackCover = _resolveImageUrl(_maybeReadProvider());
    final imageUrl = _vividCoverUrl ?? fallbackCover;
    final title = widget.anime.nameCn?.isNotEmpty == true
        ? widget.anime.nameCn!
        : widget.anime.name;

    final metaParts = <String>[
      '共${widget.anime.episodeCount}集',
      _timeFormatter.format(widget.anime.lastWatchTime.toLocal()),
      if (hostName != null && hostName.isNotEmpty) hostName,
    ];

    return AspectRatio(
      aspectRatio: 5 / 7,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: surfaceColor),
          if (imageUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.5,
                child: CachedNetworkImageWidget(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  shouldCompress: false,
                  delayLoad: true,
                  loadMode: CachedImageLoadMode.hybrid,
                  errorBuilder: (_, __) => Container(color: surfaceColor),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [
                    maskColor,
                    maskColor.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .navLargeTitleTextStyle
                      .copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: highlightColor,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  metaParts.join(' · '),
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(
                        fontSize: 13,
                        color: detailColor,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVividPlayButton(BuildContext context) {
    final playableEpisode = _firstPlayableEpisode;
    final bool isEnabled = playableEpisode != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: CupertinoButton.filled(
        onPressed:
            isEnabled ? () => _playEpisode(playableEpisode!) : null,
        padding: const EdgeInsets.symmetric(vertical: 14),
        borderRadius: BorderRadius.circular(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(CupertinoIcons.play_fill, size: 20),
            SizedBox(width: 8),
            Text('播放', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildVividSynopsisSection(BuildContext context) {
    final summary = _cleanSummary;
    final titleStyle = CupertinoTheme.of(context)
        .textTheme
        .textStyle
        .copyWith(fontSize: 17, fontWeight: FontWeight.w600);
    final bodyStyle = CupertinoTheme.of(context)
        .textTheme
        .textStyle
        .copyWith(fontSize: 14, height: 1.45, color: CupertinoColors.secondaryLabel);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('剧情简介', style: titleStyle),
          const SizedBox(height: 12),
          if (summary != null && summary.isNotEmpty) ...[
            AnimatedCrossFade(
              firstChild: Text(
                summary,
                style: bodyStyle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              secondChild: Text(summary, style: bodyStyle),
              crossFadeState: _isSynopsisExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() {
                    _isSynopsisExpanded = !_isSynopsisExpanded;
                  });
                },
                child: Text(
                  _isSynopsisExpanded ? '收起简介' : '展开更多',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ] else
            Text('暂无简介。', style: bodyStyle),
        ],
      ),
    );
  }

  List<Widget> _buildVividEpisodeSlivers(BuildContext context) {
    if (_isLoadingBangumiAnime || _isLoadingEpisodes) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ),
      ];
    }

    if (_bangumiAnimeError != null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_circle,
                  size: 44,
                  color: CupertinoColors.systemRed,
                ),
                const SizedBox(height: 12),
                Text(
                  '加载剧集失败',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _bangumiAnimeError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
                const SizedBox(height: 18),
                CupertinoButton.filled(
                  onPressed: () => _loadBangumiAnime(force: true),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final bangumiAnime = _bangumiAnime;
    if (bangumiAnime == null ||
        bangumiAnime.episodeList == null ||
        bangumiAnime.episodeList!.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                '暂无剧集信息',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
            ),
          ),
        ),
      ];
    }

    final sharedEpisodesMap = <int, SharedRemoteEpisode>{};
    if (_episodes != null) {
      for (final episode in _episodes!) {
        if (episode.episodeId != null) {
          sharedEpisodesMap[episode.episodeId!] = episode;
        }
      }
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            '剧集',
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: bangumiAnime.episodeList!.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final episode = bangumiAnime.episodeList![index];
              final sharedEpisode = sharedEpisodesMap[episode.id];
              final hasSharedFile =
                  sharedEpisode != null && sharedEpisode.fileExists;
              final isWatched = _episodeWatchStatus[episode.id] ?? false;
              return _buildVividEpisodeCard(
                context,
                index,
                episode,
                sharedEpisode: sharedEpisode,
                hasSharedFile: hasSharedFile,
                isWatched: isWatched,
              );
            },
          ),
        ),
      ),
    ];
  }

  Widget _buildVividEpisodeCard(
    BuildContext context,
    int index,
    EpisodeData bangumiEpisode, {
    SharedRemoteEpisode? sharedEpisode,
    bool hasSharedFile = false,
    bool isWatched = false,
  }) {
    final primaryColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final subtitleColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );

    return GestureDetector(
      onTap: hasSharedFile ? () => _playEpisode(sharedEpisode!) : null,
      child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: hasSharedFile
                          ? CupertinoDynamicColor.resolve(
                              CupertinoColors.systemGrey5,
                              context,
                            )
                          : CupertinoDynamicColor.resolve(
                              const CupertinoDynamicColor.withBrightness(
                                color: CupertinoColors.white,
                                darkColor: CupertinoColors.darkBackgroundGray,
                              ),
                              context,
                            ),
                    ),
                    if (hasSharedFile)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Icon(
                          CupertinoIcons.play_circle_fill,
                          size: 24,
                          color: CupertinoTheme.of(context).primaryColor,
                        ),
                      ),
                    if (isWatched)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGreen.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            CupertinoIcons.check_mark,
                            size: 12,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '第${index + 1}集',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              bangumiEpisode.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: subtitleColor, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildRatingSection(BuildContext context) {
    final bangumiAnime = _bangumiAnime;
    if (bangumiAnime == null &&
        !_isLoadingBangumiAnime &&
        _bangumiAnimeError == null) {
      return null;
    }

    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    final borderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );
    final titleColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final secondaryColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    const bangumiAccent = Color(0xFFEB4994);

    final bool isBusy = _isLoadingBangumiCollection ||
        _isSavingBangumiCollection ||
        _isSubmittingRating;

    final Widget actionButton = CupertinoButton.filled(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      borderRadius: BorderRadius.circular(10),
      onPressed:
          (bangumiAnime == null || isBusy) ? null : _showRatingDialog,
      child: isBusy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CupertinoActivityIndicator(radius: 8),
            )
          : Text(
              BangumiApiService.isLoggedIn ? '编辑Bangumi评分' : '为番剧评分',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
    );

    Widget buildUserSection() {
      if (BangumiApiService.isLoggedIn) {
        if (_isLoadingBangumiCollection && bangumiAnime == null) {
          return Row(
            children: [
              const CupertinoActivityIndicator(),
              const SizedBox(width: 8),
              Text(
                '正在同步Bangumi信息...',
                style: TextStyle(color: secondaryColor, fontSize: 13),
              ),
            ],
          );
        }

        if (_isLoadingBangumiCollection) {
          return Row(
            children: [
              const CupertinoActivityIndicator(),
              const SizedBox(width: 8),
              Text(
                '正在加载Bangumi收藏信息...',
                style: TextStyle(color: secondaryColor, fontSize: 13),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '我的Bangumi评分',
              style: TextStyle(
                color: bangumiAccent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            if (_bangumiUserRating > 0) ...[
              Row(
                children: [
                  Text(
                    '${_bangumiUserRating}分',
                    style: TextStyle(
                      color: bangumiAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_ratingEvaluationMap[_bangumiUserRating] != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      _ratingEvaluationMap[_bangumiUserRating]!,
                      style: TextStyle(
                        color: bangumiAccent.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ] else
              Text(
                '未评分，点击右上角按钮进行编辑',
                style: TextStyle(color: secondaryColor, fontSize: 13),
              ),
            const SizedBox(height: 8),
            if (_hasBangumiCollection) ...[
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    '收藏状态: ${_collectionTypeLabel(_bangumiCollectionType)}',
                    style: TextStyle(color: secondaryColor, fontSize: 13),
                  ),
                  Text(
                    '观看进度: ${_bangumiEpisodeStatus}/${bangumiAnime != null ? _formatEpisodeTotal(bangumiAnime) : '-'}',
                    style: TextStyle(color: secondaryColor, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_bangumiComment != null && _bangumiComment!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: bangumiAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: bangumiAccent.withOpacity(0.25),
                      width: 0.6,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '我的Bangumi短评',
                        style: TextStyle(
                          color: bangumiAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _bangumiComment!,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  '暂无Bangumi短评',
                  style: TextStyle(color: secondaryColor, fontSize: 13),
                ),
            ] else
              Text(
                '尚未在Bangumi收藏此番剧',
                style: TextStyle(color: secondaryColor, fontSize: 13),
              ),
          ],
        );
      }

      if (_isSubmittingRating) {
        return Row(
          children: [
            const CupertinoActivityIndicator(),
            const SizedBox(width: 8),
            Text(
              '正在提交评分...',
              style: TextStyle(color: secondaryColor, fontSize: 13),
            ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的评分',
            style: TextStyle(
              color: titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (_userRating > 0) ...[
            Row(
              children: [
                Text(
                  '${_userRating}分',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_ratingEvaluationMap[_userRating] != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    _ratingEvaluationMap[_userRating]!,
                    style: TextStyle(color: secondaryColor, fontSize: 13),
                  ),
                ],
              ],
            ),
          ] else
            Text(
              '尚未评分，登录弹弹play账号后即可同步评分',
              style: TextStyle(color: secondaryColor, fontSize: 13),
            ),
          const SizedBox(height: 6),
          Text(
            '登录Bangumi后可同步收藏与短评',
            style: TextStyle(color: secondaryColor, fontSize: 12),
          ),
        ],
      );
    }

    final ratingValue = bangumiAnime?.ratingDetails?['Bangumi评分'];
    final otherRatings = bangumiAnime?.ratingDetails?.entries
        .where((entry) =>
            entry.key != 'Bangumi评分' &&
            entry.value is num &&
            (entry.value as num) > 0)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '评分与收藏',
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '同步Bangumi与弹弹play的评分、收藏与短评',
                      style: TextStyle(color: secondaryColor, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              actionButton,
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingBangumiAnime && bangumiAnime == null) ...[
            Row(
              children: [
                const CupertinoActivityIndicator(),
                const SizedBox(width: 8),
                Text(
                  '正在加载Bangumi信息...',
                  style: TextStyle(color: secondaryColor, fontSize: 13),
                ),
              ],
            ),
          ] else if (bangumiAnime != null) ...[
            if (ratingValue is num && ratingValue > 0) ...[
              Row(
                children: [
                  _buildRatingStars(ratingValue.toDouble()),
                  const SizedBox(width: 10),
                  Text(
                    '${ratingValue.toStringAsFixed(1)} 分',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_ratingEvaluationMap[ratingValue.round()] != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      _ratingEvaluationMap[ratingValue.round()]!,
                      style: TextStyle(color: secondaryColor, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ] else
              Text(
                '暂未获取到Bangumi评分',
                style: TextStyle(color: secondaryColor, fontSize: 13),
              ),
            const SizedBox(height: 14),
            buildUserSection(),
            if (otherRatings != null && otherRatings.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: otherRatings.map((entry) {
                  String label = entry.key;
                  if (label.endsWith('评分')) {
                    label = label.substring(0, label.length - 2);
                  }
                  final score = (entry.value as num).toStringAsFixed(1);
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemFill,
                        context,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$label: $score',
                      style: TextStyle(color: secondaryColor, fontSize: 12),
                    ),
                  );
                }).toList(),
              ),
            ],
          ] else if (_bangumiAnimeError != null) ...[
            Text(
              '加载Bangumi信息失败：$_bangumiAnimeError',
              style: TextStyle(color: secondaryColor, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRatingStars(double rating, {double size = 14}) {
    final stars = <Widget>[];
    final int fullStars = rating.floor();
    final bool hasHalfStar = (rating - fullStars) >= 0.5;
    for (int i = 0; i < 10; i++) {
      IconData icon;
      Color color = CupertinoColors.systemYellow;
      if (i < fullStars) {
        icon = CupertinoIcons.star_fill;
      } else if (i == fullStars && hasHalfStar) {
        icon = CupertinoIcons.star_lefthalf_fill;
      } else {
        icon = CupertinoIcons.star;
        color = CupertinoColors.systemYellow.withOpacity(0.4);
      }
      stars.add(Icon(icon, size: size, color: color));
      if (i < 9) {
        stars.add(const SizedBox(width: 2));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }

  String? _parseBangumiIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final match = RegExp(r'bangumi\.tv/subject/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  Future<String?> _requestBangumiHighQualityImage(String bangumiId) async {
    try {
      final uri = Uri.parse(
        'https://api.bgm.tv/v0/subjects/$bangumiId/image?type=large',
      );
      debugPrint('[共享番剧详情] 请求Bangumi高清封面: $uri');
      final response = await http.head(
        uri,
        headers: const {'User-Agent': 'NipaPlay/1.0'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 302) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          debugPrint('[共享番剧详情] Bangumi封面重定向: $location');
          return location;
        }
      } else if (response.statusCode == 200) {
        debugPrint('[共享番剧详情] Bangumi封面直接返回200');
        return uri.toString();
      }
    } catch (e) {
      debugPrint('[共享番剧详情] Bangumi 图片接口失败: $e');
    }
    return null;
  }

  Widget _buildHeader(
    BuildContext context,
    double topSpacing,
    String? hostName,
  ) {
    final primaryColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final title = widget.anime.nameCn?.isNotEmpty == true
        ? widget.anime.nameCn!
        : widget.anime.name;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 25, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: primaryColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (hostName != null) ...[
            const SizedBox(height: 4),
            Text(
              '来源：$hostName',
              style: TextStyle(
                color: secondaryColor,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSegmentedControl(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: _buildAdaptiveSegmentedControl(context),
    );
  }

  Widget _buildAdaptiveSegmentedControl(BuildContext context) {
    final Color resolvedTextColor =
        CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.black,
        darkColor: CupertinoColors.white,
      ),
      context,
    );
    final Color resolvedSegmentColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.inactiveGray,
      ),
      context,
    );

    final baseTheme = CupertinoTheme.of(context);
    final segmentTheme = baseTheme.copyWith(
      primaryColor: resolvedTextColor,
      textTheme: baseTheme.textTheme.copyWith(
        textStyle:
            baseTheme.textTheme.textStyle.copyWith(color: resolvedTextColor),
      ),
    );

    return CupertinoTheme(
      data: segmentTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: resolvedTextColor,
          fontWeight: FontWeight.w500,
        ),
        child: AdaptiveSegmentedControl(
          labels: const ['详情', '剧集'],
          selectedIndex: _currentSegment,
          color: resolvedSegmentColor,
          onValueChanged: (index) {
            setState(() {
              _currentSegment = index;
            });
          },
        ),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, String? hostName) {
    final resolvedCardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    final primaryColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final imageUrl =
        _resolveImageUrl(_maybeReadProvider());
    final cleanSummary = _cleanSummary;
    final ratingSection = _buildRatingSection(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: resolvedCardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 120,
                      height: 168,
                      child: _buildPoster(imageUrl),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.anime.name,
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          context,
                          icon: CupertinoIcons.play_rectangle,
                          label: '剧集数量',
                          value: '${widget.anime.episodeCount}',
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          context,
                          icon: CupertinoIcons.time,
                          label: '最近观看',
                          value: _timeFormatter
                              .format(widget.anime.lastWatchTime.toLocal()),
                        ),
                        if (hostName != null) ...[
                          const SizedBox(height: 8),
                          _buildInfoRow(
                            context,
                            icon: CupertinoIcons.share,
                            label: '客户端',
                            value: hostName,
                          ),
                        ],
                        if (widget.anime.hasMissingFiles) ...[
                          const SizedBox(height: 12),
                          _buildInfoBadge(
                            context,
                            icon: CupertinoIcons.exclamationmark_triangle_fill,
                            text: '该番剧存在缺失文件',
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '简介',
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (cleanSummary != null && cleanSummary.isNotEmpty)
                  Text(
                    cleanSummary,
                    style: TextStyle(
                      color: secondaryColor,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  )
                else
                  Text(
                    '暂无简介。',
                    style: TextStyle(
                      color: secondaryColor,
                      fontSize: 14,
                    ),
                  ),

                if (ratingSection != null) ...[
                  const SizedBox(height: 20),
                  ratingSection,
                ],

                // 显示Bangumi详细信息
                if (_isLoadingBangumiAnime)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: CupertinoActivityIndicator(),
                    ),
                  )
                else if (_bangumiAnime != null) ...[
                  // 制作信息
                  if (_bangumiAnime!.metadata != null && _bangumiAnime!.metadata!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      '制作信息',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._bangumiAnime!.metadata!.where((item) {
                      final trimmed = item.trim();
                      return !trimmed.startsWith('别名:') && !trimmed.startsWith('别名：');
                    }).map((item) {
                      final parts = item.split(RegExp(r'[:：]'));
                      if (parts.length == 2) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: secondaryColor,
                                fontSize: 14,
                                height: 1.4,
                              ),
                              children: [
                                TextSpan(
                                  text: '${parts[0].trim()}: ',
                                  style: TextStyle(
                                    color: primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(text: parts[1].trim()),
                              ],
                            ),
                          ),
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            item,
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        );
                      }
                    }).toList(),
                  ],

                  // 标签
                  if (_bangumiAnime!.tags != null && _bangumiAnime!.tags!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      '标签',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _bangumiAnime!.tags!.map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.systemFill,
                              context,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoster(String? imageUrl) {
    final placeholderColor = CupertinoDynamicColor.resolve(
      CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.systemGrey5,
        darkColor: CupertinoColors.darkBackgroundGray,
      ),
      context,
    );

    if (imageUrl == null) {
      return DecoratedBox(
        decoration: BoxDecoration(color: placeholderColor),
        child: const Center(
          child: Icon(
            CupertinoIcons.tv,
            size: 32,
            color: CupertinoColors.systemGrey,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: placeholderColor,
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => DecoratedBox(
          decoration: BoxDecoration(color: placeholderColor),
          child: const Center(
            child: Icon(
              CupertinoIcons.tv,
              size: 32,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final valueColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: labelColor),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: labelColor, fontSize: 13),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBadge(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final resolvedColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemRed.withOpacity(0.12),
      context,
    );
    final textColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: resolvedColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: textColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEpisodeSlivers(BuildContext context) {
    // 如果正在加载Bangumi数据,显示加载状态
    if (_isLoadingBangumiAnime || _isLoadingEpisodes) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoActivityIndicator(),
                SizedBox(height: 12),
                Text(
                  '正在加载剧集...',
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    // 如果Bangumi数据加载失败,显示错误
    if (_bangumiAnimeError != null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_circle,
                  size: 44,
                  color: CupertinoColors.systemRed,
                ),
                const SizedBox(height: 12),
                Text(
                  '加载剧集失败',
                  style: TextStyle(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.label, context),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _bangumiAnimeError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondaryLabel, context),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 18),
                CupertinoButton.filled(
                  onPressed: () => _loadBangumiAnime(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    // 检查是否有BangumiAnime数据
    final bangumiAnime = _bangumiAnime;
    if (bangumiAnime == null || bangumiAnime.episodeList == null || bangumiAnime.episodeList!.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.tv,
                  size: 44,
                  color: CupertinoColors.inactiveGray,
                ),
                SizedBox(height: 12),
                Text(
                  '暂无剧集信息',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    // 创建共享剧集的映射表,以便快速查找
    final sharedEpisodesMap = <int, SharedRemoteEpisode>{};
    if (_episodes != null) {
      for (final episode in _episodes!) {
        if (episode.episodeId != null) {
          sharedEpisodesMap[episode.episodeId!] = episode;
        }
      }
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index.isOdd) {
                return const SizedBox(height: 10);
              }
              final episodeIndex = index ~/ 2;
              final bangumiEpisode = bangumiAnime.episodeList![episodeIndex];
              final sharedEpisode = sharedEpisodesMap[bangumiEpisode.id];
              final hasSharedFile = sharedEpisode != null && sharedEpisode.fileExists;

              return _buildEpisodeTile(
                context,
                bangumiEpisode,
                sharedEpisode: sharedEpisode,
                hasSharedFile: hasSharedFile,
                isWatched: _episodeWatchStatus[bangumiEpisode.id] ?? false,
              );
            },
            childCount: bangumiAnime.episodeList!.length * 2 - 1,
          ),
        ),
      ),
    ];
  }

  Widget _buildEpisodeTile(
    BuildContext context,
    EpisodeData bangumiEpisode, {
    SharedRemoteEpisode? sharedEpisode,
    bool hasSharedFile = false,
    bool isWatched = false,
  }) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    // 根据是否有共享文件来确定图标颜色和样式
    final iconColor = hasSharedFile
        ? CupertinoColors.activeBlue
        : CupertinoDynamicColor.resolve(CupertinoColors.systemGrey, context);

    final isEnabled = hasSharedFile;

    return GestureDetector(
      onTap: isEnabled ? () => _playEpisode(sharedEpisode!) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            const CupertinoDynamicColor.withBrightness(
              color: CupertinoColors.white,
              darkColor: CupertinoColors.darkBackgroundGray,
            ),
            context,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(0.07),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: hasSharedFile
                    ? iconColor
                    : CupertinoDynamicColor.resolve(
                        CupertinoColors.systemGrey5,
                        context,
                      ),
                borderRadius: BorderRadius.circular(12),
                border: hasSharedFile
                    ? Border.all(
                        color: CupertinoColors.white,
                        width: 1.5,
                      )
                    : null,
              ),
              child: Icon(
                CupertinoIcons.play_fill,
                size: 16,
                color: hasSharedFile
                    ? CupertinoColors.white
                    : CupertinoDynamicColor.resolve(
                        CupertinoColors.systemGrey2,
                        context,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bangumiEpisode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasSharedFile ? labelColor : subtitleColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (sharedEpisode != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      sharedEpisode.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 云端已观看标记和可观看标记
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isWatched && hasSharedFile) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.cloud_fill,
                          size: 10,
                          color: CupertinoColors.systemGreen,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '已观看',
                          style: TextStyle(
                            color: CupertinoColors.systemGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (hasSharedFile)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '可观看',
                      style: TextStyle(
                        color: CupertinoColors.activeBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Icon(
                    CupertinoIcons.xmark,
                    size: 16,
                    color: subtitleColor,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playEpisode(SharedRemoteEpisode episode) async {
    try {
      PlayableItem playableItem;
      final customBuilder = widget.customPlayableBuilder;
      if (customBuilder != null) {
        playableItem = await customBuilder(context, episode);
      } else {
        final provider = _maybeReadProvider();
        if (provider == null) {
          throw '未找到媒体库数据源';
        }
        playableItem = provider.buildPlayableItem(
          anime: widget.anime,
          episode: episode,
        );
      }
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      // 先关闭详情弹窗，避免横屏时页面残留导致的画面撕裂
      await rootNavigator.maybePop();
      await PlaybackService().play(playableItem);
    } catch (e) {
      AdaptiveSnackBar.show(
        context,
        message: '播放失败：$e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Widget _buildBackButton(BuildContext context) {
    final iconColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    if (PlatformInfo.isIOS26OrHigher()) {
      return SizedBox(
        width: _toolbarButtonSize,
        height: _toolbarButtonSize,
        child: AdaptiveButton.sfSymbol(
          useSmoothRectangleBorder: false,
          onPressed: () => Navigator.of(context).maybePop(),
          style: AdaptiveButtonStyle.glass,
          size: AdaptiveButtonSize.large,
          sfSymbol: SFSymbol('chevron.left', size: 16, color: iconColor),
        ),
      );
    }

    return SizedBox(
      width: _toolbarButtonSize,
      height: _toolbarButtonSize,
      child: AdaptiveButton.child(
        useSmoothRectangleBorder: false,
        onPressed: () => Navigator.of(context).maybePop(),
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        child: Icon(
          CupertinoIcons.chevron_left,
          size: 16,
          color: iconColor,
        ),
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    final iconColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    if (PlatformInfo.isIOS26OrHigher()) {
      return SizedBox(
        width: _toolbarButtonSize,
        height: _toolbarButtonSize,
        child: AdaptiveButton.sfSymbol(
          useSmoothRectangleBorder: false,
          onPressed: () => Navigator.of(context).maybePop(),
          style: AdaptiveButtonStyle.glass,
          size: AdaptiveButtonSize.large,
          sfSymbol: SFSymbol('xmark', size: 16, color: iconColor),
        ),
      );
    }

    return SizedBox(
      width: _toolbarButtonSize,
      height: _toolbarButtonSize,
      child: AdaptiveButton.child(
        useSmoothRectangleBorder: false,
        onPressed: () => Navigator.of(context).maybePop(),
        style: AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.large,
        child: Icon(
          CupertinoIcons.xmark,
          size: 16,
          color: iconColor,
        ),
      ),
    );
  }

  String? _resolveImageUrl([SharedRemoteLibraryProvider? provider]) {
    final imageUrl = widget.anime.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return null;
    }
    if (imageUrl.startsWith('http') || provider == null) {
      return imageUrl;
    }
    final baseUrl = provider.activeHost?.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      return imageUrl;
    }
    if (imageUrl.startsWith('/')) {
      return '$baseUrl$imageUrl';
    }
    return '$baseUrl/$imageUrl';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static const double _toolbarPadding = 12;
  static const double _toolbarButtonSize = 40;
}
