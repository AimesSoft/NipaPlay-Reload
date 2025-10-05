import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/media_library_page.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/floating_action_glass_button.dart';
import 'package:nipaplay/widgets/nipaplay_theme/glass_bottom_sheet.dart';
import 'package:nipaplay/widgets/nipaplay_theme/shared_remote_host_selection_sheet.dart';

class SharedRemoteLibraryView extends StatefulWidget {
  const SharedRemoteLibraryView({super.key, this.onPlayEpisode});

  final OnPlayEpisodeCallback? onPlayEpisode;

  @override
  State<SharedRemoteLibraryView> createState() => _SharedRemoteLibraryViewState();
}

class _SharedRemoteLibraryViewState extends State<SharedRemoteLibraryView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _gridScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<SharedRemoteLibraryProvider>(
      builder: (context, provider, child) {
        final hosts = provider.hosts;
        final activeHost = provider.activeHost;
        final animeSummaries = provider.animeSummaries;
        final hasHosts = hosts.isNotEmpty;

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (provider.errorMessage != null)
                  _buildErrorChip(provider.errorMessage!, provider),
                Expanded(
                  child: _buildBody(context, provider, animeSummaries, hasHosts),
                ),
              ],
            ),
            _buildFloatingButtons(context, provider),
          ],
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    List<SharedRemoteAnimeSummary> animeSummaries,
    bool hasHosts,
  ) {
    if (provider.isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!hasHosts) {
      return _buildEmptyHostsPlaceholder(context);
    }

    if (provider.isLoading && animeSummaries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (animeSummaries.isEmpty) {
      return _buildEmptyLibraryPlaceholder(context, provider.activeHost);
    }

    return RepaintBoundary(
      child: Scrollbar(
        controller: _gridScrollController,
        radius: const Radius.circular(4),
        child: GridView.builder(
          controller: _gridScrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 7 / 12,
          ),
          itemCount: animeSummaries.length,
          itemBuilder: (context, index) {
            final anime = animeSummaries[index];
            return AnimeCard(
              key: ValueKey('shared_${anime.animeId}'),
              name: anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name,
              imageUrl: anime.imageUrl ?? '',
              source: provider.activeHost?.displayName,
              enableShadow: false,
              backgroundBlurSigma: 10,
              onTap: () => _openEpisodeSheet(context, provider, anime),
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorChip(String message, SharedRemoteLibraryProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.orange.withOpacity(0.12),
          border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Ionicons.warning_outline, color: Colors.orangeAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                locale: const Locale('zh', 'CN'),
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
            ),
            IconButton(
              onPressed: provider.clearError,
              icon: const Icon(Ionicons.close_outline, color: Colors.orangeAccent, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHostsPlaceholder(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Ionicons.cloud_outline, color: Colors.white38, size: 48),
          SizedBox(height: 12),
          Text(
            '尚未添加共享客户端\n请前往设置 > 远程媒体库 添加',
            locale: Locale('zh', 'CN'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyLibraryPlaceholder(BuildContext context, SharedRemoteHost? host) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Ionicons.folder_open_outline, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          Text(
            host == null
                ? '请选择一个共享客户端'
                : '该客户端尚未扫描任何番剧',
            locale: const Locale('zh', 'CN'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingButtons(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionGlassButton(
            iconData: Ionicons.refresh_outline,
            description: '刷新共享媒体\n重新同步番剧清单',
            onPressed: () {
              if (!provider.hasActiveHost) {
                BlurSnackBar.show(context, '请先添加并选择共享客户端');
                return;
              }
              provider.refreshLibrary();
            },
          ),
          const SizedBox(height: 16),
          FloatingActionGlassButton(
            iconData: Ionicons.link_outline,
            description: '切换共享客户端\n从列表中选择远程主机',
            onPressed: () => SharedRemoteHostSelectionSheet.show(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openEpisodeSheet(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    SharedRemoteAnimeSummary anime,
  ) async {
    try {
      final episodes = await provider.loadAnimeEpisodes(anime.animeId);
      if (!mounted) return;
      await GlassBottomSheet.show(
        context: context,
        title: anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name,
        height: MediaQuery.of(context).size.height * 0.55,
        child: _buildEpisodeList(episodes, (episode) {
          final watchItem = provider.buildWatchHistoryItem(anime: anime, episode: episode);
          widget.onPlayEpisode?.call(watchItem);
          Navigator.of(context).pop();
        }),
      );
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '加载剧集失败: $e');
    }
  }

  Widget _buildEpisodeList(
    List<SharedRemoteEpisode> episodes,
    void Function(SharedRemoteEpisode) onPlay,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: episodes.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
      itemBuilder: (_, index) {
        final episode = episodes[index];
        final playable = episode.fileExists;
        return ListTile(
          onTap: playable ? () => onPlay(episode) : null,
          leading: CircleAvatar(
            backgroundColor: Colors.white12,
            child: Text('${index + 1}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          title: Text(
            episode.title,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          subtitle: Text(
            playable ? '可播放' : '原文件缺失',
            locale: const Locale('zh', 'CN'),
            style: TextStyle(
              color: playable ? Colors.white54 : Colors.orangeAccent,
              fontSize: 12,
            ),
          ),
          trailing: const Icon(Ionicons.play_circle_outline, color: Colors.white70),
        );
      },
    );
  }
}

