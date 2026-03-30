import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/themes/steamdeck/models/big_screen_anime_series.dart';
import 'package:nipaplay/themes/steamdeck/navigation/big_screen_directional_controller.dart';
import 'package:nipaplay/themes/steamdeck/services/big_screen_playback_helper.dart';
import 'package:nipaplay/themes/steamdeck/widgets/big_screen_media_widgets.dart';
import 'package:nipaplay/utils/media_source_utils.dart';

class BigScreenAnimeDetailPage extends StatefulWidget {
  const BigScreenAnimeDetailPage({
    super.key,
    required this.series,
    required this.persistedCoverUrls,
  });

  final BigScreenAnimeSeries series;
  final Map<int, String> persistedCoverUrls;

  @override
  State<BigScreenAnimeDetailPage> createState() =>
      _BigScreenAnimeDetailPageState();
}

class _BigScreenAnimeDetailPageState extends State<BigScreenAnimeDetailPage> {
  static const Color _focusColor = Color(0xFFFF2E55);

  final FocusNode _focusNode = FocusNode(debugLabel: 'steamdeck_detail_focus');
  final ScrollController _episodeScrollController = ScrollController();
  late final BigScreenDirectionalController _directionalController;

  late final List<WatchHistoryItem> _historyEpisodes;
  List<_EpisodeDisplayItem> _displayEpisodes = const [];

  BangumiAnime? _animeDetail;
  bool _isLoadingDetail = false;

  String _summaryText = '暂无简介';
  String _coverPath = '';
  double _episodeItemExtent = 280;

  @override
  void initState() {
    super.initState();
    _directionalController = BigScreenDirectionalController(sectionCount: 2);
    _historyEpisodes = _buildEpisodeList(widget.series.episodes);
    _displayEpisodes = _buildDisplayEpisodes();
    _coverPath = _resolveInitialCover();

    _directionalController.setSelectedIndex(1, 0);
    _directionalController.clampToSectionLengths([1, _displayEpisodes.length]);

    unawaited(_loadAnimeDetail());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _episodeScrollController.dispose();
    super.dispose();
  }

  List<WatchHistoryItem> _buildEpisodeList(List<WatchHistoryItem> source) {
    final episodes = List<WatchHistoryItem>.from(source);
    episodes.sort((a, b) {
      final aEpisodeId = a.episodeId;
      final bEpisodeId = b.episodeId;

      if (aEpisodeId != null &&
          bEpisodeId != null &&
          aEpisodeId != bEpisodeId) {
        return aEpisodeId.compareTo(bEpisodeId);
      }
      return b.lastWatchTime.compareTo(a.lastWatchTime);
    });
    return episodes;
  }

  String _resolveInitialCover() {
    final seriesCover = _sanitizeImagePath(widget.series.coverPath);
    if (seriesCover.isNotEmpty) {
      return seriesCover;
    }

    final animeId = widget.series.animeId;
    if (animeId != null && animeId > 0) {
      final coverFromPrefs =
          _sanitizeImagePath(widget.persistedCoverUrls[animeId] ?? '');
      if (coverFromPrefs.isNotEmpty) {
        return coverFromPrefs;
      }
    }

    if (_historyEpisodes.isNotEmpty) {
      return _sanitizeImagePath(_historyEpisodes.first.thumbnailPath ?? '');
    }

    return '';
  }

