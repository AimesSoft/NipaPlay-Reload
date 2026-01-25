import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/utils/watch_history_auto_match_helper.dart';

class WatchHistoryPage extends StatefulWidget {
  const WatchHistoryPage({super.key});

  @override
  State<WatchHistoryPage> createState() => _WatchHistoryPageState();
}

class _WatchHistoryPageState extends State<WatchHistoryPage> {
  bool _isAutoMatching = false;
  bool _autoMatchDialogVisible = false;
  OverlayEntry? _contextMenuOverlay;
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  List<WatchHistoryItem> _cachedValidHistory = const [];
  int _lastHistoryHash = 0;

  @override
  void dispose() {
    _hideContextMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Consumer<WatchHistoryProvider>(
        builder: (context, historyProvider, child) {
          if (historyProvider.isLoading && historyProvider.history.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: colorScheme.onSurface),
            );
          }

          final validHistory = _getValidHistory(historyProvider.history);

          if (validHistory.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: validHistory.length,
            itemBuilder: (context, index) {
              final item = validHistory[index];
              return _buildWatchHistoryItem(item);
            },
            separatorBuilder: (context, index) => const SizedBox(height: 8),
          );
        },
      ),
    );
  }

  Widget _buildWatchHistoryItem(WatchHistoryItem item) {
    final appearanceProvider = context.watch<AppearanceSettingsProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress:
        _isAutoMatching ? null : () => _showDeleteConfirmDialog(item),
      onSecondaryTapDown: _isAutoMatching
        ? null
        : (details) =>
          _showContextMenu(details.globalPosition, item),
      child: GlassmorphicContainer(
        width: double.infinity,
        height: 70,
        borderRadius: 8,
        blur: appearanceProvider.enableWidgetBlurEffect ? 10 : 0,
        alignment: Alignment.center,
        border: 0.5,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.onSurface.withOpacity(0.1),
            colorScheme.onSurface.withOpacity(0.05),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.onSurface.withOpacity(0.5),
            colorScheme.onSurface.withOpacity(0.5),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isAutoMatching ? null : () => _onWatchHistoryItemTap(item),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // 缩略图
                  _buildThumbnail(item),
                  const SizedBox(width: 12),
                  
                  // 标题和副标题
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.animeName.isNotEmpty ? item.animeName : path.basename(item.filePath),
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.episodeTitle ?? '未知集数',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.6),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  
                  // 观看进度和时间
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (item.watchProgress > 0)
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colorScheme.onSurface.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: item.watchProgress,
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.secondary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(item.lastWatchTime),
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(WatchHistoryItem item) {
    final path = item.thumbnailPath;
    if (path != null) {
      return FutureBuilder<Uint8List?>(
        future: _getThumbnailBytes(path),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                snapshot.data!,
                width: 80,
                height: 45, // 16:9 比例
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultThumbnail();
                },
              ),
            );
          }
          return _buildDefaultThumbnail();
        },
      );
    }
    return _buildDefaultThumbnail();
  }

  Widget _buildDefaultThumbnail() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 80,
      height: 45, // 16:9 比例
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Ionicons.videocam_outline,
        color: colorScheme.onSurface.withOpacity(0.6),
        size: 20,
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Ionicons.time_outline,
            color: colorScheme.onSurface.withOpacity(0.6),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无观看记录',
            locale:const Locale("zh-Hans","zh"),
style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '开始播放视频后，这里会显示观看记录',
            locale:const Locale("zh-Hans","zh"),
