import 'package:flutter/material.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/jellyfin_dandanplay_matcher.dart';
import 'package:nipaplay/services/emby_dandanplay_matcher.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_detail_shell.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class MediaServerDetailPage extends StatefulWidget {
  final String mediaId;
  final MediaServerType serverType;

  const MediaServerDetailPage({
    super.key, 
    required this.mediaId, 
    required this.serverType,
  });

  @override
  State<MediaServerDetailPage> createState() => _MediaServerDetailPageState();
  
  static Future<WatchHistoryItem?> showJellyfin(BuildContext context, String jellyfinId) {
    return show(context, jellyfinId, MediaServerType.jellyfin);
  }

  static Future<WatchHistoryItem?> showEmby(BuildContext context, String embyId) {
    return show(context, embyId, MediaServerType.emby);
  }

  static Future<WatchHistoryItem?> show(BuildContext context, String mediaId, MediaServerType serverType) {
    // 获取外观设置Provider
    final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context, listen: false);
    final enableAnimation = appearanceSettings.enablePageAnimation;
    
    return NipaplayWindow.show<WatchHistoryItem>(
      context: context,
      enableAnimation: enableAnimation,
      child: MediaServerDetailPage(mediaId: mediaId, serverType: serverType),
    );
  }
}

class _MediaServerDetailPageState extends State<MediaServerDetailPage> with SingleTickerProviderStateMixin {
  // 静态Map，用于存储视频的哈希值（ID -> 哈希值）
  static final Map<String, String> _videoHashes = {};
  static final Map<String, Map<String, dynamic>> _videoInfos = {};
  
  // 通用媒体详情（可以是Jellyfin或Emby）
  dynamic _mediaDetail;
  List<dynamic> _seasons = [];
  final Map<String, List<dynamic>> _episodesBySeasonId = {};
  String? _selectedSeasonId;
  bool _isLoading = true;
  String? _error;
  bool _isMovie = false; // 新增状态，判断是否为电影

  bool _isDetailAutoMatching = false;
  bool _detailAutoMatchDialogVisible = false;
  bool _detailAutoMatchCancelled = false;

  TabController? _tabController;
  String? _hoveredEpisodeId;

  // 辅助方法：获取演员头像URL
  String? _getActorImageUrl(dynamic actor) {
    if (widget.serverType == MediaServerType.jellyfin) {
      if (actor.primaryImageTag != null) {
        final service = JellyfinService.instance;
        return service.getImageUrl(actor.id, type: 'Primary', width: 100, quality: 90);
      }
    } else {
      if (actor.imagePrimaryTag != null && actor.id != null) {
        final service = EmbyService.instance;
        return service.getImageUrl(actor.id!, type: 'Primary', width: 100, height: 100, tag: actor.imagePrimaryTag);
      }
    }
    return null;
  }

  // 辅助方法：获取剧集缩略图URL
  String _getEpisodeImageUrl(dynamic episode, dynamic service) {
    if (widget.serverType == MediaServerType.jellyfin) {
      return service.getImageUrl(episode.id, type: 'Primary', width: 300, quality: 90);
    } else {
      // Emby需要传递tag参数
      return service.getImageUrl(episode.id, type: 'Primary', width: 300, tag: episode.imagePrimaryTag);
    }
  }

  // 辅助方法：获取海报URL
  String _getPosterUrl({int width = 300}) {
    if (_mediaDetail?.imagePrimaryTag == null) return '';
    
    if (widget.serverType == MediaServerType.jellyfin) {
      final service = JellyfinService.instance;
      return service.getImageUrl(_mediaDetail!.id, type: 'Primary', width: width, quality: 95);
    } else {
      final service = EmbyService.instance;
      return service.getImageUrl(_mediaDetail!.id, type: 'Primary', width: width, tag: _mediaDetail!.imagePrimaryTag);
    }
  }

