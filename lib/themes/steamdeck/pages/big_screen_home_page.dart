import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/themes/steamdeck/models/big_screen_anime_series.dart';
import 'package:nipaplay/themes/steamdeck/navigation/big_screen_directional_controller.dart';
import 'package:nipaplay/themes/steamdeck/pages/big_screen_anime_detail_page.dart';
import 'package:nipaplay/themes/steamdeck/services/big_screen_playback_helper.dart';
import 'package:nipaplay/themes/steamdeck/widgets/big_screen_media_widgets.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SteamDeckBigScreenPage extends StatefulWidget {
  const SteamDeckBigScreenPage({super.key});

  @override
  State<SteamDeckBigScreenPage> createState() => _SteamDeckBigScreenPageState();
}

class _SteamDeckBigScreenPageState extends State<SteamDeckBigScreenPage> {
  static const Color _focusColor = Color(0xFFFF2E55);
  static const String _coverPrefsKeyPrefix = 'media_library_image_url_';

  final FocusNode _focusNode = FocusNode(debugLabel: 'steamdeck_home_focus');
  final ScrollController _libraryScrollController = ScrollController();
  final ScrollController _recentScrollController = ScrollController();

  late final BigScreenDirectionalController _directionalController;
  Map<int, String> _persistedCoverUrls = const {};

  double _libraryItemExtent = 220;
  double _recentItemExtent = 280;

