import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/themes/web/models/web_playback_item.dart';
import 'package:nipaplay/themes/web/services/web_remote_api_client.dart';

class WebLibraryPage extends StatefulWidget {
  const WebLibraryPage({
    super.key,
    required this.api,
    required this.searchQuery,
    required this.onPlay,
  });

  final WebRemoteApiClient api;
  final String searchQuery;
  final ValueChanged<WebPlaybackItem> onPlay;

  @override
  State<WebLibraryPage> createState() => _WebLibraryPageState();
}

class _WebLibraryPageState extends State<WebLibraryPage> {
  late Future<List<SharedRemoteAnimeSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchSharedAnimeSummaries();
  }

  @override
  void didUpdateWidget(covariant WebLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api.baseUrl != widget.api.baseUrl) {
      _future = widget.api.fetchSharedAnimeSummaries();
    }
  }

  void _refresh() {
    setState(() {
      _future = widget.api.fetchSharedAnimeSummaries();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '媒体库',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<SharedRemoteAnimeSummary>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorView(
                    title: '加载失败',
                    message: snapshot.error.toString(),
                    onRetry: _refresh,
                  );
                }
                final data = snapshot.data ?? const <SharedRemoteAnimeSummary>[];
                final filtered = _filter(data, widget.searchQuery);
                if (filtered.isEmpty) {
                  return const Center(child: Text('暂无数据'));
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return GridView.builder(
                      gridDelegate:
                          SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent:
                            constraints.maxWidth >= 1200 ? 220 : 200,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.62,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final anime = filtered[index];
                        return _AnimeCard(
                          anime: anime,
                          onTap: () => _openAnimeDetail(anime),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<SharedRemoteAnimeSummary> _filter(
    List<SharedRemoteAnimeSummary> items,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return items;

    return items.where((anime) {
      final title = (anime.nameCn?.isNotEmpty == true ? anime.nameCn : anime.name) ?? '';
      return title.toLowerCase().contains(normalized) ||
          anime.name.toLowerCase().contains(normalized);
    }).toList(growable: false);
  }

  Future<void> _openAnimeDetail(SharedRemoteAnimeSummary anime) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
            child: _AnimeDetailDialog(
              api: widget.api,
              animeId: anime.animeId,
              onPlay: widget.onPlay,
            ),
          ),
        );
      },
    );
  }
}

class _AnimeCard extends StatelessWidget {
  const _AnimeCard({
    required this.anime,
    required this.onTap,
  });

  final SharedRemoteAnimeSummary anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name;
    final dateText = DateFormat('yyyy-MM-dd').format(anime.lastWatchTime.toLocal());

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if ((anime.imageUrl ?? '').isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: anime.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    )
                  else
                    const ColoredBox(
                      color: Color(0xFFE9ECEF),
                      child: Center(child: Icon(Icons.image_not_supported_outlined)),
                    ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.history, size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                dateText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(
                children: [
                  Text(
                    '${anime.episodeCount} 集',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (anime.hasMissingFiles)
                    const Tooltip(
                      message: '存在缺失文件',
                      child: Icon(Icons.warning_amber_rounded, size: 16),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimeDetailDialog extends StatefulWidget {
  const _AnimeDetailDialog({
    required this.api,
    required this.animeId,
    required this.onPlay,
  });

  final WebRemoteApiClient api;
  final int animeId;
  final ValueChanged<WebPlaybackItem> onPlay;

  @override
  State<_AnimeDetailDialog> createState() => _AnimeDetailDialogState();
}

class _AnimeDetailDialogState extends State<_AnimeDetailDialog> {
  late Future<WebSharedAnimeDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchSharedAnimeDetail(widget.animeId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WebSharedAnimeDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorView(
            title: '加载详情失败',
            message: snapshot.error.toString(),
            onRetry: () {
              setState(() {
                _future = widget.api.fetchSharedAnimeDetail(widget.animeId);
              });
            },
          );
        }
        final detail = snapshot.data;
        if (detail == null) {
          return const Center(child: Text('暂无数据'));
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      detail.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: () {
                      setState(() {
                        _future = widget.api.fetchSharedAnimeDetail(widget.animeId);
                      });
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (detail.summary?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  detail.summary!.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: detail.episodes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final ep = detail.episodes[index];
                    final double progress = (ep.progress ?? 0).clamp(0.0, 1.0);
                    final lastWatchText = ep.lastWatchTime == null
                        ? null
                        : DateFormat('yyyy-MM-dd HH:mm')
                            .format(ep.lastWatchTime!.toLocal());

                    return ListTile(
                      title: Text(ep.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (lastWatchText != null) '上次观看：$lastWatchText',
                              '进度：${(progress * 100).toStringAsFixed(1)}%',
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ep.fileExists == false)
                            const Tooltip(
                              message: '文件不存在',
                              child: Icon(Icons.warning_amber_rounded),
                            ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: ep.fileExists == false
                                ? null
                                : () {
                                    final uri = widget.api
                                        .resolveExternal(ep.streamPath);
                                    widget.onPlay(
                                      WebPlaybackItem(
                                        uri: uri,
                                        title: ep.title,
                                        subtitle: detail.title,
                                      ),
                                    );
                                    Navigator.of(context).pop();
                                  },
                            child: const Text('播放'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
