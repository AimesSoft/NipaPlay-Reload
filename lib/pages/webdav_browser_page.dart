import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/webdav_connection_dialog.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/utils/webdav_file_sorter.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';

/// WebDAV 文件浏览器页面
/// 用于快捷 Tab，提供快速浏览和播放 WebDAV 视频的功能
class WebDAVBrowserPage extends StatefulWidget {
  const WebDAVBrowserPage({super.key});

  @override
  State<WebDAVBrowserPage> createState() => _WebDAVBrowserPageState();
}

class _WebDAVBrowserPageState extends State<WebDAVBrowserPage> {
  // 当前选中的服务器连接
  WebDAVConnection? _currentConnection;
  // 当前路径
  String _currentPath = '/';
  // 路径历史，用于返回
  final List<String> _pathHistory = [];
  // 当前目录内容
  List<WebDAVFile> _currentFiles = [];
  // 加载状态
  bool _isLoading = false;
  // 是否正在初始化
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    // 初始化 WebDAV 服务
    await WebDAVService.instance.initialize();

    if (!mounted) return;

    // 加载快捷设置
    final provider =
        Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
    await provider.loadSettings();

    if (!mounted) return;

    // 设置默认服务器
    if (provider.hasValidDefaultServer) {
      _currentConnection = provider.defaultConnection;
      _currentPath = provider.defaultDirectory;
    } else if (WebDAVService.instance.connections.isNotEmpty) {
      // 如果没有设置默认服务器，使用第一个可用的连接
      _currentConnection = WebDAVService.instance.connections.first;
      _currentPath = '/';
    }

    setState(() {
      _isInitializing = false;
    });