  @override
  void initState() {
    super.initState();
    _directionalController = BigScreenDirectionalController(sectionCount: 2);
    unawaited(_loadPersistedCovers());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
      final historyProvider = context.read<WatchHistoryProvider>();
      if (!historyProvider.isLoaded && !historyProvider.isLoading) {
        unawaited(historyProvider.loadHistory());
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _libraryScrollController.dispose();
    _recentScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPersistedCovers() async {
    final prefs = await SharedPreferences.getInstance();
    final coverMap = <int, String>{};

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_coverPrefsKeyPrefix)) {
        continue;
      }
      final idText = key.substring(_coverPrefsKeyPrefix.length);
      final animeId = int.tryParse(idText);
      final url = prefs.getString(key);
      if (animeId == null || url == null || url.trim().isEmpty) {
        continue;
      }
      coverMap[animeId] = url;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _persistedCoverUrls = coverMap;
    });
  }

  List<BigScreenAnimeSeries> _buildAnimeSeries(
    List<WatchHistoryItem> history,
  ) {
    if (history.isEmpty) {
      return const [];
    }

    final grouped = <String, List<WatchHistoryItem>>{};
    for (final item in history) {
      final key = _resolveSeriesKey(item);
      grouped.putIfAbsent(key, () => <WatchHistoryItem>[]).add(item);
    }

    final series = <BigScreenAnimeSeries>[];
    for (final entry in grouped.entries) {
      final episodes = List<WatchHistoryItem>.from(entry.value)
        ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));

      final latest = episodes.first;
      final title = latest.animeName.trim().isNotEmpty
          ? latest.animeName.trim()
          : path.basenameWithoutExtension(latest.filePath);

      series.add(
        BigScreenAnimeSeries(
          key: entry.key,
          animeId: latest.animeId,
          title: title,
          coverPath: _resolveSeriesCover(episodes, latest.animeId),
          episodes: episodes,
        ),
      );
    }

    series.sort((a, b) {
      final aTime = a.latestEpisode?.lastWatchTime;
      final bTime = b.latestEpisode?.lastWatchTime;
      if (aTime == null && bTime == null) {
        return 0;
      }
      if (aTime == null) {
        return 1;
      }
      if (bTime == null) {
        return -1;
      }
      return bTime.compareTo(aTime);
    });

    return series;
  }

  String _resolveSeriesKey(WatchHistoryItem item) {
    if (item.animeId != null && item.animeId! > 0) {
      return 'anime:${item.animeId}';
    }

    final normalizedName = item.animeName.trim().toLowerCase();
    if (normalizedName.isNotEmpty) {
      return 'name:$normalizedName';
    }

    return 'file:${path.basenameWithoutExtension(item.filePath).toLowerCase()}';
  }

  String _resolveSeriesCover(List<WatchHistoryItem> episodes, int? animeId) {
    if (animeId != null && animeId > 0) {
      final persisted = _persistedCoverUrls[animeId] ?? '';
      if (_isUsableImagePath(persisted)) {
        return persisted;
      }
    }

    for (final episode in episodes) {
      final thumbnail = episode.thumbnailPath?.trim() ?? '';
      if (_isUsableImagePath(thumbnail)) {
        return thumbnail;
      }
    }
    return '';
  }

  String _resolveFallbackCoverForHistory(WatchHistoryItem item) {
    if (item.animeId != null && item.animeId! > 0) {
      final persisted = _persistedCoverUrls[item.animeId!] ?? '';
      if (_isUsableImagePath(persisted)) {
        return persisted;
      }
    }
    final thumbnail = item.thumbnailPath?.trim() ?? '';
    if (_isUsableImagePath(thumbnail)) {
      return thumbnail;
    }
    return '';
  }

  bool _isUsableImagePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final lowerPath = trimmed.toLowerCase();
    if (lowerPath.startsWith('http://') || lowerPath.startsWith('https://')) {
      return true;
    }
    if (trimmed.startsWith('assets/')) {
      return true;
    }
    if (kIsWeb) {
      return false;
    }
    try {
      return File(trimmed).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> _activateSelection({
    required List<BigScreenAnimeSeries> animeSeries,
    required List<WatchHistoryItem> continueWatching,
  }) async {
    final activeSection = _directionalController.activeSection;

    if (activeSection == 0) {
      if (animeSeries.isEmpty) {
        return;
      }
      final index = _directionalController.selectedIndex(0);
      final selected = animeSeries[index.clamp(0, animeSeries.length - 1)];
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BigScreenAnimeDetailPage(
            series: selected,
            persistedCoverUrls: _persistedCoverUrls,
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
      return;
    }

    if (continueWatching.isEmpty) {
      return;
    }

    final index = _directionalController.selectedIndex(1);
    final selected =
        continueWatching[index.clamp(0, continueWatching.length - 1)];
    await BigScreenPlaybackHelper.playFromHistory(context, selected);
  }

  KeyEventResult _handleKeyEvent(
    KeyEvent event, {
    required List<BigScreenAnimeSeries> animeSeries,
    required List<WatchHistoryItem> continueWatching,
  }) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      unawaited(
        _activateSelection(
          animeSeries: animeSeries,
          continueWatching: continueWatching,
        ),
      );
      return KeyEventResult.handled;
    }

    final moved = _directionalController.handleArrow(
      key,
      [animeSeries.length, continueWatching.length],
    );
    if (!moved) {
      return KeyEventResult.ignored;
    }

    setState(() {});
    _scheduleScrollSync();
    return KeyEventResult.handled;
  }

  void _scheduleScrollSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scrollToIndex(
        controller: _libraryScrollController,
        index: _directionalController.selectedIndex(0),
        itemExtent: _libraryItemExtent,
      );
      _scrollToIndex(
        controller: _recentScrollController,
        index: _directionalController.selectedIndex(1),
        itemExtent: _recentItemExtent,
      );
    });
  }

  void _scrollToIndex({
    required ScrollController controller,
    required int index,
    required double itemExtent,
  }) {
    if (!controller.hasClients || itemExtent <= 0) {
      return;
    }

    final maxOffset = controller.position.maxScrollExtent;
    final target = (index * itemExtent).clamp(0.0, maxOffset);
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, _) {
        final animeSeries = _buildAnimeSeries(historyProvider.history);
        final continueWatching = historyProvider.continueWatchingItems;

        _directionalController.clampToSectionLengths(
          [animeSeries.length, continueWatching.length],
        );

        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (node, event) => _handleKeyEvent(
            event,
            animeSeries: animeSeries,
            continueWatching: continueWatching,
          ),
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
                          child: _buildLibrarySection(animeSeries),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          flex: 9,
                          child: _buildContinueSection(continueWatching),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Text(
          '大屏幕模式',
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        Text(
          '方向键移动 · Enter确认 · Esc返回',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildLibrarySection(List<BigScreenAnimeSeries> animeSeries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          title: '媒体库',
          isActive: _directionalController.activeSection == 0,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const textAreaHeight = 86.0;
              final imageHeight =
                  (constraints.maxHeight - textAreaHeight).clamp(120.0, 320.0);
              final cardWidth = (imageHeight * 2 / 3).clamp(120.0, 220.0);
              const spacing = 14.0;

              _libraryItemExtent = cardWidth + spacing;

              if (animeSeries.isEmpty) {
                return _buildEmptySection('暂无番剧卡片');
              }

              return ListView.builder(
                controller: _libraryScrollController,
                scrollDirection: Axis.horizontal,
                itemCount: animeSeries.length,
                itemBuilder: (context, index) {
                  final series = animeSeries[index];
                  final isSelected =
                      _directionalController.activeSection == 0 &&
                          _directionalController.selectedIndex(0) == index;

                  return Padding(
                    padding: EdgeInsets.only(
                        right: index == animeSeries.length - 1 ? 0 : spacing),
                    child: _AnimeLibraryCard(
                      series: series,
                      width: cardWidth,
                      imageHeight: imageHeight,
                      isSelected: isSelected,
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

  Widget _buildContinueSection(List<WatchHistoryItem> continueWatching) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          title: '最近观看',
          isActive: _directionalController.activeSection == 1,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const textAreaHeight = 86.0;
              final imageHeight =
                  (constraints.maxHeight - textAreaHeight).clamp(100.0, 200.0);
              final cardWidth = (imageHeight * 16 / 9).clamp(190.0, 340.0);
              const spacing = 14.0;

              _recentItemExtent = cardWidth + spacing;

              if (continueWatching.isEmpty) {
                return _buildEmptySection('暂无观看记录');
              }

              return ListView.builder(
                controller: _recentScrollController,
                scrollDirection: Axis.horizontal,
                itemCount: continueWatching.length,
                itemBuilder: (context, index) {
                  final item = continueWatching[index];
                  final isSelected =
                      _directionalController.activeSection == 1 &&
                          _directionalController.selectedIndex(1) == index;

                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == continueWatching.length - 1 ? 0 : spacing,
                    ),
                    child: _ContinueWatchingCard(
                      item: item,
                      width: cardWidth,
                      imageHeight: imageHeight,
                      isSelected: isSelected,
                      fallbackCoverPath: _resolveFallbackCoverForHistory(item),
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

  Widget _buildSectionTitle({required String title, required bool isActive}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: isActive ? _focusColor : colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isActive ? _focusColor : colorScheme.onSurface,
              ),
        ),
      ],
    );
  }

  Widget _buildEmptySection(String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _AnimeLibraryCard extends StatelessWidget {
  const _AnimeLibraryCard({
    required this.series,
    required this.width,
    required this.imageHeight,
    required this.isSelected,
  });

  final BigScreenAnimeSeries series;
  final double width;
  final double imageHeight;
  final bool isSelected;

  static const Color _focusColor = Color(0xFFFF2E55);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final latestEpisode = series.latestEpisode;
    final subtitle = latestEpisode?.episodeTitle?.trim() ?? '';

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: width,
            height: imageHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
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
            child: BigScreenMediaImage(imagePath: series.coverPath),
          ),
          const SizedBox(height: 8),
          Text(
            series.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
    required this.item,
    required this.width,
    required this.imageHeight,
    required this.isSelected,
    required this.fallbackCoverPath,
  });

  final WatchHistoryItem item;
  final double width;
  final double imageHeight;
  final bool isSelected;
  final String fallbackCoverPath;

  static const Color _focusColor = Color(0xFFFF2E55);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final animeTitle = item.animeName.trim().isNotEmpty
        ? item.animeName.trim()
        : path.basename(item.filePath);
    final progressText = '${(item.watchProgress * 100).clamp(0, 100).toInt()}%';
    final episodeTitle = item.episodeTitle?.trim() ?? '';

    return SizedBox(
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
            child: BigScreenHistoryThumbnail(
              item: item,
              fallbackCoverPath: fallbackCoverPath,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            animeTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            episodeTitle.isEmpty
                ? progressText
                : '$progressText · $episodeTitle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
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
              widthFactor: item.watchProgress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: _focusColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
