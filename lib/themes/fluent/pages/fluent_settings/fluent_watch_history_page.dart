import 'dart:io';
import 'dart:typed_data';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/utils/message_helper.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

class FluentWatchHistoryPage extends StatefulWidget {
  const FluentWatchHistoryPage({super.key});

  @override
  State<FluentWatchHistoryPage> createState() => _FluentWatchHistoryPageState();
}

class _FluentWatchHistoryPageState extends State<FluentWatchHistoryPage> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.scrollable(
      children: [
        Consumer<WatchHistoryProvider>(
          builder: (context, historyProvider, child) {
            if (historyProvider.isLoading && historyProvider.history.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(50.0),
                  child: ProgressRing(),
                ),
              );
            }

            // 过滤出真正被观看过的记录（与主页仪表盘保持一致）
            final validHistory = historyProvider.history.where((item) => item.duration > 0).toList();

            if (validHistory.isEmpty) {
              return _buildEmptyState();
            }

            return Column(
              children: validHistory
                  .map((item) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: _buildWatchHistoryItem(item),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWatchHistoryItem(WatchHistoryItem item) {
    return Card(
      child: ListTile(
        leading: _buildThumbnail(item),
        title: Text(
          item.animeName.isNotEmpty ? item.animeName : path.basename(item.filePath),
          style: FluentTheme.of(context).typography.body?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.episodeTitle ?? '未知集数',
              style: FluentTheme.of(context).typography.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.watchProgress > 0) ...[
              const SizedBox(height: 4),
              SizedBox(
                height: 4,
                child: ProgressBar(
                  value: item.watchProgress * 100,
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatTime(item.lastWatchTime),
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(FluentIcons.delete, size: 16),
              onPressed: () => _showDeleteConfirmDialog(item),
            ),
          ],
        ),
        onPressed: () => _onWatchHistoryItemTap(item),
      ),
    );
  }

  Widget _buildThumbnail(WatchHistoryItem item) {
    if (item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        return FutureBuilder<Uint8List>(
          future: thumbnailFile.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Container(
                width: 80,
                height: 45,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildDefaultThumbnail();
                    },
                  ),
                ),
              );
            }
            return _buildDefaultThumbnail();
          },
        );
      }
    }
    return _buildDefaultThumbnail();
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      width: 80,
      height: 45,
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: FluentTheme.of(context).inactiveColor,
          width: 1,
        ),
      ),
      child: Icon(
        FluentIcons.video,
        color: FluentTheme.of(context).inactiveColor,
        size: 20,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(50.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.history,
              color: FluentTheme.of(context).inactiveColor,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无观看记录',
              style: FluentTheme.of(context).typography.subtitle,
            ),
            const SizedBox(height: 8),
            Text(
              '开始播放视频后，这里会显示观看记录',
              style: FluentTheme.of(context).typography.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  void _onWatchHistoryItemTap(WatchHistoryItem item) async {
    debugPrint('[FluentWatchHistoryPage] _onWatchHistoryItemTap: Received item: $item');

    // 检查是否为网络URL或流媒体协议URL
    final isNetworkUrl = item.filePath.startsWith('http://') || item.filePath.startsWith('https://');
    final isJellyfinProtocol = item.filePath.startsWith('jellyfin://');
    final isEmbyProtocol = item.filePath.startsWith('emby://');
    
    bool fileExists = false;
    String filePath = item.filePath;
    String? actualPlayUrl;

    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      fileExists = true;
      if (isJellyfinProtocol) {
        try {
          final jellyfinId = item.filePath.replaceFirst('jellyfin://', '');
          final jellyfinService = JellyfinService.instance;
          if (jellyfinService.isConnected) {
            actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
          } else {
            MessageHelper.showMessage(context, '未连接到Jellyfin服务器');
            return;
          }
        } catch (e) {
          MessageHelper.showMessage(context, '获取Jellyfin流媒体URL失败: $e');
          return;
        }
      }
      
      if (isEmbyProtocol) {
        try {
          final embyId = item.filePath.replaceFirst('emby://', '');
          final embyService = EmbyService.instance;
          if (embyService.isConnected) {
            actualPlayUrl = await embyService.getStreamUrl(embyId);
          } else {
            MessageHelper.showMessage(context, '未连接到Emby服务器');
            return;
          }
        } catch (e) {
          MessageHelper.showMessage(context, '获取Emby流媒体URL失败: $e');
          return;
        }
      }
    } else {
      final videoFile = File(item.filePath);
      fileExists = videoFile.existsSync();
      
      if (!fileExists && Platform.isIOS) {
        String altPath = filePath.startsWith('/private') 
            ? filePath.replaceFirst('/private', '') 
            : '/private$filePath';
        
        final File altFile = File(altPath);
        if (altFile.existsSync()) {
          filePath = altPath;
          fileExists = true;
        }
      }
    }
    
    if (!fileExists) {
      MessageHelper.showMessage(context, '文件不存在或无法访问: ${path.basename(item.filePath)}');
      return;
    }

    final playableItem = PlayableItem(
      videoPath: item.filePath,
      title: item.animeName,
      subtitle: item.episodeTitle,
      animeId: item.animeId,
      episodeId: item.episodeId,
      historyItem: item,
      actualPlayUrl: actualPlayUrl,
    );

    await PlaybackService().play(playableItem);
  }

  void _showDeleteConfirmDialog(WatchHistoryItem item) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('删除观看记录'),
          content: Text('确定要删除 ${item.animeName} 的观看记录吗？'),
          actions: [
            Button(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            FilledButton(
              child: const Text('删除'),
              onPressed: () async {
                // 调用 Provider 的方法删除观看记录
                final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
                await watchHistoryProvider.removeHistory(item.filePath);
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }
}