    // 加载目录内容
    if (_currentConnection != null) {
      await _loadDirectory();
    }
  }

  Future<void> _loadDirectory({bool isRecursive = false}) async {
    if (_currentConnection == null) return;
    // 只在非递归调用时检查 _isLoading，避免重入
    if (!isRecursive && _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final files = await WebDAVService.instance.listDirectory(
        _currentConnection!,
        _currentPath,
      );

      // 应用排序预设
      final provider =
          Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
      WebDAVFileSorter.sort(files, provider.sortPreset);

      // 检查是否需要自动进入 Season 文件夹
      if (provider.autoEnterSeasonFolder) {
        final folderNames =
            files.where((f) => f.isDirectory).map((f) => f.name).toList();
        final matchFolder = provider.findMatchingSeasonFolder(folderNames);

        if (matchFolder != null && mounted) {
          // 找到匹配的文件夹，自动进入
          final matchPath = _currentPath.endsWith('/')
              ? '$_currentPath$matchFolder'
              : '$_currentPath/$matchFolder';
          setState(() {
            _currentPath = matchPath;
          });
          // 递归加载（标记为递归调用）
          await _loadDirectory(isRecursive: true);
          return;
        }
      }

      if (mounted) {
        setState(() {
          _currentFiles = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        BlurSnackBar.show(context, '加载目录失败: $e');
      }
    }
  }

  void _navigateToDirectory(String path) {
    if (_currentPath != '/') {
      _pathHistory.add(_currentPath);
    }
    setState(() {
      _currentPath = path;
    });
    _loadDirectory();
  }

  void _navigateBack() {
    if (_pathHistory.isNotEmpty) {
      setState(() {
        _currentPath = _pathHistory.removeLast();
      });
      _loadDirectory();
    } else if (_currentPath != '/') {
      // 返回上一级目录（而不是直接跳到根目录）
      final segments =
          _currentPath.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        segments.removeLast();
        final parentPath = segments.isEmpty ? '/' : '/' + segments.join('/');
        setState(() {
          _currentPath = parentPath;
        });
        _loadDirectory();
      }
    }
  }

  /// 是否可以返回上一级
  bool get _canNavigateBack => _currentPath != '/';

  void _playVideo(WebDAVFile file) {
    if (_currentConnection == null) return;

    final videoUrl = WebDAVService.instance.getFileUrl(
      _currentConnection!,
      file.path,
    );

    // 创建观看历史项用于播放
    final historyItem = WatchHistoryItem(
      animeName: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
      episodeTitle: file.name,
      filePath: videoUrl,
      watchProgress: 0,
      lastPosition: 0,
      duration: 0,
      lastWatchTime: DateTime.now(),
    );

    // 使用 PlaybackService 播放视频
    final playableItem = PlayableItem(
      videoPath: videoUrl,
      title: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
      subtitle: file.name,
      historyItem: historyItem,
    );

    PlaybackService().play(playableItem);
  }

  void _showServerSelector() {
    final connections = WebDAVService.instance.connections;
    if (connections.isEmpty) {
      BlurSnackBar.show(context, '没有配置任何 WebDAV 服务器');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _ServerSelectorSheet(
        connections: connections,
        currentConnection: _currentConnection,
        onSelected: (connection) {
          setState(() {
            _currentConnection = connection;
            _currentPath = '/';
            _pathHistory.clear();
          });
          _loadDirectory();
        },
      ),
    );
  }

  /// 显示添加 WebDAV 服务器对话框
  Future<void> _showAddServerDialog() async {
    final connectionsBefore = WebDAVService.instance.connections.length;

    final result = await WebDAVConnectionDialog.show(context);

    if (result == true && mounted) {
      // 添加成功
      final connectionsAfter = WebDAVService.instance.connections;

      if (connectionsAfter.isNotEmpty) {
        // 获取新添加的服务器（最后一个）
        final newConnection = connectionsAfter.last;

        // 如果添加前没有服务器，添加后只有一个服务器，则自动设置为默认服务器
        if (connectionsBefore == 0 && connectionsAfter.length == 1) {
          final provider =
              Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
          await provider.setDefaultServerName(newConnection.name);
          BlurSnackBar.show(
              context, '已将 ${newConnection.name} 设置为默认 WebDAV 服务器');
        }

        // 自动选择新添加的服务器并加载目录
        setState(() {
          _currentConnection = newConnection;
          _currentPath = '/';
          _pathHistory.clear();
        });
        await _loadDirectory();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5);
    final cardColor = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white60 : Colors.black54;
    final accentColor = const Color(0xFFFF2E55);

    if (_isInitializing) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF2E55)),
        ),
      );
    }

    // 没有配置任何 WebDAV 服务器
    if (_currentConnection == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 64,
                color: secondaryTextColor,
              ),
              const SizedBox(height: 16),
              Text(
                '没有配置 WebDAV 服务器',
                style: TextStyle(
                  fontSize: 18,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请先在设置中添加 WebDAV 服务器',
                style: TextStyle(
                  fontSize: 14,
                  color: secondaryTextColor,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _showAddServerDialog(),
                icon: const Icon(Icons.add),
                label: const Text('添加服务器'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_canNavigateBack, // 如果可以返回上一级，则阻止系统返回
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _canNavigateBack) {
          _navigateBack();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Column(
          children: [
            // 顶部导航栏
            _buildNavigationBar(
              context: context,
              cardColor: cardColor,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              accentColor: accentColor,
            ),
            // 文件列表
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFFF2E55)),
                    )
                  : _currentFiles.isEmpty
                      ? Center(
                          child: Text(
                            '当前目录为空',
                            style: TextStyle(color: secondaryTextColor),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _currentFiles.length,
                          itemBuilder: (context, index) {
                            final file = _currentFiles[index];
                            return _buildFileItem(
                              file: file,
                              cardColor: cardColor,
                              textColor: textColor,
                              secondaryTextColor: secondaryTextColor,
                              accentColor: accentColor,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationBar({
    required BuildContext context,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      decoration: BoxDecoration(
        color: cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 服务器选择和返回按钮
          Row(
            children: [
              // 返回按钮
              if (_currentPath != '/' || _pathHistory.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  color: textColor,
                  onPressed: _navigateBack,
                ),
              // 服务器选择
              Expanded(
                child: InkWell(
                  onTap: _showServerSelector,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: secondaryTextColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_outlined,
                          size: 20,
                          color: accentColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _currentConnection?.name ?? '选择服务器',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.expand_more,
                          size: 20,
                          color: secondaryTextColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 路径面包屑导航（根据设置显示）
          if (Provider.of<WebDAVQuickAccessProvider>(context)
              .showPathBreadcrumb) ...[
            const SizedBox(height: 12),
            _buildPathBreadcrumb(
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              accentColor: accentColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPathBreadcrumb({
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    // 将路径分割成片段
    final segments =
        _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    final hasSegments = segments.isNotEmpty;

    return SizedBox(
      height: 32,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            // 根目录
            InkWell(
              onTap: () => _navigateToPath('/'),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  '根目录',
                  style: TextStyle(
                    color: !hasSegments ? accentColor : secondaryTextColor,
                    fontSize: 13,
                    fontWeight:
                        !hasSegments ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
            // 路径片段
            ...List.generate(segments.length, (index) {
              final segment = segments[index];
              final isLast = index == segments.length - 1;
              final path = '/' + segments.sublist(0, index + 1).join('/');

              return Row(
                children: [
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: secondaryTextColor,
                  ),
                  InkWell(
                    onTap: isLast ? null : () => _navigateToPath(path),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Text(
                        segment,
                        style: TextStyle(
                          color: isLast ? accentColor : secondaryTextColor,
                          fontSize: 13,
                          fontWeight:
                              isLast ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  void _navigateToPath(String path) {
    // 清空历史记录，直接跳转到指定路径
    setState(() {
      _pathHistory.clear();
      _currentPath = path;
    });
    _loadDirectory();
  }

  Widget _buildFileItem({
    required WebDAVFile file,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    final isDirectory = file.isDirectory;

    // 提取 SxxExx 季集信息
    String? seasonEpisode;
    if (!isDirectory) {
      final match = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,2})').firstMatch(file.name);
      if (match != null) {
        seasonEpisode = 'S${match.group(1)}E${match.group(2)}';
      }
    }

    // 查找播放历史
    final videoUrl = _currentConnection != null
        ? WebDAVService.instance.getFileUrl(_currentConnection!, file.path)
        : null;
    final historyProvider =
        Provider.of<WatchHistoryProvider>(context, listen: false);
    WatchHistoryItem? historyItem;
    if (videoUrl != null) {
      try {
        historyItem = historyProvider.history.firstWhere(
          (item) => item.filePath == videoUrl,
        );
      } catch (_) {
        historyItem = null;
      }
    }
    final hasProgress = historyItem != null &&
        historyItem.duration > 0 &&
        historyItem.watchProgress > 0.01 &&
        historyItem.watchProgress < 0.95;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: secondaryTextColor.withOpacity(0.1),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isDirectory
            ? () => _navigateToDirectory(file.path)
            : () => _playVideo(file),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                isDirectory ? Icons.folder_outlined : Icons.video_file_outlined,
                color: isDirectory ? Colors.amber : accentColor,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 文件名 - 最多显示两行
                    Text(
                      file.name,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 文件大小和播放进度
                    Row(
                      children: [
                        if (!isDirectory &&
                            file.size != null &&
                            file.size! > 0) ...[
                          Text(
                            _formatFileSize(file.size!),
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                          if (seasonEpisode != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.blue.withOpacity(0.3),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                seasonEpisode,
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          if (hasProgress) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${(historyItem.watchProgress * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  color: accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ] else if (!isDirectory && seasonEpisode != null) ...[
                          Text(
                            seasonEpisode,
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else if (isDirectory) ...[
                          Text(
                            '文件夹',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // 播放进度条
                    if (hasProgress) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: historyItem.watchProgress,
                          backgroundColor: secondaryTextColor.withOpacity(0.2),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(accentColor),
                          minHeight: 3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!isDirectory)
                IconButton(
                  icon: const Icon(Icons.play_circle_outline),
                  color: accentColor,
                  onPressed: () => _playVideo(file),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: secondaryTextColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// 服务器选择底部弹窗
class _ServerSelectorSheet extends StatelessWidget {
  final List<WebDAVConnection> connections;
  final WebDAVConnection? currentConnection;
  final ValueChanged<WebDAVConnection> onSelected;

  const _ServerSelectorSheet({
    required this.connections,
    this.currentConnection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white60 : Colors.black54;
    final accentColor = const Color(0xFFFF2E55);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: secondaryTextColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '选择 WebDAV 服务器',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          const Divider(height: 1),
          ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: connections.length,
            itemBuilder: (context, index) {
              final connection = connections[index];
              final isSelected = connection.name == currentConnection?.name;

              return ListTile(
                leading: Icon(
                  isSelected ? Icons.cloud : Icons.cloud_outlined,
                  color: isSelected ? accentColor : secondaryTextColor,
                ),
                title: Text(
                  connection.name,
                  style: TextStyle(
                    color: textColor,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  connection.url,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: accentColor)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  onSelected(connection);
                },
              );
            },
          ),
          // 底部安全区域
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
