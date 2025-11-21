import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/emby_dandanplay_matcher.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_dandanplay_matcher.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart'
    show MediaServerType;
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';

class CupertinoMediaServerDetailPage extends StatefulWidget {
  const CupertinoMediaServerDetailPage({
    super.key,
    required this.mediaId,
    required this.serverType,
  });

  final String mediaId;
  final MediaServerType serverType;

  static Future<WatchHistoryItem?> showJellyfin(
    BuildContext context,
    String mediaId,
  ) {
    return _show(context, mediaId, MediaServerType.jellyfin);
  }

  static Future<WatchHistoryItem?> showEmby(
    BuildContext context,
    String mediaId,
  ) {
    return _show(context, mediaId, MediaServerType.emby);
  }

  static Future<WatchHistoryItem?> _show(
    BuildContext context,
    String mediaId,
    MediaServerType type,
  ) {
    return Navigator.of(context).push<WatchHistoryItem>(
      CupertinoPageRoute(
        builder: (_) => CupertinoMediaServerDetailPage(
          mediaId: mediaId,
          serverType: type,
        ),
      ),
    );
  }

  @override
  State<CupertinoMediaServerDetailPage> createState() =>
      _CupertinoMediaServerDetailPageState();
}

class _CupertinoMediaServerDetailPageState
    extends State<CupertinoMediaServerDetailPage> {
  static final Map<String, String> _videoHashes = {};
  static final Map<String, Map<String, dynamic>> _videoInfos = {};

  dynamic _mediaDetail;
  List<dynamic> _seasons = <dynamic>[];
  final Map<String, List<dynamic>> _episodesBySeasonId = {};
  String? _selectedSeasonId;
  bool _isLoading = true;
  String? _error;
  bool _isMovie = false;
  int _currentSegment = 0;

  @override
  void initState() {
    super.initState();
    _loadMediaDetail();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String? _getActorImageUrl(dynamic actor) {
    if (widget.serverType == MediaServerType.jellyfin) {
      if (actor.primaryImageTag != null) {
        final service = JellyfinService.instance;
        return service.getImageUrl(
          actor.id,
          type: 'Primary',
          width: 100,
          quality: 90,
        );
      }
    } else {
      if (actor.imagePrimaryTag != null && actor.id != null) {
        final service = EmbyService.instance;
        return service.getImageUrl(
          actor.id!,
          type: 'Primary',
          width: 100,
          height: 100,
          tag: actor.imagePrimaryTag,
        );
      }
    }
    return null;
  }

  String _getEpisodeImageUrl(dynamic episode, dynamic service) {
    if (widget.serverType == MediaServerType.jellyfin) {
      return service.getImageUrl(
        episode.id,
        type: 'Primary',
        width: 300,
        quality: 90,
      );
    }
    return service.getImageUrl(
      episode.id,
      type: 'Primary',
      width: 300,
      tag: episode.imagePrimaryTag,
    );
  }

  String _getPosterUrl() {
    if (_mediaDetail?.imagePrimaryTag == null) {
      return '';
    }

    if (widget.serverType == MediaServerType.jellyfin) {
      final service = JellyfinService.instance;
      return service.getImageUrl(
        _mediaDetail!.id,
        type: 'Primary',
        width: 300,
        quality: 95,
      );
    }

    final service = EmbyService.instance;
    return service.getImageUrl(
      _mediaDetail!.id,
      type: 'Primary',
      width: 300,
      tag: _mediaDetail!.imagePrimaryTag,
    );
  }

  Future<void> _loadMediaDetail() async {
    if (!mounted) {
      return;
    }

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

      if (!mounted) {
        return;
      }

      int defaultSegment = 0;
      try {
        final appearanceSettings =
            Provider.of<AppearanceSettingsProvider>(context, listen: false);
        defaultSegment =
            appearanceSettings.animeCardAction == AnimeCardAction.synopsis
                ? 0
                : 1;
      } catch (_) {
        defaultSegment = 0;
      }

      setState(() {
        _mediaDetail = detail;
        _isMovie = detail.type == 'Movie';
        _isLoading = false;
        _currentSegment = _isMovie ? 0 : defaultSegment;
      });

      if (_isMovie) {
        return;
      }

      dynamic seasons;
      if (widget.serverType == MediaServerType.jellyfin) {
        seasons =
            await (service as JellyfinService).getSeriesSeasons(widget.mediaId);
      } else {
        seasons = await (service as EmbyService).getSeasons(widget.mediaId);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _seasons = seasons;
        if (seasons.isNotEmpty) {
          _selectedSeasonId = seasons.first.id;
        }
      });

      if (_selectedSeasonId != null) {
        await _loadEpisodesForSeason(_selectedSeasonId!);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadEpisodesForSeason(String seasonId) async {
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
      if (_mediaDetail?.id == null) {
        setState(() {
          _error = '无法获取剧集详情，无法加载剧集列表。';
          _isLoading = false;
        });
        return;
      }

      dynamic episodes;
      if (widget.serverType == MediaServerType.jellyfin) {
        final service = JellyfinService.instance;
        episodes = await service.getSeasonEpisodes(
          _mediaDetail!.id,
          seasonId,
        );
      } else {
        final service = EmbyService.instance;
        episodes = await service.getSeasonEpisodes(
          _mediaDetail!.id,
          seasonId,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _episodesBySeasonId[seasonId] = episodes;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<WatchHistoryItem?> _createWatchHistoryItem(dynamic episode) async {
    try {
      dynamic matcher;
      if (widget.serverType == MediaServerType.jellyfin) {
        matcher = JellyfinDandanplayMatcher.instance;
      } else {
        matcher = EmbyDandanplayMatcher.instance;
      }

      unawaited(
        matcher
            .precomputeVideoInfoAndMatch(context, episode)
            .then((dynamic preMatchResult) {
          final String? videoHash = preMatchResult['videoHash'] as String?;
          final String? fileName = preMatchResult['fileName'] as String?;
          final int? fileSize = preMatchResult['fileSize'] as int?;

          if (videoHash != null && videoHash.isNotEmpty) {
            _videoHashes[episode.id] = videoHash;
            _videoInfos[episode.id] = <String, dynamic>{
              'hash': videoHash,
              'fileName': fileName ?? '',
              'fileSize': fileSize ?? 0,
            };
          }
        }).catchError((Object e) {
          debugPrint('预计算过程中出错: $e');
        }),
      );

      final playableItem = await matcher.createPlayableHistoryItem(
        context,
        episode,
      );

      if (playableItem != null) {
        if (_videoHashes.containsKey(episode.id)) {
          playableItem.videoHash = _videoHashes[episode.id];
        }
      }

      return playableItem;
    } catch (e) {
      debugPrint('创建可播放历史记录项失败: $e');
      return episode.toWatchHistoryItem();
    }
  }

  Future<void> _playMovie() async {
    if (_mediaDetail == null || !_isMovie) {
      return;
    }

    try {
      dynamic matcher;
      WatchHistoryItem? historyItem;
      String? streamUrl;

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
        matcher = JellyfinDandanplayMatcher.instance;
        historyItem = await matcher.createPlayableHistoryItemFromMovie(
            context, movieInfo);
        if (historyItem != null) {
          streamUrl = JellyfinService.instance.getStreamUrl(_mediaDetail!.id);
        }
      } else {
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
        matcher = EmbyDandanplayMatcher.instance;
        historyItem = await matcher.createPlayableHistoryItemFromMovie(
            context, movieInfo);
        if (historyItem != null) {
          streamUrl = await EmbyService.instance.getStreamUrl(_mediaDetail!.id);
        }
      }

      if (historyItem == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      // 创建 PlayableItem
      final playableItem = PlayableItem(
        videoPath: historyItem.filePath,
        title: historyItem.animeName,
        subtitle: historyItem.episodeTitle,
        animeId: historyItem.animeId,
        episodeId: historyItem.episodeId,
        historyItem: historyItem,
        actualPlayUrl: streamUrl,
      );

      // 先关闭详情页
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      await rootNavigator.maybePop();

      // 使用 PlaybackService 播放
      await PlaybackService().play(playableItem);
    } catch (e) {
      if (!mounted) {
        return;
      }
      AdaptiveSnackBar.show(
        context,
        message: '播放失败: $e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  String _formatRuntime(int? runTimeTicks) {
    if (runTimeTicks == null) {
      return '';
    }

    final durationInSeconds = runTimeTicks / 10000000;
    final hours = (durationInSeconds / 3600).floor();
    final minutes = ((durationInSeconds % 3600) / 60).floor();
    if (hours > 0) {
      return '$hours小时${minutes > 0 ? ' $minutes分钟' : ''}';
    }
    return '$minutes分钟';
  }

  @override
  Widget build(BuildContext context) {
    final title = _mediaDetail?.name ?? '详情';

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: title,
        useNativeToolbar: true,
      ),
      body: SafeArea(
        bottom: false,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _mediaDetail == null) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (_error != null && _mediaDetail == null) {
      return _buildErrorView();
    }

    if (_mediaDetail == null) {
      return const Center(child: Text('未找到媒体详情'));
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeroSection()),
        if (!_isMovie) SliverToBoxAdapter(child: _buildSegmentControl()),
        if (_isMovie)
          ..._buildInfoSlivers()
        else if (_currentSegment == 0)
          ..._buildInfoSlivers()
        else
          ..._buildEpisodeSlivers(),
        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.exclamationmark_octagon,
              size: 56, color: CupertinoColors.systemRed),
          const SizedBox(height: 16),
          Text(
            '加载详情失败',
            style: CupertinoTheme.of(context)
                .textTheme
                .navTitleTextStyle
                .copyWith(fontSize: 20),
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? '未知错误',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: CupertinoColors.systemGrey,
            ),
          ),
          const SizedBox(height: 24),
          AdaptiveButton.child(
            onPressed: _loadMediaDetail,
            style: AdaptiveButtonStyle.filled,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    final String? backdropUrl = _resolveBackdropUrl();
    final posterUrl = _getPosterUrl();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            SizedBox(
              height: 220,
              width: double.infinity,
              child: backdropUrl != null
                  ? CachedNetworkImageWidget(
                      imageUrl: backdropUrl,
                      fit: BoxFit.cover,
                    )
                  : Container(color: CupertinoColors.systemGrey5),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.05),
                      Colors.black.withOpacity(0.55),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              right: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 110,
                      height: 160,
                      child: posterUrl.isNotEmpty
                          ? CachedNetworkImageWidget(
                              imageUrl: posterUrl,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Colors.black26,
                              child: const Icon(
                                Ionicons.film_outline,
                                color: Colors.white60,
                                size: 40,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _buildHeroTextuals()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _resolveBackdropUrl() {
    if (_mediaDetail?.imageBackdropTag == null) {
      return null;
    }
    if (widget.serverType == MediaServerType.jellyfin) {
      final service = JellyfinService.instance;
      return service.getImageUrl(
        _mediaDetail!.id,
        type: 'Backdrop',
        width: 1920,
        height: 1080,
        quality: 95,
      );
    }
    final service = EmbyService.instance;
    return service.getImageUrl(
      _mediaDetail!.id,
      type: 'Backdrop',
      width: 1920,
      height: 1080,
      quality: 95,
      tag: _mediaDetail!.imageBackdropTag,
    );
  }

  Widget _buildHeroTextuals() {
    final primaryStyle = CupertinoTheme.of(context)
        .textTheme
        .navLargeTitleTextStyle
        .copyWith(color: Colors.white, fontSize: 26);
    final subtitleStyle = const TextStyle(
      color: Colors.white70,
      fontSize: 15,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _mediaDetail!.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: primaryStyle,
        ),
        if (_mediaDetail!.productionYear != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${_mediaDetail!.productionYear}',
              style: subtitleStyle,
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _mediaDetail!.genres.map<Widget>((dynamic genre) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                genre,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (_mediaDetail!.communityRating != null)
              Row(
                children: [
                  const Icon(CupertinoIcons.star_fill,
                      size: 14, color: Color(0xFFFFD166)),
                  const SizedBox(width: 4),
                  Text(
                    _mediaDetail!.communityRating!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            if (_mediaDetail!.officialRating != null) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _mediaDetail!.officialRating!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSegmentControl() {
    final Color segmentLabelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final Color segmentBackgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.tertiarySystemFill,
      context,
    );
    final Color segmentThumbColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemBackground,
      context,
    );
    final CupertinoThemeData baseTheme = CupertinoTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: CupertinoTheme(
        data: baseTheme.copyWith(
          textTheme: baseTheme.textTheme.copyWith(
            textStyle: baseTheme.textTheme.textStyle.copyWith(
              color: segmentLabelColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        child: CupertinoSlidingSegmentedControl<int>(
          backgroundColor: segmentBackgroundColor,
          thumbColor: segmentThumbColor,
          groupValue: _currentSegment,
          onValueChanged: (int? value) {
            if (value == null) {
              return;
            }
            setState(() {
              _currentSegment = value;
            });
          },
          children: <int, Widget>{
            0: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                '简介',
                style: TextStyle(color: segmentLabelColor),
              ),
            ),
            1: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                '剧集',
                style: TextStyle(color: segmentLabelColor),
              ),
            ),
          },
        ),
      ),
    );
  }

  List<Widget> _buildInfoSlivers() {
    final Color labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final Color secondaryColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final Color iconAccentColor = CupertinoDynamicColor.resolve(
      CupertinoColors.activeBlue,
      context,
    );
    final Color actorPlaceholderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey5,
      context,
    );
    final Color actorIconColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey,
      context,
    );

    final List<Widget> slivers = <Widget>[];

    if (_isMovie) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double buttonWidth = constraints.maxWidth * 0.8;
                return Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: buttonWidth,
                    height: 56,
                    child: AdaptiveButton.child(
                      onPressed: _playMovie,
                      style: AdaptiveButtonStyle.filled,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.play_fill,
                            size: 22,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.black,
                              context,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Play',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: CupertinoDynamicColor.resolve(
                                CupertinoColors.black,
                                context,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    if (_mediaDetail!.overview != null &&
        _mediaDetail!.overview!.trim().isNotEmpty) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Text(
              _mediaDetail!.overview!
                  .replaceAll('<br>', ' ')
                  .replaceAll('<br/>', ' ')
                  .replaceAll('<br />', ' '),
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: labelColor,
              ),
            ),
          ),
        ),
      );
    }

    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(
                icon: CupertinoIcons.time,
                label: '时长',
                value: _formatRuntime(_mediaDetail!.runTimeTicks),
                labelColor: secondaryColor,
                valueColor: labelColor,
                iconColor: iconAccentColor,
              ),
              if (_mediaDetail!.seriesStudio != null &&
                  _mediaDetail!.seriesStudio!.isNotEmpty)
                _buildInfoRow(
                  icon: CupertinoIcons.house_fill,
                  label: '工作室',
                  value: _mediaDetail!.seriesStudio!,
                  labelColor: secondaryColor,
                  valueColor: labelColor,
                  iconColor: iconAccentColor,
                ),
            ],
          ),
        ),
      ),
    );

    if (_mediaDetail!.cast.isNotEmpty) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 0, 0),
          sliver: SliverToBoxAdapter(
            child: Text(
              '演员',
              style: CupertinoTheme.of(context)
                  .textTheme
                  .navTitleTextStyle
                  .copyWith(fontSize: 18, color: labelColor),
            ),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: 120,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              scrollDirection: Axis.horizontal,
              itemCount: _mediaDetail!.cast.length,
              itemBuilder: (BuildContext _, int index) {
                final actor = _mediaDetail!.cast[index];
                final imageUrl = _getActorImageUrl(actor);
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: actorPlaceholderColor,
                        backgroundImage:
                            imageUrl != null ? NetworkImage(imageUrl) : null,
                        child: imageUrl == null
                            ? Icon(
                                CupertinoIcons.person_fill,
                                color: actorIconColor,
                              )
                            : null,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 72,
                        child: Text(
                          actor.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: labelColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? labelColor,
    Color? valueColor,
    Color? iconColor,
  }) {
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }
    final Color resolvedLabelColor = labelColor ??
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final Color resolvedValueColor = valueColor ??
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final Color resolvedIconColor = iconColor ??
        CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: resolvedIconColor),
          const SizedBox(width: 12),
          Text(
            '$label：',
            style: TextStyle(
              fontSize: 15,
              color: resolvedLabelColor,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                color: resolvedValueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEpisodeSlivers() {
    final Color labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final Color secondaryColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final Color activeColor = CupertinoDynamicColor.resolve(
      CupertinoColors.activeBlue,
      context,
    );
    final Color chipBackgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey5,
      context,
    );
    final Color episodeTileBackground = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final Color episodePlaceholderBackground = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey4,
      context,
    );

    if (_seasons.isEmpty) {
      return <Widget>[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          sliver: SliverToBoxAdapter(
            child: _isLoading
                ? const Center(child: CupertinoActivityIndicator())
                : const Text('该剧集没有季节信息'),
          ),
        ),
      ];
    }

    final episodes = _episodesBySeasonId[_selectedSeasonId] ?? <dynamic>[];

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: SizedBox(
          height: 40,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _seasons.length,
            itemBuilder: (BuildContext _, int index) {
              final season = _seasons[index];
              final bool selected = season.id == _selectedSeasonId;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => _loadEpisodesForSeason(season.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? activeColor
                          : chipBackgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      season.name,
                      style: TextStyle(
                        color: selected
                            ? CupertinoColors.white
                            : labelColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ];

    if (_error != null && episodes.isEmpty) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                Text(
                  '加载剧集失败: $_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CupertinoColors.systemGrey),
                ),
                const SizedBox(height: 16),
                AdaptiveButton.child(
                  onPressed: () {
                    final selected = _selectedSeasonId;
                    if (selected != null) {
                      unawaited(_loadEpisodesForSeason(selected));
                    }
                  },
                  style: AdaptiveButtonStyle.tinted,
                  child: const Text('重试加载'),
                ),
              ],
            ),
          ),
        ),
      );
      return slivers;
    }

    if (_isLoading && episodes.isEmpty) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ),
      );
      return slivers;
    }

    if (episodes.isEmpty) {
      slivers.add(
        const SliverPadding(
          padding: EdgeInsets.symmetric(vertical: 32),
          sliver: SliverToBoxAdapter(
            child: Center(child: Text('该季没有剧集')),
          ),
        ),
      );
      return slivers;
    }

    dynamic service;
    if (widget.serverType == MediaServerType.jellyfin) {
      service = JellyfinService.instance;
    } else {
      service = EmbyService.instance;
    }

    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              final episode = episodes[index];
              final imageUrl = episode.imagePrimaryTag != null
                  ? _getEpisodeImageUrl(episode, service)
                  : '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildEpisodeTile(
                  episode,
                  imageUrl,
                  backgroundColor: episodeTileBackground,
                  titleColor: labelColor,
                  subtitleColor: secondaryColor,
                  runtimeColor: secondaryColor,
                  placeholderColor: episodePlaceholderBackground,
                  iconColor: activeColor,
                ),
              );
            },
            childCount: episodes.length,
          ),
        ),
      ),
    );

    return slivers;
  }

  Widget _buildEpisodeTile(
    dynamic episode,
    String imageUrl, {
    required Color backgroundColor,
    required Color titleColor,
    required Color subtitleColor,
    required Color runtimeColor,
    required Color placeholderColor,
    required Color iconColor,
  }) {
    final title = episode.indexNumber != null
        ? '${episode.indexNumber}. ${episode.name}'
        : episode.name;
    final subtitle =
        episode.overview != null && episode.overview!.trim().isNotEmpty
            ? episode.overview!
                .replaceAll('<br>', ' ')
                .replaceAll('<br/>', ' ')
                .replaceAll('<br />', ' ')
            : null;

    return GestureDetector(
      onTap: () => _playEpisode(episode),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 120,
                height: 72,
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImageWidget(
                        key: ValueKey<String>('episode_${episode.id}'),
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: placeholderColor,
                        child: const Icon(
                          Ionicons.film_outline,
                          color: CupertinoColors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  if (episode.runTimeTicks != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _formatRuntime(episode.runTimeTicks),
                        style: TextStyle(
                          fontSize: 12,
                          color: runtimeColor,
                        ),
                      ),
                    ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: subtitleColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              CupertinoIcons.play_circle,
              color: iconColor,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playEpisode(dynamic episode) async {
    try {
      AdaptiveSnackBar.show(
        context,
        message: '准备播放: ${episode.name}',
        type: AdaptiveSnackBarType.info,
      );

      String streamUrl;
      if (widget.serverType == MediaServerType.jellyfin) {
        streamUrl = JellyfinDandanplayMatcher.instance.getPlayUrl(episode);
      } else {
        streamUrl = await EmbyDandanplayMatcher.instance.getPlayUrl(episode);
      }

      AdaptiveSnackBar.show(
        context,
        message: '正在匹配弹幕信息...',
        type: AdaptiveSnackBarType.info,
      );

      final historyItem = await _createWatchHistoryItem(episode);
      if (historyItem == null) {
        return;
      }

      // 创建 PlayableItem
      final playableItem = PlayableItem(
        videoPath: historyItem.filePath,
        title: historyItem.animeName,
        subtitle: historyItem.episodeTitle,
        animeId: historyItem.animeId,
        episodeId: historyItem.episodeId,
        historyItem: historyItem,
        actualPlayUrl: streamUrl,
      );

      // 先关闭详情页
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      await rootNavigator.maybePop();

      // 使用 PlaybackService 播放
      await PlaybackService().play(playableItem);
    } catch (e) {
      AdaptiveSnackBar.show(
        context,
        message: '播放出错: $e',
        type: AdaptiveSnackBarType.error,
      );
    }
  }
}
