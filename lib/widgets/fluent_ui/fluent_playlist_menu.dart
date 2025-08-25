import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'dart:io';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';

class FluentPlaylistMenu extends StatefulWidget {
  final VideoPlayerState videoState;

  const FluentPlaylistMenu({
    super.key,
    required this.videoState,
  });

  @override
  State<FluentPlaylistMenu> createState() => _FluentPlaylistMenuState();
}

class _FluentPlaylistMenuState extends State<FluentPlaylistMenu> {
  // 文件系统数据
  List<String> _fileSystemEpisodes = [];
  
  // Jellyfin剧集信息缓存
  final Map<String, dynamic> _jellyfinEpisodeCache = {};
  
  // Emby剧集信息缓存
  final Map<String, dynamic> _embyEpisodeCache = {};
  
  bool _isLoading = true;
  String? _error;
  String? _currentFilePath;
  String? _currentAnimeTitle;
  
  // 数据源类型
  String _dataSourceType = 'unknown'; // 'filesystem', 'jellyfin', 'emby'
  bool _hasFileSystemData = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _currentFilePath = widget.videoState.currentVideoPath;
      _currentAnimeTitle = widget.videoState.animeTitle;
      
      if (_currentFilePath != null) {
        // 检查是否为Jellyfin流媒体URL
        if (_currentFilePath!.startsWith('jellyfin://')) {
          _dataSourceType = 'jellyfin';
          await _loadJellyfinEpisodes();
          return;
        }
        
        // 检查是否为Emby流媒体URL
        if (_currentFilePath!.startsWith('emby://')) {
          _dataSourceType = 'emby';
          await _loadEmbyEpisodes();
          return;
        }
        
        // 本地文件系统
        _dataSourceType = 'filesystem';
        await _loadFileSystemData();
      }
    } catch (e) {
      setState(() {
        _error = '加载播放列表失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFileSystemData() async {
    try {
      final currentFile = File(_currentFilePath!);
      final directory = currentFile.parent;
      
      if (directory.existsSync()) {
        // 获取目录中的所有视频文件
        final videoExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.3gp', '.ts', '.m2ts'];
        final videoFiles = directory
            .listSync()
            .whereType<File>()
            .where((file) => videoExtensions.any((ext) => file.path.toLowerCase().endsWith(ext)))
            .toList();

        // 按文件名排序
        videoFiles.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

        _fileSystemEpisodes = videoFiles.map((file) => file.path).toList();
        _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;
      }

      if (!_hasFileSystemData) {
        throw Exception('目录中没有找到视频文件');
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      throw Exception('加载本地文件失败：$e');
    }
  }

  Future<void> _loadJellyfinEpisodes() async {
    try {
      final episodeId = _currentFilePath!.replaceFirst('jellyfin://', '');
      
      final episodeInfo = await JellyfinService.instance.getEpisodeDetails(episodeId);
      if (episodeInfo == null) {
        throw Exception('无法获取Jellyfin剧集信息');
      }
      
      final episodes = await JellyfinService.instance.getSeasonEpisodes(
        episodeInfo.seriesId!, 
        episodeInfo.seasonId!
      );
      
      if (episodes.isEmpty) {
        throw Exception('该季没有找到剧集');
      }
      
      // 按集数排序
      episodes.sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
      
      // 缓存剧集信息并转换为播放列表格式
      _jellyfinEpisodeCache.clear();
      _fileSystemEpisodes = episodes.map((ep) {
        final episodeUrl = 'jellyfin://${ep.id}';
        _jellyfinEpisodeCache[ep.id] = {
          'name': ep.name,
          'indexNumber': ep.indexNumber,
          'seriesName': ep.seriesName,
        };
        return episodeUrl;
      }).toList();
      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      throw Exception('加载Jellyfin播放列表失败：$e');
    }
  }

  Future<void> _loadEmbyEpisodes() async {
    try {
      final embyPath = _currentFilePath!.replaceFirst('emby://', '');
      final pathParts = embyPath.split('/');
      final episodeId = pathParts.last;
      
      final episodeInfo = await EmbyService.instance.getEpisodeDetails(episodeId);
      if (episodeInfo == null) {
        throw Exception('无法获取Emby剧集信息');
      }
      
      final episodes = await EmbyService.instance.getSeasonEpisodes(
        episodeInfo.seriesId!, 
        episodeInfo.seasonId!
      );
      
      if (episodes.isEmpty) {
        throw Exception('该季没有找到剧集');
      }
      
      // 按集数排序
      episodes.sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
      
      // 缓存剧集信息
      _embyEpisodeCache.clear();
      _fileSystemEpisodes = episodes.map((ep) {
        final episodeUrl = 'emby://${ep.id}';
        _embyEpisodeCache[ep.id] = {
          'name': ep.name,
          'indexNumber': ep.indexNumber,
          'seriesName': ep.seriesName,
        };
        return episodeUrl;
      }).toList();
      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      throw Exception('加载Emby播放列表失败：$e');
    }
  }

  String _getDisplayName(String filePath) {
    switch (_dataSourceType) {
      case 'jellyfin':
        final episodeId = filePath.replaceFirst('jellyfin://', '');
        final episodeInfo = _jellyfinEpisodeCache[episodeId];
        if (episodeInfo != null) {
          final indexNumber = episodeInfo['indexNumber'] ?? 0;
          final name = episodeInfo['name'] ?? '';
          return 'EP$indexNumber: $name';
        }
        return '未知剧集';
      case 'emby':
        final episodeId = filePath.replaceFirst('emby://', '');
        final episodeInfo = _embyEpisodeCache[episodeId];
        if (episodeInfo != null) {
          final indexNumber = episodeInfo['indexNumber'] ?? 0;
          final name = episodeInfo['name'] ?? '';
          return 'EP$indexNumber: $name';
        }
        return '未知剧集';
      default:
        return filePath.split('/').last;
    }
  }

  String _getSubtitle(String filePath) {
    switch (_dataSourceType) {
      case 'jellyfin':
        final episodeId = filePath.replaceFirst('jellyfin://', '');
        final episodeInfo = _jellyfinEpisodeCache[episodeId];
        return episodeInfo?['seriesName'] ?? 'Jellyfin';
      case 'emby':
        final episodeId = filePath.replaceFirst('emby://', '');
        final episodeInfo = _embyEpisodeCache[episodeId];
        return episodeInfo?['seriesName'] ?? 'Emby';
      default:
        return filePath;
    }
  }

  IconData _getSourceIcon() {
    switch (_dataSourceType) {
      case 'jellyfin':
        return FluentIcons.cloud;
      case 'emby':
        return FluentIcons.cloud;
      default:
        return FluentIcons.folder;
    }
  }

  String _getSourceName() {
    switch (_dataSourceType) {
      case 'jellyfin':
        return 'Jellyfin';
      case 'emby':
        return 'Emby';
      default:
        return '本地文件';
    }
  }

  void _playEpisode(String filePath) async {
    try {
      // 根据不同的数据源类型进行相应的初始化
      if (_dataSourceType == 'jellyfin') {
        // Jellyfin流媒体模式需要特殊处理，但在这个简化版本中直接使用基础的initializePlayer
        await widget.videoState.initializePlayer(filePath);
      } else if (_dataSourceType == 'emby') {
        // Emby流媒体模式需要特殊处理，但在这个简化版本中直接使用基础的initializePlayer
        await widget.videoState.initializePlayer(filePath);
      } else {
        // 本地文件直接使用initializePlayer
        await widget.videoState.initializePlayer(filePath);
      }
    } catch (e) {
      if (mounted) {
        displayInfoBar(context, builder: (context, close) {
          return InfoBar(
            title: const Text('播放失败'),
            content: Text('无法播放该文件：$e'),
            severity: InfoBarSeverity.error,
            isLong: true,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 提示信息
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getSourceIcon(),
                    size: 16,
                    color: FluentTheme.of(context).resources.textFillColorPrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '播放列表',
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '来源: ${_getSourceName()}${_fileSystemEpisodes.isNotEmpty ? " • ${_fileSystemEpisodes.length}项" : ""}',
                style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: FluentTheme.of(context).resources.textFillColorTertiary,
                ),
              ),
              if (_currentAnimeTitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  _currentAnimeTitle!,
                  style: FluentTheme.of(context).typography.caption?.copyWith(
                    color: FluentTheme.of(context).resources.textFillColorSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // 分隔线
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        
        // 播放列表内容
        Expanded(
          child: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const ProgressRing(strokeWidth: 3),
                      const SizedBox(height: 16),
                      Text(
                        '加载播放列表中...',
                        style: FluentTheme.of(context).typography.body?.copyWith(
                          color: FluentTheme.of(context).resources.textFillColorSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            FluentIcons.error,
                            size: 48,
                            color: FluentTheme.of(context).resources.textFillColorSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '加载失败',
                            style: FluentTheme.of(context).typography.bodyLarge?.copyWith(
                              color: FluentTheme.of(context).resources.textFillColorSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              _error!,
                              style: FluentTheme.of(context).typography.caption?.copyWith(
                                color: FluentTheme.of(context).resources.textFillColorTertiary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Button(
                            onPressed: _loadData,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : _fileSystemEpisodes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                FluentIcons.playlist_music,
                                size: 48,
                                color: FluentTheme.of(context).resources.textFillColorSecondary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '播放列表为空',
                                style: FluentTheme.of(context).typography.bodyLarge?.copyWith(
                                  color: FluentTheme.of(context).resources.textFillColorSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _fileSystemEpisodes.length,
                          itemBuilder: (context, index) {
                            final filePath = _fileSystemEpisodes[index];
                            final isCurrentEpisode = filePath == _currentFilePath;
                            final displayName = _getDisplayName(filePath);
                            final subtitle = _getSubtitle(filePath);
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: HoverButton(
                                onPressed: isCurrentEpisode ? null : () => _playEpisode(filePath),
                                builder: (context, states) {
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isCurrentEpisode
                                          ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
                                          : states.isHovered
                                              ? FluentTheme.of(context).resources.subtleFillColorSecondary
                                              : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isCurrentEpisode
                                            ? FluentTheme.of(context).accentColor
                                            : FluentTheme.of(context).resources.controlStrokeColorDefault.withValues(alpha: 0.3),
                                        width: isCurrentEpisode ? 1 : 0.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // 播放状态指示器
                                        Container(
                                          width: 4,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: isCurrentEpisode
                                                ? FluentTheme.of(context).accentColor
                                                : FluentTheme.of(context).resources.controlStrokeColorDefault,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                        
                                        const SizedBox(width: 12),
                                        
                                        // 剧集信息
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                displayName,
                                                style: FluentTheme.of(context).typography.body?.copyWith(
                                                  color: isCurrentEpisode
                                                      ? FluentTheme.of(context).accentColor
                                                      : FluentTheme.of(context).resources.textFillColorPrimary,
                                                  fontWeight: isCurrentEpisode ? FontWeight.w600 : FontWeight.normal,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                subtitle,
                                                style: FluentTheme.of(context).typography.caption?.copyWith(
                                                  color: isCurrentEpisode
                                                      ? FluentTheme.of(context).accentColor.withValues(alpha: 0.8)
                                                      : FluentTheme.of(context).resources.textFillColorSecondary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        
                                        // 播放状态图标
                                        if (isCurrentEpisode)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8),
                                            child: Icon(
                                              FluentIcons.play_solid,
                                              size: 16,
                                              color: FluentTheme.of(context).accentColor,
                                            ),
                                          )
                                        else if (!isCurrentEpisode && states.isHovered)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8),
                                            child: Icon(
                                              FluentIcons.play,
                                              size: 16,
                                              color: FluentTheme.of(context).resources.textFillColorSecondary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}