  String _getBackdropUrl() {
    if (_mediaDetail?.imageBackdropTag == null) return '';
    if (widget.serverType == MediaServerType.jellyfin) {
      final service = JellyfinService.instance;
      return service.getImageUrl(_mediaDetail!.id,
          type: 'Backdrop', width: 1920, height: 1080, quality: 95);
    } else {
      final service = EmbyService.instance;
      return service.getImageUrl(_mediaDetail!.id,
          type: 'Backdrop',
          width: 1920,
          height: 1080,
          quality: 95,
          tag: _mediaDetail!.imageBackdropTag);
    }
  }

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
      dynamic service;
      dynamic detail;
      
      if (widget.serverType == MediaServerType.jellyfin) {
        service = JellyfinService.instance;
        detail = await service.getMediaItemDetails(widget.mediaId);
      } else {
        service = EmbyService.instance;
        detail = await service.getMediaItemDetails(widget.mediaId);
      }
      
      if (mounted) {
        setState(() {
          _mediaDetail = detail;
          _isMovie = detail.type == 'Movie'; // 判断是否为电影

          if (_isMovie) {
            _isLoading = false;
            // 对于电影，我们不需要 TabController
          } else {
            // 对于剧集，初始化 TabController
            _tabController = TabController(
                length: 2,
                vsync: this,
                initialIndex: Provider.of<AppearanceSettingsProvider>(context, listen: false)
                    .animeCardAction == AnimeCardAction.synopsis ? 0 : 1
            );
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
        dynamic seasons;
        if (widget.serverType == MediaServerType.jellyfin) {
          seasons = await (service as JellyfinService).getSeriesSeasons(widget.mediaId);
        } else {
          seasons = await (service as EmbyService).getSeasons(widget.mediaId);
        }
        
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
      // 确保_mediaDetail不为null且有有效id
      if (_mediaDetail?.id == null) {
        if (mounted) {
          setState(() {
            _error = '无法获取剧集详情，无法加载剧集列表。';
            _isLoading = false;
          });
        }
        return;
      }
      
      dynamic episodes;
      if (widget.serverType == MediaServerType.jellyfin) {
        final service = JellyfinService.instance;
        episodes = await service.getSeasonEpisodes(_mediaDetail!.id, seasonId);
      } else {
        final service = EmbyService.instance;
        episodes = await service.getSeasonEpisodes(_mediaDetail!.id, seasonId);
      }
      
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
  
  Future<WatchHistoryItem?> _createWatchHistoryItem(dynamic episode) async {
    // 根据服务器类型使用相应的匹配器创建可播放的历史记录项
    try {
      dynamic matcher;
      if (widget.serverType == MediaServerType.jellyfin) {
        matcher = JellyfinDandanplayMatcher.instance;
      } else {
        matcher = EmbyDandanplayMatcher.instance;
      }
      
      // 先进行预计算和预匹配，不阻塞主流程
      matcher.precomputeVideoInfoAndMatch(context, episode).then((preMatchResult) {
        final String? videoHash = preMatchResult['videoHash'] as String?;
        final String? fileName = preMatchResult['fileName'] as String?;
        final int? fileSize = preMatchResult['fileSize'] as int?;
        
        if (videoHash != null && videoHash.isNotEmpty) {
          debugPrint('预计算哈希值成功: $videoHash');
          
          // 需要在播放器创建或历史项创建时使用这个哈希值
          _videoHashes[episode.id] = videoHash;
          debugPrint('视频哈希值已缓存: ${episode.id} -> $videoHash');
          
          // 同时保存文件名和文件大小信息
          Map<String, dynamic> videoInfo = {
            'hash': videoHash,
            'fileName': fileName ?? '',
            'fileSize': fileSize ?? 0
          };
          _videoInfos[episode.id] = videoInfo;
          debugPrint('视频信息已缓存: ${episode.id} -> $videoInfo');
        }
        
        if (preMatchResult['success'] == true) {
          debugPrint('预匹配成功: animeId=${preMatchResult['animeId']}, episodeId=${preMatchResult['episodeId']}');
        } else {
          debugPrint('预匹配未成功: ${preMatchResult['message']}');
        }
      }).catchError((e) {
        debugPrint('预计算过程中出错: $e');
      });
      
      // 继续常规匹配流程
      final playableItem = await matcher.createPlayableHistoryItem(context, episode);
      
      // 如果我们有这个视频的信息，添加到历史项中
      if (playableItem != null) {
        // 添加哈希值
        if (_videoHashes.containsKey(episode.id)) {
          final videoHash = _videoHashes[episode.id];
          playableItem.videoHash = videoHash;
          debugPrint('成功将哈希值 $videoHash 添加到历史记录项');
        }
        
        // 存储完整的视频信息，可用于后续弹幕匹配
        if (_videoInfos.containsKey(episode.id)) {
          final videoInfo = _videoInfos[episode.id]!;
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
    if (_isDetailAutoMatching) {
      BlurSnackBar.show(context, '正在自动匹配，请稍候');
      return;
    }

    try {
      final playableItem = await _runDetailAutoMatchTask<WatchHistoryItem?>(() async {
        if (widget.serverType == MediaServerType.jellyfin) {
          final movieInfo = JellyfinMovieInfo(
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
          return JellyfinDandanplayMatcher.instance
              .createPlayableHistoryItemFromMovie(context, movieInfo);
        }

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
        return EmbyDandanplayMatcher.instance
            .createPlayableHistoryItemFromMovie(context, movieInfo);
      });

      if (playableItem == null) {
        if (!_detailAutoMatchCancelled && mounted) {
          BlurSnackBar.show(context, '未能找到匹配的弹幕信息，但仍可播放。');
          final basicItem = _mediaDetail!.toWatchHistoryItem();
          Navigator.of(context).pop(basicItem);
        }
        return;
      }

      if (mounted) {
        Navigator.of(context).pop(playableItem);
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
    
    // Jellyfin和Emby中的RunTimeTicks单位是100纳秒
    final durationInSeconds = runTimeTicks / 10000000;
    final hours = (durationInSeconds / 3600).floor();
    final minutes = ((durationInSeconds % 3600) / 60).floor();
    
    if (hours > 0) {
      return '$hours小时${minutes > 0 ? ' $minutes分钟' : ''}';
    } else {
      return '$minutes分钟';
    }
  }

  String? _formatPremiereDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value.split('T').first;
    }
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }

  Widget _buildRatingStars(double rating) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    if (rating < 0 || rating > 10) {
      return Text('N/A',
          style: TextStyle(color: textColor.withOpacity(0.85), fontSize: 13));
    }

    final stars = <Widget>[];
    final fullStars = rating.floor();
    final halfStar = (rating - fullStars) >= 0.5;

    for (int i = 0; i < 10; i++) {
      if (i < fullStars) {
        stars.add(Icon(Ionicons.star, color: Colors.yellow[600], size: 16));
      } else if (i == fullStars && halfStar) {
        stars.add(
            Icon(Ionicons.star_half, color: Colors.yellow[600], size: 16));
      } else {
        stars.add(Icon(Ionicons.star_outline,
            color: Colors.yellow[600]?.withOpacity(isDark ? 0.7 : 0.4), size: 16));
      }
      if (i < 9) {
        stars.add(const SizedBox(width: 1));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }

  Future<T?> _runDetailAutoMatchTask<T>(Future<T?> Function() task) async {
    if (_isDetailAutoMatching) {
      if (mounted) {
        BlurSnackBar.show(context, '正在自动匹配，请稍候');
      }
      return null;
    }

    _updateDetailAutoMatchingState(true);
    _detailAutoMatchCancelled = false;
    _showDetailAutoMatchingDialog();

    try {
      final result = await task();
      if (_detailAutoMatchCancelled) {
        if (mounted) {
          BlurSnackBar.show(context, '已取消自动匹配');
        }
        return null;
      }
      return result;
    } finally {
      _hideDetailAutoMatchingDialog();
      _updateDetailAutoMatchingState(false);
    }
  }

  void _updateDetailAutoMatchingState(bool value) {
    if (!mounted) {
      _isDetailAutoMatching = value;
      return;
    }
    if (_isDetailAutoMatching == value) {
      return;
    }
    setState(() {
      _isDetailAutoMatching = value;
    });
  }

  void _showDetailAutoMatchingDialog() {
    if (_detailAutoMatchDialogVisible || !mounted) {
      return;
    }
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    _detailAutoMatchDialogVisible = true;
    BlurDialog.show(
      context: context,
      title: '正在自动匹配',
      barrierDismissible: false,
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(textColor),
          ),
          const SizedBox(height: 16),
          Text(
            '正在为当前条目匹配弹幕，请稍候…',
            style: TextStyle(color: textColor, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _detailAutoMatchCancelled = true;
            Navigator.of(context, rootNavigator: true).pop();
          },
          child: const Text('中断匹配', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ).whenComplete(() {
      _detailAutoMatchDialogVisible = false;
    });
  }

  void _hideDetailAutoMatchingDialog() {
    if (!_detailAutoMatchDialogVisible) {
      return;
    }
    if (!mounted) {
      _detailAutoMatchDialogVisible = false;
      return;
    }
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    
    Widget pageContent;

    if (_isLoading && _mediaDetail == null) {
      pageContent = Center(
        child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.black87),
      );
    } else if (_error != null && _mediaDetail == null) {
      pageContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('加载详情失败:', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: textColor.withOpacity(0.8))),
              const SizedBox(height: 8),
              Text(
                _error!,
                locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryTextColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              BlurButton(
                icon: Icons.refresh,
                text: '重试',
                onTap: _loadMediaDetail,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                fontSize: 16,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('关闭', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryTextColor)),
              ),
            ],
          ),
        ),
      );
    } else if (_mediaDetail == null) {
      // 理论上在成功加载后 _mediaDetail 不会为 null，除非发生意外
      pageContent = Center(child: Text('未找到媒体详情', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryTextColor)));
    } else {
      // 成功加载，构建详情UI
      final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context, listen: false);
      final enableAnimation = appearanceSettings.enablePageAnimation;
      final subtitle = _mediaDetail!.originalTitle;
      final bool isDesktopOrTablet = globals.isDesktopOrTablet;

      pageContent = NipaplayAnimeDetailLayout(
        title: _mediaDetail!.name,
        subtitle: subtitle,
        sourceLabel: widget.serverType == MediaServerType.jellyfin
            ? 'Jellyfin'
            : 'Emby',
        sourceLabelUseContainer: false,
        onClose: () => Navigator.of(context).pop(),
        tabController: _tabController,
        showTabs: !isDesktopOrTablet,
        enableAnimation: enableAnimation,
        isDesktopOrTablet: isDesktopOrTablet,
        infoView: RepaintBoundary(child: _buildInfoView()),
        episodesView: _isMovie
            ? null
            : RepaintBoundary(child: _buildEpisodesView()),
        desktopView: (isDesktopOrTablet && !_isMovie)
            ? _buildDesktopTabletLayout()
            : null,
      );
    }

    final backdropUrl = _getBackdropUrl();
    final posterUrl = _getPosterUrl(width: 600);
    final hasBackdrop = backdropUrl.isNotEmpty;

    return NipaplayWindowScaffold(
      backgroundImageUrl: hasBackdrop ? backdropUrl : (posterUrl.isNotEmpty ? posterUrl : null),
      blurBackground: !hasBackdrop, // 如果没有横向图而使用竖向图，开启高斯模糊
      onClose: () => Navigator.of(context).pop(),
      child: pageContent,
    );
  }

  Widget _buildInfoView() {
    if (_mediaDetail == null) return const SizedBox.shrink();

    final summaryText =
        (_mediaDetail!.overview != null && _mediaDetail!.overview!.trim().isNotEmpty
                ? _mediaDetail!.overview!
                : '暂无简介')
            .replaceAll('<br>', ' ')
            .replaceAll('<br/>', ' ')
            .replaceAll('<br />', ' ')
            .replaceAll('```', '');
    final posterUrl = _getPosterUrl();
    final backdropUrl = _getBackdropUrl();
    final ratingValue = double.tryParse(_mediaDetail!.communityRating ?? '');

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    final valueStyle = TextStyle(
      color: textColor.withOpacity(0.85),
      fontSize: 13,
      height: 1.5,
    );
    final boldWhiteKeyStyle = TextStyle(
      color: textColor,
      fontWeight: FontWeight.w600,
      fontSize: 13,
      height: 1.5,
    );
    final sectionTitleStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(color: textColor, fontWeight: FontWeight.bold);

    final infoRows = <Widget>[];
    void addInfoRow(String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      infoRows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: RichText(
            text: TextSpan(
              style: valueStyle,
              children: [
                TextSpan(text: '$label: ', style: boldWhiteKeyStyle),
                TextSpan(text: value.trim(), style: valueStyle),
              ],
            ),
          ),
        ),
      );
    }

    addInfoRow('首播', _formatPremiereDate(_mediaDetail!.premiereDate));
    addInfoRow('年份', _mediaDetail!.productionYear?.toString());
    addInfoRow('时长', _formatRuntime(_mediaDetail!.runTimeTicks));
    addInfoRow('分级', _mediaDetail!.officialRating);
    addInfoRow('制作', _mediaDetail!.seriesStudio);
    if (_mediaDetail!.genres.isNotEmpty) {
      addInfoRow('类型', _mediaDetail!.genres.join(' / '));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              if (_mediaDetail!.originalTitle != null &&
                  _mediaDetail!.originalTitle!.isNotEmpty &&
                  _mediaDetail!.originalTitle != _mediaDetail!.name)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    _mediaDetail!.originalTitle!,
                    style: valueStyle.copyWith(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (posterUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0, bottom: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImageWidget(
                          imageUrl: posterUrl,
                          width: 130,
                          height: 195,
                          fit: BoxFit.cover,
                          loadMode: CachedImageLoadMode.legacy,
                        ),
                      ),
                    ),
                  Expanded(
                    child: SizedBox(
                      height: 195,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Text(summaryText, style: valueStyle),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: textColor.withOpacity(0.15)),
              const SizedBox(height: 8),
              if (ratingValue != null && ratingValue > 0) ...[
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: '评分: ', style: boldWhiteKeyStyle),
                      WidgetSpan(child: _buildRatingStars(ratingValue)),
                      TextSpan(
                        text: ' ${ratingValue.toStringAsFixed(1)} ',
                        style: TextStyle(
                          color: Colors.yellow[600],
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              ...infoRows,
              if (_mediaDetail!.genres.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _mediaDetail!.genres.map<Widget>((genre) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: textColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: textColor.withOpacity(0.12), width: 0.5),
                      ),
                      child: Text(
                        genre,
                        style: TextStyle(color: secondaryTextColor, fontSize: 12),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (_mediaDetail!.cast.isNotEmpty) ...[
                const SizedBox(height: 12),
                if (sectionTitleStyle != null)
                  Text('演员', style: sectionTitleStyle),
                const SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _mediaDetail!.cast.length,
                    itemBuilder: (context, index) {
                      final actor = _mediaDetail!.cast[index];
                      final actorImage = _getActorImageUrl(actor);

                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.grey.shade800,
                              backgroundImage:
                                  actorImage != null ? NetworkImage(actorImage) : null,
                              child: actorImage == null
                                  ? Icon(Icons.person,
                                      color: secondaryTextColor)
                                  : null,
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 70,
                              child: Text(
                                actor.name,
                                style: TextStyle(
                                    fontSize: 12, color: secondaryTextColor),
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
              if (_isMovie) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    BlurButton(
                      icon: Icons.play_arrow,
                      text: '播放',
                      onTap: () {
                        if (_isDetailAutoMatching) {
                          BlurSnackBar.show(context, '正在自动匹配，请稍候');
                          return;
                        }
                        _playMovie();
                      },
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      fontSize: 18,
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
  }

  Widget _buildDesktopTabletLayout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RepaintBoundary(child: _buildInfoView()),
          ),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: 12),
            color: Colors.white.withOpacity(0.12),
          ),
          Expanded(
            child: RepaintBoundary(child: _buildEpisodesView()),
          ),
        ],
      ),
    );
  }
  Widget _buildEpisodesView() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    // 移除原有的 Positioned 返回按钮，因为顶部已经有了全局关闭按钮
    return Column( // 不再需要 Stack，因为返回按钮已全局处理
      children: [
        // const SizedBox(height: 16), // 顶部间距可以根据整体布局调整，TabBar外部已有间距
        
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
                        backgroundColor: isSelected
                            ? textColor.withOpacity(0.2)
                            : Colors.transparent,
                        foregroundColor: isSelected ? textColor : secondaryTextColor,
                        side: BorderSide(
                          color: isSelected ? secondaryTextColor : textColor.withOpacity(0.1),
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Text(season.name),
                    ),
                  );
                },
              ),
            ),
          ),
        
        if (_seasons.isNotEmpty) // 仅当有季节选择器时显示分割线
          Divider(height: 1, thickness: 1, color: textColor.withOpacity(0.1), indent: 16, endIndent: 16),
        
        // 剧集列表
        Expanded(
          child: _buildEpisodesListForSelectedSeason(),
        ),
      ],
    );
  }
  
  Widget _buildEpisodesListForSelectedSeason() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    if (_selectedSeasonId == null && _seasons.isNotEmpty) { // 如果有季但没有选择，提示选择
      return Center(
        child: Text('请选择一个季', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryTextColor)),
      );
    }
    if (_selectedSeasonId == null && _seasons.isEmpty && !_isLoading) { // 如果没有季且不在加载中
        return Center(
        child: Text('该剧集没有季节信息', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryTextColor)),
      );
    }
    
    if (_isLoading && (_episodesBySeasonId[_selectedSeasonId ?? ''] == null || _episodesBySeasonId[_selectedSeasonId ?? '']!.isEmpty)) {
      return Center(
        child: CircularProgressIndicator(color: textColor),
      );
    }
    
    if (_error != null && _selectedSeasonId != null) { // 仅在尝试加载特定季出错时显示
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('加载剧集失败: $_error', style: TextStyle(color: secondaryTextColor), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              BlurButton(
                icon: Icons.refresh,
                text: '重试',
                onTap: () => _loadEpisodesForSeason(_selectedSeasonId!),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                fontSize: 16,
              ),
            ],
          ),
        ),
      );
    }
    
    final episodes = _episodesBySeasonId[_selectedSeasonId] ?? [];
    
    if (episodes.isEmpty && !_isLoading && _selectedSeasonId != null) { // 确保不是在加载中，并且确实选择了季
      return Center(
        child: Text('该季没有剧集', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryTextColor)),
      );
    }
     if (episodes.isEmpty && _isLoading) { // 如果仍在加载，显示加载指示器
      return Center(child: CircularProgressIndicator(color: textColor));
    }
    if (episodes.isEmpty && _selectedSeasonId == null && _seasons.isEmpty) { // 处理没有季的情况
        return Center(child: Text('没有可显示的剧集', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: secondaryTextColor)));
    }


    dynamic service;
    if (widget.serverType == MediaServerType.jellyfin) {
      service = JellyfinService.instance;
    } else {
      service = EmbyService.instance;
    }
    
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final episode = episodes[index];
        final episodeImageUrl = episode.imagePrimaryTag != null
            ? _getEpisodeImageUrl(episode, service)
            : '';
        final bool playHoverEnabled =
            !_isDetailAutoMatching && !globals.isTouch;
        final bool isPlayHovered =
            playHoverEnabled && _hoveredEpisodeId == episode.id;
        final Color playIconColor = isPlayHovered
            ? const Color(0xFFFF2E55)
            : secondaryTextColor;
        
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          enabled: !_isDetailAutoMatching,
          leading: SizedBox(
            width: 100, // 调整图片宽度
            height: 60, // 调整图片高度，保持宽高比
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: episodeImageUrl.isNotEmpty
                  ? CachedNetworkImageWidget(
                      key: ValueKey(episode.id), // 为 CachedNetworkImageWidget 添加 Key
                      imageUrl: episodeImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error) {
                        return Container(
                          color: isDark ? Colors.grey[800] : Colors.grey[300],
                          child: Center(
                            child: Icon(
                              Ionicons.image_outline, // 使用 Ionicons
                              size: 24,
                              color: secondaryTextColor.withOpacity(0.5),
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: isDark ? Colors.grey[800] : Colors.grey[300],
                      child: Center(
                        child: Icon(
                          Ionicons.film_outline, // 使用 Ionicons
                          size: 24,
                          color: secondaryTextColor.withOpacity(0.5),
                        ),
                      ),
                    ),
            ),
          ),
          title: Text(
            episode.indexNumber != null
                ? '${episode.indexNumber}. ${episode.name}'
                : episode.name,
            style: TextStyle(
              fontWeight: FontWeight.w500, 
              color: textColor, // 关键：使用主题textColor
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (episode.runTimeTicks != null)
                Text(
                  _formatRuntime(episode.runTimeTicks),
                  locale: const Locale("zh-Hans", "zh"),
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
              if (episode.overview != null && episode.overview!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text(
                    episode.overview!
                        .replaceAll('<br>', ' ')
                        .replaceAll('<br/>', ' ')
                        .replaceAll('<br />', ' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    locale: const Locale("zh-Hans", "zh"),
                    style: TextStyle(fontSize: 12, color: secondaryTextColor),
                  ),
                ),
            ],
          ),
          trailing: MouseRegion(
            cursor: playHoverEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: playHoverEnabled
                ? (_) => setState(() => _hoveredEpisodeId = episode.id)
                : null,
            onExit: playHoverEnabled
                ? (_) {
                    if (_hoveredEpisodeId == episode.id) {
                      setState(() => _hoveredEpisodeId = null);
                    }
                  }
                : null,
            child: AnimatedScale(
              scale: isPlayHovered ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Icon(
                Ionicons.play_circle_outline,
                color: playIconColor,
                size: 22,
              ),
            ),
          ),
          onTap: () async {
            if (_isDetailAutoMatching) {
              BlurSnackBar.show(context, '正在自动匹配，请稍候');
              return;
            }
            try {
              BlurSnackBar.show(context, '准备播放: ${episode.name}');
              
              // 获取流媒体URL但暂不播放
              String streamUrl;
              if (widget.serverType == MediaServerType.jellyfin) {
                streamUrl = JellyfinDandanplayMatcher.instance.getPlayUrl(episode);
              } else {
                streamUrl = await EmbyDandanplayMatcher.instance.getPlayUrl(episode);
              }
              debugPrint('获取到流媒体URL: $streamUrl');
              
              // 显示加载指示器
              if (mounted) {
                BlurSnackBar.show(context, '正在匹配弹幕信息...');
              }
              
              // 使用JellyfinDandanplayMatcher创建增强的WatchHistoryItem
              // 这一步会显示匹配对话框，阻塞直到用户完成选择或跳过
              final historyItem = await _runDetailAutoMatchTask<WatchHistoryItem?>(() => _createWatchHistoryItem(episode));
              if (historyItem == null) return; // 用户关闭弹窗，什么都不做
              
              // 用户已完成匹配选择，现在可以继续播放流程
              debugPrint('成功获取历史记录项: ${historyItem.animeName} - ${historyItem.episodeTitle}, animeId=${historyItem.animeId}, episodeId=${historyItem.episodeId}');
              
              // 调试：检查 historyItem 的弹幕 ID
              if (historyItem.animeId == null || historyItem.episodeId == null) {
                debugPrint('警告: 从 JellyfinDandanplayMatcher 获得的 historyItem 缺少弹幕 ID');
                debugPrint('  animeId: ${historyItem.animeId}');
                debugPrint('  episodeId: ${historyItem.episodeId}');
              } else {
                debugPrint('确认: historyItem 包含有效的弹幕 ID');
                debugPrint('  animeId: ${historyItem.animeId}');
                debugPrint('  episodeId: ${historyItem.episodeId}');
              }
              
              // 获取必要的服务引用
              final videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
              
              // 在页面关闭前，获取TabChangeNotifier
              // 注意：通过listen: false方式获取，避免建立依赖关系
              TabChangeNotifier? tabChangeNotifier;
              try {
                tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
              } catch (e) {
                debugPrint('无法获取TabChangeNotifier: $e');
              }
              
              // *** 关键修改：立即切换页面和关闭详情页，像本地视频播放一样 ***
              // 1. 立即切换到播放页面，显示加载中
              if (tabChangeNotifier != null) {
                debugPrint('立即切换到播放页面');
                tabChangeNotifier.changeTab(1);
              }
              
              // 2. 立即关闭详情页面
              Navigator.of(context).pop();
              debugPrint('详情页面已立即关闭');
              
              // 3. 显示开始播放的提示（这个提示会在播放页面显示）
              if (mounted) {
                BlurSnackBar.show(context, '开始播放: ${historyItem.episodeTitle}');
              }
              
              // 创建一个专门用于流媒体播放的历史记录项，使用稳定的jellyfin://或emby://协议
              final playableHistoryItem = WatchHistoryItem(
                filePath: historyItem.filePath, // 保持稳定的jellyfin://或emby://协议URL
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
              
              // 4. 异步初始化播放器（页面已切换，用户能看到加载中）
              debugPrint('开始异步初始化播放器...');
              
              // 使用异步方式初始化播放器，不阻塞UI
              Future.delayed(const Duration(milliseconds: 100), () async {
                try {
                  debugPrint('异步初始化播放器 - 开始');
                  // 使用稳定的jellyfin://协议URL作为标识符，临时HTTP URL作为实际播放源
                  await videoPlayerState.initializePlayer(
                    historyItem.filePath, // 使用稳定的jellyfin://协议
                    historyItem: playableHistoryItem,
                    actualPlayUrl: streamUrl, // 临时HTTP流媒体URL仅用于播放
                  );
                  debugPrint('异步初始化播放器 - 完成');
                  
                  // 开始播放
                  debugPrint('异步播放 - 开始播放视频');
                  videoPlayerState.play();
                  debugPrint('异步播放 - 成功开始播放: ${playableHistoryItem.animeName} - ${playableHistoryItem.episodeTitle}');
                } catch (playError) {
                  debugPrint('异步播放流媒体时出错: $playError');
                  // 此时页面已关闭，无法显示错误提示，只记录日志
                }
              });
                        } catch (e) {
              BlurSnackBar.show(context, '播放出错: $e');
              debugPrint('播放Jellyfin媒体出错: $e');
            }
          },
        );
      },
    );
  }
}
