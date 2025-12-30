import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nipaplay/themes/web/services/web_remote_api_client.dart';
import 'package:url_launcher/url_launcher.dart';

class WebHistoryPage extends StatefulWidget {
  const WebHistoryPage({
    super.key,
    required this.api,
    required this.searchQuery,
  });

  final WebRemoteApiClient api;
  final String searchQuery;

  @override
  State<WebHistoryPage> createState() => _WebHistoryPageState();
}

class _WebHistoryPageState extends State<WebHistoryPage> {
  late Future<List<WebRemoteHistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchWatchHistory();
  }

  @override
  void didUpdateWidget(covariant WebHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api.baseUrl != widget.api.baseUrl) {
      _future = widget.api.fetchWatchHistory();
    }
  }

  void _refresh() {
    setState(() {
      _future = widget.api.fetchWatchHistory();
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
                '观看记录',
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
            child: FutureBuilder<List<WebRemoteHistoryEntry>>(
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

                final items = snapshot.data ?? const <WebRemoteHistoryEntry>[];
                final filtered = _filter(items, widget.searchQuery);
                if (filtered.isEmpty) {
                  return const Center(child: Text('暂无观看记录'));
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _HistoryCard(
                      entry: filtered[index],
                      onOpen: () async {
                        final uri = widget.api.resolveExternal(
                          filtered[index].episode.streamPath,
                        );
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  List<WebRemoteHistoryEntry> _filter(
    List<WebRemoteHistoryEntry> items,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return items;
    return items.where((entry) {
      final t1 = (entry.animeName ?? '').toLowerCase();
      final t2 = entry.episode.title.toLowerCase();
      return t1.contains(normalized) || t2.contains(normalized);
    }).toList(growable: false);
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.onOpen,
  });

  final WebRemoteHistoryEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ep = entry.episode;
    final double progress = (ep.progress ?? 0).clamp(0.0, 1.0);
    final String timeText = DateFormat('yyyy-MM-dd HH:mm')
        .format((ep.lastWatchTime ?? DateTime.now()).toLocal());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(imageUrl: entry.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.animeName ?? '未知标题',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ep.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 6),
                  Text(
                    '$timeText · ${(progress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onOpen, child: const Text('打开')),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 112,
        height: 72,
        child: (imageUrl ?? '').isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: Color(0xFFE9ECEF),
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              )
            : const ColoredBox(
                color: Color(0xFFE9ECEF),
                child: Center(child: Icon(Icons.image_not_supported_outlined)),
              ),
      ),
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

