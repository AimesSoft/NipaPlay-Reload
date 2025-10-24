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
import 'package:nipaplay/widgets/cupertino/cupertino_bottom_sheet.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';

class CupertinoSharedAnimeDetailPage extends StatefulWidget {
  const CupertinoSharedAnimeDetailPage({
    super.key,
    required this.anime,
  });

  final SharedRemoteAnimeSummary anime;

  @override
  State<CupertinoSharedAnimeDetailPage> createState() =>
      _CupertinoSharedAnimeDetailPageState();
}

class _CupertinoSharedAnimeDetailPageState
    extends State<CupertinoSharedAnimeDetailPage> {
  static const int _infoSegment = 0;

  final ScrollController _scrollController = ScrollController();
  final DateFormat _timeFormatter = DateFormat('MM-dd HH:mm');

  int _currentSegment = _infoSegment;
  List<SharedRemoteEpisode>? _episodes;
  bool _isLoadingEpisodes = false;

  // Bangumi详细信息
  BangumiAnime? _bangumiAnime;
  bool _isLoadingBangumiAnime = false;
  String? _bangumiAnimeError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadEpisodes();
      _loadBangumiAnime();
    });
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

  Future<void> _loadBangumiAnime() async {
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

  @override
  Widget build(BuildContext context) {
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
        Positioned(
          top: 0,
          left: 0,
          child: Padding(
            padding: EdgeInsets.all(_toolbarPadding),
            child: _buildBackButton(context),
          ),
        ),
      ],
    );
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

    // 获取完整的简介信息
    final summary = widget.anime.summary?.trim();
    final cleanSummary = summary
        ?.replaceAll('<br>', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll('<br />', '\n')
        .replaceAll('```', '');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: resolvedCardColor,
              borderRadius: BorderRadius.circular(20),
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

    return Image.network(
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
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
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
      ),
    );
  }

  Future<void> _playEpisode(SharedRemoteEpisode episode) async {
    final provider = context.read<SharedRemoteLibraryProvider>();
    try {
      final playableItem =
          provider.buildPlayableItem(anime: widget.anime, episode: episode);
      await PlaybackService().play(playableItem);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      if (!mounted) return;
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
