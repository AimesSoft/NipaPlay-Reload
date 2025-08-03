import 'dart:io';
import 'dart:typed_data';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/widgets/nipaplay_theme/loading_placeholder.dart';

class FluentHistoryCard extends StatelessWidget {
  final WatchHistoryItem item;
  final bool isLatestUpdated;
  final VoidCallback onTap;

  const FluentHistoryCard({
    super.key,
    required this.item,
    required this.isLatestUpdated,
    required this.onTap,
  });

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        return Card(
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 90,
                  width: double.infinity,
                  child: _getVideoThumbnail(item, isLatestUpdated),
                ),
                ProgressBar(
                  value: item.watchProgress * 100,
                  backgroundColor: Colors.grey.withOpacity(0.2),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.animeName.isNotEmpty ? item.animeName : p.basename(item.filePath),
                          style: theme.typography.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.episodeTitle ?? '未知集数',
                          style: theme.typography.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Icon(
                              FluentIcons.play,
                              color: theme.accentColor,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(Duration(milliseconds: item.lastPosition)),
                              style: theme.typography.caption?.copyWith(color: theme.accentColor),
                            ),
                            Text(
                              " / ${_formatDuration(Duration(milliseconds: item.duration))}",
                              style: theme.typography.caption,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _getVideoThumbnail(WatchHistoryItem item, bool isLatestUpdated) {
    if (item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        return FutureBuilder<Uint8List>(
          future: thumbnailFile.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingPlaceholder(width: double.infinity, height: 90, borderRadius: 0);
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
              return _buildDefaultThumbnail();
            }
            try {
              return Image.memory(
                snapshot.data!,
                key: isLatestUpdated ? UniqueKey() : ValueKey(item.thumbnailPath),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) => _buildDefaultThumbnail(),
              );
            } catch (e) {
              return _buildDefaultThumbnail();
            }
          },
        );
      }
    }
    return _buildDefaultThumbnail();
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      color: Colors.grey[170],
      child: Center(
        child: Icon(FluentIcons.video, color: Colors.grey[80], size: 32),
      ),
    );
  }
}