style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.7),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
    if (_isAutoMatching) {
      BlurSnackBar.show(context, '正在自动匹配，请稍候');
      return;
    }

    debugPrint('[WatchHistoryPage] _onWatchHistoryItemTap: Received item: $item');
    var currentItem = item;

    // 检查是否为网络URL或流媒体协议URL
    final isNetworkUrl = currentItem.filePath.startsWith('http://') || currentItem.filePath.startsWith('https://');
    final isJellyfinProtocol = currentItem.filePath.startsWith('jellyfin://');
    final isEmbyProtocol = currentItem.filePath.startsWith('emby://');
    
    bool fileExists = false;
    String filePath = currentItem.filePath;
    String? actualPlayUrl;

    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      fileExists = true;
      if (isJellyfinProtocol) {
        try {
          final jellyfinId = currentItem.filePath.replaceFirst('jellyfin://', '');
          final jellyfinService = JellyfinService.instance;
          if (jellyfinService.isConnected) {
            actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
          } else {
            BlurSnackBar.show(context, '未连接到Jellyfin服务器');
            return;
          }
        } catch (e) {
          BlurSnackBar.show(context, '获取Jellyfin流媒体URL失败: $e');
          return;
        }
      }
      
      if (isEmbyProtocol) {
        try {
          final embyId = currentItem.filePath.replaceFirst('emby://', '');
          final embyService = EmbyService.instance;
          if (embyService.isConnected) {
            actualPlayUrl = await embyService.getStreamUrl(embyId);
          } else {
            BlurSnackBar.show(context, '未连接到Emby服务器');
            return;
          }
        } catch (e) {
          BlurSnackBar.show(context, '获取Emby流媒体URL失败: $e');
          return;
        }
      }
    } else {
      final videoFile = File(currentItem.filePath);
      fileExists = videoFile.existsSync();
      
      if (!fileExists && Platform.isIOS) {
        String altPath = filePath.startsWith('/private') 
            ? filePath.replaceFirst('/private', '') 
            : '/private$filePath';
        
        final File altFile = File(altPath);
        if (altFile.existsSync()) {
          filePath = altPath;
          currentItem = currentItem.copyWith(filePath: filePath);
          fileExists = true;
        }
      }
    }
    
    if (!fileExists) {
      BlurSnackBar.show(context, '文件不存在或无法访问: ${path.basename(currentItem.filePath)}');
      return;
    }

    if (WatchHistoryAutoMatchHelper.shouldAutoMatch(currentItem)) {
      final matchablePath = actualPlayUrl ?? currentItem.filePath;
      currentItem = await _performAutoMatch(currentItem, matchablePath);
    }

    final playableItem = PlayableItem(
      videoPath: currentItem.filePath,
      title: currentItem.animeName,
      subtitle: currentItem.episodeTitle,
      animeId: currentItem.animeId,
      episodeId: currentItem.episodeId,
      historyItem: currentItem,
      actualPlayUrl: actualPlayUrl,
    );

    await PlaybackService().play(playableItem);
  }

  Future<WatchHistoryItem> _performAutoMatch(
    WatchHistoryItem currentItem,
    String matchablePath,
  ) async {
    _updateAutoMatchingState(true);
    _showAutoMatchingDialog();
    String? notification;

    try {
      return await WatchHistoryAutoMatchHelper.tryAutoMatch(
        context,
        currentItem,
        matchablePath: matchablePath,
        onMatched: (message) => notification = message,
      );
    } finally {
      _hideAutoMatchingDialog();
      _updateAutoMatchingState(false);
      if (notification != null && mounted) {
        BlurSnackBar.show(context, notification!);
      }
    }
  }

  void _updateAutoMatchingState(bool value) {
    if (!mounted) {
      _isAutoMatching = value;
      return;
    }
    if (_isAutoMatching == value) {
      return;
    }
    setState(() {
      _isAutoMatching = value;
    });
  }

  void _showAutoMatchingDialog() {
    if (_autoMatchDialogVisible || !mounted) return;
    _autoMatchDialogVisible = true;
    BlurDialog.show(
      context: context,
      title: '正在自动匹配',
      barrierDismissible: false,
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(height: 8),
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          SizedBox(height: 16),
          Text(
            '正在为历史记录匹配弹幕，请稍候…',
            style: TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).whenComplete(() {
      _autoMatchDialogVisible = false;
    });
  }

  void _hideAutoMatchingDialog() {
    if (!_autoMatchDialogVisible) {
      return;
    }
    if (!mounted) {
      _autoMatchDialogVisible = false;
      return;
    }
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _showDeleteConfirmDialog(WatchHistoryItem item) {
    _hideContextMenu();
    BlurDialog.show(
      context: context,
      title: '删除观看记录',
      content: '确定要删除 ${item.animeName} 的观看记录吗？',
      actions: [
        TextButton(
          child: const Text('取消'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: const Text('删除', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.red)),
          onPressed: () async {
            // 调用 Provider 的方法删除观看记录
            final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
            await watchHistoryProvider.removeHistory(item.filePath);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  void _showContextMenu(Offset tapPosition, WatchHistoryItem item) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _hideContextMenu();

    final renderBox = overlay.context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    const double menuWidth = 196;
    const double menuHeight = 56;
    final Size overlaySize = renderBox.size;
    final Offset overlayPosition = renderBox.globalToLocal(tapPosition);

    double left = overlayPosition.dx;
    double top = overlayPosition.dy;

    if (left + menuWidth > overlaySize.width) {
      left = overlaySize.width - menuWidth - 12;
    }
    if (top + menuHeight > overlaySize.height) {
      top = overlaySize.height - menuHeight - 12;
    }

    final bool enableBlur = context.read<AppearanceSettingsProvider>().enableWidgetBlurEffect;

    _contextMenuOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideContextMenu,
              onSecondaryTap: _hideContextMenu,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: _BlurContextMenu(
              enableBlur: enableBlur,
              onDelete: () {
                _hideContextMenu();
                _showDeleteConfirmDialog(item);
              },
            ),
          ),
        ],
      ),
    );

    overlay.insert(_contextMenuOverlay!);
  }

  void _hideContextMenu() {
    _contextMenuOverlay?.remove();
    _contextMenuOverlay = null;
  }

  List<WatchHistoryItem> _getValidHistory(List<WatchHistoryItem> history) {
    final hash = _historyHash(history);
    if (hash != _lastHistoryHash) {
      _cachedValidHistory =
          history.where((item) => item.duration > 0).toList(growable: false);
      _lastHistoryHash = hash;
    }
    return _cachedValidHistory;
  }

  Future<Uint8List?> _getThumbnailBytes(String path) {
    return _thumbnailFutures.putIfAbsent(path, () async {
      try {
        final file = File(path);
        if (!await file.exists()) return null;
        return await file.readAsBytes();
      } catch (_) {
        return null;
      }
    });
  }

  int _historyHash(List<WatchHistoryItem> history) {
    int hash = history.length;
    final sample = history.length > 5 ? history.take(5) : history;
    for (final item in sample) {
      hash = hash ^ item.filePath.hashCode ^ item.lastWatchTime.millisecondsSinceEpoch;
    }
    return hash;
  }
}

class _BlurContextMenu extends StatelessWidget {
  final bool enableBlur;
  final VoidCallback onDelete;

  const _BlurContextMenu({
    required this.enableBlur,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GlassmorphicContainer(
      width: 196,
      height: 56,
      borderRadius: 12,
      blur: enableBlur ? 16 : 0,
      border: 0.8,
      alignment: Alignment.center,
      linearGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.onSurface.withOpacity(0.18),
          colorScheme.onSurface.withOpacity(0.08),
        ],
      ),
      borderGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.onSurface.withOpacity(0.45),
          colorScheme.onSurface.withOpacity(0.15),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onDelete,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Ionicons.trash_outline,
                  size: 18,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 10),
                Text(
                  '删除观看记录',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