  Future<void> _loadAnimeDetail() async {
    final animeId = widget.series.animeId;
    if (animeId == null || animeId <= 0) {
      return;
    }

    final cachedDetail =
        BangumiService.instance.getAnimeDetailsFromMemory(animeId);
    if (cachedDetail != null && mounted) {
      _applyDetail(cachedDetail);
    }

    setState(() {
      _isLoadingDetail = true;
    });

    try {
      final detail = await BangumiService.instance.getAnimeDetails(animeId);
      if (!mounted) {
        return;
      }
      _applyDetail(detail);
    } catch (_) {
      // 保持现有信息，不弹错误，避免影响大屏幕操作流畅性。
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDetail = false;
        });
      }
    }
  }

  void _applyDetail(BangumiAnime detail) {
    final summary = detail.summary?.trim() ?? '';
    final detailCover = _sanitizeImagePath(detail.imageUrl);

    setState(() {
      _animeDetail = detail;
      _displayEpisodes = _buildDisplayEpisodes(detail: detail);
      if (summary.isNotEmpty) {
        _summaryText = summary;
      }
      if (detailCover.isNotEmpty) {
        _coverPath = detailCover;
      }
    });

    _directionalController.clampToSectionLengths([1, _displayEpisodes.length]);
  }

  String _sanitizeImagePath(String rawPath) {
    return rawPath.trim();
  }

  String _resolveSeriesTitle() {
    if (_animeDetail != null) {
      final cn = _animeDetail!.nameCn.trim();
      if (cn.isNotEmpty) {
        return cn;
      }
      final name = _animeDetail!.name.trim();
      if (name.isNotEmpty) {
        return name;
      }
    }
    return widget.series.title;
  }

  List<_EpisodeDisplayItem> _buildDisplayEpisodes({BangumiAnime? detail}) {
    final detailToUse = detail ?? _animeDetail;
    final detailEpisodes = detailToUse?.episodeList;

    if (detailEpisodes == null || detailEpisodes.isEmpty) {
      return _historyEpisodes
          .map(
            (item) => _EpisodeDisplayItem(
              episodeId: item.episodeId ?? 0,
              title: _resolveHistoryEpisodeTitle(item),
              historyItem: item,
              isPlayable: _isHistoryPlayable(item),
            ),
          )
          .toList();
    }

    final historyByEpisodeId = <int, WatchHistoryItem>{};
    final historyByTitle = <String, WatchHistoryItem>{};
    for (final item in _historyEpisodes) {
      final episodeId = item.episodeId;
      if (episodeId != null && episodeId > 0) {
        historyByEpisodeId.putIfAbsent(episodeId, () => item);
      }
      final normalizedTitle = _normalizeTitle(item.episodeTitle ?? '');
      if (normalizedTitle.isNotEmpty) {
        historyByTitle.putIfAbsent(normalizedTitle, () => item);
      }
    }

    final usedHistoryKeys = <String>{};
    final result = <_EpisodeDisplayItem>[];

    for (final episode in detailEpisodes) {
      final byId = episode.id > 0 ? historyByEpisodeId[episode.id] : null;
      final byTitle = historyByTitle[_normalizeTitle(episode.title)];
      final historyItem = byId ?? byTitle;

      if (historyItem != null) {
        usedHistoryKeys.add(_historyKey(historyItem));
      }

      result.add(
        _EpisodeDisplayItem(
          episodeId: episode.id,
          title: episode.title.trim().isNotEmpty
              ? episode.title.trim()
              : '第${result.length + 1}集',
          historyItem: historyItem,
          isPlayable: historyItem != null && _isHistoryPlayable(historyItem),
        ),
      );
    }

    for (final historyItem in _historyEpisodes) {
      final key = _historyKey(historyItem);
      if (usedHistoryKeys.contains(key)) {
        continue;
      }

      result.add(
        _EpisodeDisplayItem(
          episodeId: historyItem.episodeId ?? 0,
          title: _resolveHistoryEpisodeTitle(historyItem),
          historyItem: historyItem,
          isPlayable: _isHistoryPlayable(historyItem),
        ),
      );
    }

    return result;
  }

  String _resolveHistoryEpisodeTitle(WatchHistoryItem item) {
    final title = item.episodeTitle?.trim() ?? '';
    if (title.isNotEmpty) {
      return title;
    }
    return item.animeName.trim().isNotEmpty ? item.animeName.trim() : '未知剧集';
  }

  String _normalizeTitle(String title) {
    return title.trim().toLowerCase();
  }

  String _historyKey(WatchHistoryItem item) {
    return '${item.episodeId ?? 0}_${item.filePath}_${item.lastWatchTime.millisecondsSinceEpoch}';
  }

  bool _isHistoryPlayable(WatchHistoryItem item) {
    final filePath = item.filePath.trim();
    if (filePath.isEmpty) {
      return false;
    }

    final lowerPath = filePath.toLowerCase();
    if (item.isDandanplayRemote ||
        lowerPath.startsWith('http://') ||
        lowerPath.startsWith('https://') ||
        lowerPath.startsWith('jellyfin://') ||
        lowerPath.startsWith('emby://') ||
        MediaSourceUtils.isWebDavPath(filePath) ||
        MediaSourceUtils.isSmbPath(filePath)) {
      return true;
    }

    if (kIsWeb) {
      return true;
    }

    try {
      return File(filePath).existsSync();
    } catch (_) {
      return false;
    }
  }

  WatchHistoryItem? _defaultPlayItem() {
    final latest = widget.series.latestEpisode;
    if (latest != null && _isHistoryPlayable(latest)) {
      return latest;
    }

    for (final entry in _displayEpisodes) {
      if (entry.isPlayable && entry.historyItem != null) {
        return entry.historyItem;
      }
    }
    return null;
  }

  String _fallbackCoverForEpisode(WatchHistoryItem item) {
    final animeId = item.animeId;
    if (animeId != null && animeId > 0) {
      final cover =
          _sanitizeImagePath(widget.persistedCoverUrls[animeId] ?? '');
      if (cover.isNotEmpty) {
        return cover;
      }
    }
    return _coverPath;
  }

  Future<void> _playDefaultEpisode() async {
    final item = _defaultPlayItem();
    if (item == null) {
      return;
    }
    final played = await BigScreenPlaybackHelper.playFromHistory(context, item);
    if (!played || !mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.maybePop();
  }

  Future<void> _playEpisodeEntry(_EpisodeDisplayItem entry) async {
    if (!entry.isPlayable || entry.historyItem == null) {
      return;
    }

    final played = await BigScreenPlaybackHelper.playFromHistory(
      context,
      entry.historyItem!,
    );
    if (!played || !mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.maybePop();
  }

  Future<void> _playFocusedEpisode() async {
    if (_displayEpisodes.isEmpty) {
      return;
    }

    final index = _directionalController
        .selectedIndex(1)
        .clamp(0, _displayEpisodes.length - 1);
    final entry = _displayEpisodes[index];
    await _playEpisodeEntry(entry);
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_directionalController.activeSection == 0) {
        unawaited(_playDefaultEpisode());
      } else {
        unawaited(_playFocusedEpisode());
      }
      return KeyEventResult.handled;
    }

    final moved = _directionalController.handleArrow(
      key,
      [1, _displayEpisodes.length],
    );
    if (!moved) {
      return KeyEventResult.ignored;
    }

    setState(() {});
    _scheduleEpisodeScrollSync();
    return KeyEventResult.handled;
  }

  void _scheduleEpisodeScrollSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_episodeScrollController.hasClients) {
        return;
      }

      final index = _directionalController.selectedIndex(1);
      final maxOffset = _episodeScrollController.position.maxScrollExtent;
      final target = (index * _episodeItemExtent).clamp(0.0, maxOffset);
      _episodeScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _directionalController.clampToSectionLengths([1, _displayEpisodes.length]);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  constraints.maxWidth >= 1200 ? 30.0 : 18.0;

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  14,
                  horizontalPadding,
                  14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 14),
                    Expanded(
                      flex: 11,
                      child: _buildTopSection(context),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      flex: 9,
                      child: _buildEpisodeSection(context),
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

  Widget _buildHeader(BuildContext context) {
    final title = _resolveSeriesTitle();
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
        ),
        const Spacer(),
        Text(
          '上下切换区域 · 左右选择剧集 · Enter确认 · Esc返回',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildTopSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final posterHeight = constraints.maxHeight.clamp(180.0, 420.0);
        final posterWidth = (posterHeight * 2 / 3).clamp(140.0, 280.0);

        final summaryText = _isLoadingDetail && _summaryText == '暂无简介'
            ? '正在加载简介...'
            : _summaryText;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: posterWidth,
              height: posterHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: BigScreenMediaImage(imagePath: _coverPath),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _resolveSeriesTitle(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.45),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          summaryText,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: _PlayButton(
                      isSelected: _directionalController.activeSection == 0,
                      onTap: _playDefaultEpisode,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEpisodeSection(BuildContext context) {
    final animeTitle = _resolveSeriesTitle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: _directionalController.activeSection == 1
                    ? _focusColor
                    : Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '剧集',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _directionalController.activeSection == 1
                        ? _focusColor
                        : Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const textAreaHeight = 78.0;
              final imageHeight =
                  (constraints.maxHeight - textAreaHeight).clamp(100.0, 200.0);
              final cardWidth = (imageHeight * 16 / 9).clamp(190.0, 340.0);
              const spacing = 14.0;

              _episodeItemExtent = cardWidth + spacing;

              if (_displayEpisodes.isEmpty) {
                return _buildEmptyEpisodes(context);
              }

              return ListView.builder(
                controller: _episodeScrollController,
                scrollDirection: Axis.horizontal,
                itemCount: _displayEpisodes.length,
                itemBuilder: (context, index) {
                  final entry = _displayEpisodes[index];
                  final isSelected =
                      _directionalController.activeSection == 1 &&
                          _directionalController.selectedIndex(1) == index;
                  final fallbackCoverPath = entry.historyItem != null
                      ? _fallbackCoverForEpisode(entry.historyItem!)
                      : _coverPath;

                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == _displayEpisodes.length - 1 ? 0 : spacing,
                    ),
                    child: _EpisodeCard(
                      entry: entry,
                      width: cardWidth,
                      imageHeight: imageHeight,
                      isSelected: isSelected,
                      fallbackCoverPath: fallbackCoverPath,
                      animeTitle: animeTitle,
                      onTap: entry.isPlayable
                          ? () => unawaited(_playEpisodeEntry(entry))
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyEpisodes(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '暂无剧集信息',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.isSelected, required this.onTap});

  final bool isSelected;
  final Future<void> Function() onTap;

  static const Color _focusColor = Color(0xFFFF2E55);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => unawaited(onTap()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isSelected ? _focusColor : colorScheme.surfaceContainerHigh,
          border: Border.all(
            color: isSelected ? _focusColor : colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow_rounded,
              color: isSelected ? Colors.white : colorScheme.onSurface,
              size: 24,
            ),
            const SizedBox(width: 6),
            Text(
              '播放',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isSelected ? Colors.white : colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.entry,
    required this.width,
    required this.imageHeight,
    required this.isSelected,
    required this.fallbackCoverPath,
    required this.animeTitle,
    required this.onTap,
  });

  final _EpisodeDisplayItem entry;
  final double width;
  final double imageHeight;
  final bool isSelected;
  final String fallbackCoverPath;
  final String animeTitle;
  final VoidCallback? onTap;

  static const Color _focusColor = Color(0xFFFF2E55);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progressText = '${(entry.progress * 100).clamp(0, 100).toInt()}%';
    final subtitleText =
        entry.isPlayable ? '$progressText · $animeTitle' : '未入库 · $animeTitle';

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: width,
              height: imageHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? _focusColor : Colors.transparent,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: entry.isPlayable ? 1.0 : 0.62,
                    child: entry.historyItem != null
                        ? BigScreenHistoryThumbnail(
                            item: entry.historyItem!,
                            fallbackCoverPath: fallbackCoverPath,
                          )
                        : BigScreenMediaImage(
                            imagePath: fallbackCoverPath,
                            fit: BoxFit.cover,
                            fallbackIcon: Icons.videocam_outlined,
                          ),
                  ),
                  if (!entry.isPlayable)
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: entry.isPlayable
                        ? colorScheme.onSurface
                        : colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: entry.isPlayable
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 3,
              width: width,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: colorScheme.onSurface.withValues(alpha: 0.14),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: entry.progress,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: entry.isPlayable
                        ? _focusColor
                        : colorScheme.outlineVariant.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeDisplayItem {
  const _EpisodeDisplayItem({
    required this.episodeId,
    required this.title,
    required this.historyItem,
    required this.isPlayable,
  });

  final int episodeId;
  final String title;
  final WatchHistoryItem? historyItem;
  final bool isPlayable;

  double get progress {
    final value = historyItem?.watchProgress ?? 0.0;
    return value.clamp(0.0, 1.0).toDouble();
  }
}
