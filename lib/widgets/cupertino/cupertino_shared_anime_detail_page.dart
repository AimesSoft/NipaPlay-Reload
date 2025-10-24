import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/widgets/cupertino/cupertino_bottom_sheet.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/models/anime_detail_display_mode.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/widgets/nipaplay_theme/cached_network_image_widget.dart';

class CupertinoSharedAnimeDetailPage extends StatefulWidget {
  const CupertinoSharedAnimeDetailPage({
    super.key,
    required this.anime,
    this.hideBackButton = false,
    this.displayModeOverride,
    this.showCloseButton = true,
  });

  final SharedRemoteAnimeSummary anime;
  final bool hideBackButton;
  final AnimeDetailDisplayMode? displayModeOverride;
  final bool showCloseButton;

  @override
  State<CupertinoSharedAnimeDetailPage> createState() =>
      _CupertinoSharedAnimeDetailPageState();
}

class _CupertinoSharedAnimeDetailPageState
    extends State<CupertinoSharedAnimeDetailPage> {
  static const int _infoSegment = 0;
  static final Map<int, String> _coverCache = {};

  final ScrollController _scrollController = ScrollController();
  final DateFormat _timeFormatter = DateFormat('MM-dd HH:mm');

  int _currentSegment = _infoSegment;
  List<SharedRemoteEpisode>? _episodes;
  bool _isLoadingEpisodes = false;
  
  // Bangumi详细信息
  BangumiAnime? _bangumiAnime;
  bool _isLoadingBangumiAnime = false;
  String? _bangumiAnimeError;
  
  // 云端观看状态
  Map<int, bool> _episodeWatchStatus = {};
  bool _isLoadingWatchStatus = false;
  bool _isSynopsisExpanded = false;
  String? _vividCoverUrl;
  bool _isLoadingCover = false;

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
    final provider = context.read<SharedRemoteLibraryProvider>();
    setState(() {
      _isLoadingEpisodes = true;
    });

    try {
      final episodes = await provider.loadAnimeEpisodes(
        widget.anime.animeId,
        force: force,
      );
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
    });

    try {
      // 获取所有剧集的ID
      final episodeIds = bangumiAnime.episodeList!
          .map((episode) => episode.id)
          .toList();

      // 查询观看状态
      final watchStatus = await DandanplayService.getEpisodesWatchStatus(episodeIds);

      if (!mounted) return;
      setState(() {
        _episodeWatchStatus = watchStatus;
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
      });
    }
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

    coverUrl ??=
        _resolveImageUrl(context.read<SharedRemoteLibraryProvider>());

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
            final hostName = context
                .watch<SharedRemoteLibraryProvider>()
                .activeHost
                ?.displayName;
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

    final hostName = context
        .watch<SharedRemoteLibraryProvider>()
        .activeHost
        ?.displayName;

    return Stack(
      children: [
        CupertinoBottomSheetContentLayout(
          controller: _scrollController,
          backgroundColor: backgroundColor,
          floatingTitleOpacity: 0,
          sliversBuilder: (context, topSpacing) {
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
    final fallbackCover =
        _resolveImageUrl(context.read<SharedRemoteLibraryProvider>());
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
                          : CupertinoColors.white,
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
      child: AdaptiveSegmentedControl(
        labels: const ['详情', '剧集'],
        selectedIndex: _currentSegment,
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.white,
          context,
        ),
        onValueChanged: (index) {
          setState(() {
            _currentSegment = index;
          });
        },
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
        _resolveImageUrl(context.read<SharedRemoteLibraryProvider>());
    final cleanSummary = _cleanSummary;

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
            CupertinoColors.white,
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
    final provider = context.read<SharedRemoteLibraryProvider>();
    try {
      final playableItem =
          provider.buildPlayableItem(anime: widget.anime, episode: episode);
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      // 先关闭详情弹窗，避免横屏时页面残留导致的画面撕裂
      await rootNavigator.maybePop();
      await PlaybackService().play(playableItem);
    } catch (e) {
      BlurSnackBar.show(context, '播放失败：$e');
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

  String? _resolveImageUrl(SharedRemoteLibraryProvider provider) {
    final imageUrl = widget.anime.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return null;
    }
    if (imageUrl.startsWith('http')) {
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
  static const double _toolbarButtonSize = 36;
}
