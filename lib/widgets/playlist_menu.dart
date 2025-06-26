import 'package:flutter/material.dart';
import 'dart:ui';
import '../utils/video_player_state.dart';
import 'package:provider/provider.dart';
import '../utils/globals.dart' as globals;
import 'base_settings_menu.dart';
import 'dart:io';
import '../services/jellyfin_service.dart';
import '../services/jellyfin_episode_mapping_service.dart';
import '../services/dandanplay_service.dart';
import '../models/jellyfin_model.dart';
import '../models/watch_history_model.dart';

class PlaylistMenu extends StatefulWidget {
  final VoidCallback onClose;

  const PlaylistMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<PlaylistMenu> createState() => _PlaylistMenuState();
}

class _PlaylistMenuState extends State<PlaylistMenu> {
  // 文件系统数据
  List<String> _fileSystemEpisodes = [];
  
  // Jellyfin剧集信息缓存 (episodeId -> episode info)
  final Map<String, dynamic> _jellyfinEpisodeCache = {};
  
  bool _isLoading = true;
  String? _error;
  String? _currentFilePath;
  String? _currentAnimeTitle;
  
  // 可用的数据源
  bool _hasFileSystemData = false;

  @override
  void initState() {
    super.initState();
    _loadFileSystemData();
  }

  Future<void> _loadFileSystemData() async {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _currentFilePath = videoState.currentVideoPath;
      _currentAnimeTitle = videoState.animeTitle;
      
      debugPrint('[播放列表] 开始加载文件系统数据');
      debugPrint('[播放列表] _currentFilePath: $_currentFilePath');
      debugPrint('[播放列表] _currentAnimeTitle: $_currentAnimeTitle');
      
      if (_currentFilePath != null) {
        // 检查是否为Jellyfin流媒体URL
        if (_currentFilePath!.startsWith('jellyfin://')) {
          await _loadJellyfinEpisodes();
          return; // 直接返回，不执行本地文件逻辑
        }
        
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
          
          debugPrint('[播放列表] 找到 ${_fileSystemEpisodes.length} 个视频文件');
        }
      }

      if (!_hasFileSystemData) {
        throw Exception('目录中没有找到视频文件');
      }

      setState(() {
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('[播放列表] 加载文件系统数据失败: $e');
      setState(() {
        _error = '加载播放列表失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadJellyfinEpisodes() async {
    try {
      // 解析当前的Jellyfin URL获取episodeId
      final episodeId = _currentFilePath!.replaceFirst('jellyfin://', '');
      
      // 通过episodeId获取剧集详情，然后获取同一季的所有剧集
      final episodeInfo = await JellyfinService.instance.getEpisodeDetails(episodeId);
      if (episodeInfo == null) {
        throw Exception('无法获取Jellyfin剧集信息');
      }
      
      // 获取该季的所有剧集
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
      
      debugPrint('[播放列表] Jellyfin模式: 找到 ${_fileSystemEpisodes.length} 个剧集');
      
      setState(() {
        _isLoading = false;
      });
      
    } catch (e) {
      debugPrint('[播放列表] 加载Jellyfin剧集失败: $e');
      setState(() {
        _error = '加载Jellyfin播放列表失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _playEpisode(String filePath) async {
    try {
      debugPrint('[播放列表] 开始播放剧集: $filePath');
      
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);

      if (mounted) {
        // 检查是否为Jellyfin URL
        if (filePath.startsWith('jellyfin://')) {
          // Jellyfin流媒体模式：使用完整的弹幕映射和API获取逻辑
          final episodeId = filePath.replaceFirst('jellyfin://', '');
          final episodeInfo = await JellyfinService.instance.getEpisodeDetails(episodeId);
          
          if (episodeInfo == null) {
            throw Exception('无法获取Jellyfin剧集信息');
          }
          
          // 获取实际的流媒体URL
          final actualUrl = JellyfinService.instance.getStreamUrl(episodeId);
          debugPrint('[播放列表] 获取Jellyfin流媒体URL: $actualUrl');
          
          // 尝试获取弹幕映射
          int? animeId;
          int? episodeIdForDanmaku;
          
          try {
            final mapping = await JellyfinEpisodeMappingService.instance.getEpisodeMapping(episodeId);
            if (mapping != null) {
              animeId = mapping['dandanplay_anime_id'] as int?;
              episodeIdForDanmaku = mapping['dandanplay_episode_id'] as int?;
              debugPrint('[播放列表] 找到剧集弹幕映射: animeId=$animeId, episodeId=$episodeIdForDanmaku');
            } else {
              debugPrint('[播放列表] 未找到剧集弹幕映射，将进行自动匹配');
            }
          } catch (e) {
            debugPrint('[播放列表] 获取剧集弹幕映射失败: $e');
          }
          
          // 创建带有弹幕信息的历史项
          final historyItem = await _createJellyfinHistoryItem(episodeInfo, animeId, episodeIdForDanmaku);
          
          // 按照剧集导航的方式，使用Jellyfin协议URL作为标识符，HTTP URL作为实际播放源
          await videoState.initializePlayer(
            filePath, // 使用Jellyfin协议URL作为标识符
            historyItem: historyItem, 
            actualPlayUrl: actualUrl // HTTP URL作为实际播放源
          );
          debugPrint('[播放列表] Jellyfin剧集播放完成');
        } else {
          // 本地文件模式：保持原有逻辑
          final file = File(filePath);
          if (!file.existsSync()) {
            throw Exception('文件不存在: $filePath');
          }
          
          await videoState.initializePlayer(filePath);
          debugPrint('[播放列表] 文件路径播放完成');
        }
        
        // 播放成功后关闭菜单
        if (mounted) {
          widget.onClose();
        }
      } else {
        debugPrint('[播放列表] 组件已卸载，取消播放');
      }
    } catch (e) {
      debugPrint('[播放列表] 播放剧集失败: $e');
      
      // 发生错误时也要关闭菜单
      if (mounted) {
        widget.onClose();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放失败：$e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _getEpisodeDisplayName(String filePath) {
    // 检查是否为Jellyfin URL
    if (filePath.startsWith('jellyfin://')) {
      final episodeId = filePath.replaceFirst('jellyfin://', '');
      final cachedInfo = _jellyfinEpisodeCache[episodeId];
      if (cachedInfo != null) {
        final indexNumber = cachedInfo['indexNumber'] as int?;
        final name = cachedInfo['name'] as String?;
        if (indexNumber != null && name != null) {
          return '第$indexNumber话 - $name';
        } else if (name != null) {
          return name;
        }
      }
      return 'Episode $episodeId'; // 默认显示
    }
    
    // 本地文件模式：保持原有逻辑
    final fileName = filePath.split('/').last;
    // 移除文件扩展名
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return nameWithoutExt;
  }

  bool _isCurrentEpisode(String filePath) {
    return filePath == _currentFilePath;
  }

  /// 创建Jellyfin历史项，包含完整的弹幕映射预测和API获取的准确信息
  Future<WatchHistoryItem> _createJellyfinHistoryItem(JellyfinEpisodeInfo episode, int? animeId, int? episodeId) async {
    try {
      int? finalAnimeId = animeId;
      int? finalEpisodeId = episodeId;
      
      // 如果没有提供映射的弹幕ID，尝试智能预测
      if (finalAnimeId == null || finalEpisodeId == null) {
        debugPrint('[播放列表] 未提供弹幕映射，开始智能预测');
        
        // 1. 首先尝试获取现有的剧集映射
        final existingMapping = await JellyfinEpisodeMappingService.instance.getEpisodeMapping(episode.id);
        if (existingMapping != null) {
          finalEpisodeId = existingMapping['dandanplay_episode_id'] as int?;
          
          // 通过系列ID获取动画映射
          final animeMapping = await JellyfinEpisodeMappingService.instance.getAnimeMapping(
            jellyfinSeriesId: episode.seriesId!,
            jellyfinSeasonId: episode.seasonId,
          );
          
          if (animeMapping != null) {
            finalAnimeId = animeMapping['dandanplay_anime_id'] as int?;
            debugPrint('[播放列表] 从现有映射获取弹幕ID: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
          }
        } else {
          // 2. 如果没有现有映射，尝试智能预测
          debugPrint('[播放列表] 没有现有映射，开始智能预测映射');
          final predictedEpisodeId = await JellyfinEpisodeMappingService.instance.predictEpisodeMapping(
            jellyfinEpisode: episode,
          );
          
          if (predictedEpisodeId != null) {
            finalEpisodeId = predictedEpisodeId;
            
            // 获取对应的动画ID
            final animeMapping = await JellyfinEpisodeMappingService.instance.getAnimeMapping(
              jellyfinSeriesId: episode.seriesId!,
              jellyfinSeasonId: episode.seasonId,
            );
            
            if (animeMapping != null) {
              finalAnimeId = animeMapping['dandanplay_anime_id'] as int?;
              debugPrint('[播放列表] 预测映射成功: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
            }
          } else {
            debugPrint('[播放列表] 智能预测失败，将使用基础信息创建历史项');
          }
        }
      }
      
      // 如果有映射的弹幕ID，使用DanDanPlay API获取正确的剧集信息
      if (finalAnimeId != null && finalEpisodeId != null) {
        try {
          // 使用DanDanPlay API获取准确的剧集标题，保持标题一致性
          debugPrint('[播放列表] 使用弹幕ID查询剧集信息: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
          
          // 获取动画详情以获取准确的标题
          final bangumiDetails = await DandanplayService.getBangumiDetails(finalAnimeId);
          
          String? animeTitle;
          String? episodeTitle;
          
          if (bangumiDetails['success'] == true && bangumiDetails['bangumi'] != null) {
            final bangumi = bangumiDetails['bangumi'];
            animeTitle = bangumi['animeTitle'] as String?;
            
            // 查找对应的剧集标题
            if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
              final episodes = bangumi['episodes'] as List;
              final targetEpisode = episodes.firstWhere(
                (ep) => ep['episodeId'] == finalEpisodeId,
                orElse: () => null,
              );
              
              if (targetEpisode != null) {
                episodeTitle = targetEpisode['episodeTitle'] as String?;
                debugPrint('[播放列表] 从DanDanPlay API获取到剧集标题: $episodeTitle');
              }
            }
          }
          
          // 创建包含正确弹幕信息和标题的历史项
          return WatchHistoryItem(
            filePath: 'jellyfin://${episode.id}',
            animeName: animeTitle ?? episode.seriesName ?? 'Unknown',
            episodeTitle: episodeTitle ?? episode.name,
            animeId: finalAnimeId,
            episodeId: finalEpisodeId,
            watchProgress: 0.0,
            lastPosition: 0,
            duration: 0,
            lastWatchTime: DateTime.now(),
            thumbnailPath: null,
            isFromScan: false,
          );
        } catch (e) {
          debugPrint('[播放列表] 获取DanDanPlay剧集信息失败: $e，使用基础信息');
        }
      }
      
      // 如果没有映射的弹幕ID或获取失败，使用基础信息创建历史项
      debugPrint('[播放列表] 没有映射的弹幕ID，使用基础信息创建历史项');
      return episode.toWatchHistoryItem();
    } catch (e) {
      debugPrint('[播放列表] 创建历史项时出错：$e，使用基础历史项');
      return episode.toWatchHistoryItem();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseSettingsMenu(
      title: '播放列表',
      onClose: widget.onClose,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 动画标题
          if (_currentAnimeTitle != null)
            Container(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _currentAnimeTitle!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          
          // 内容区域 - 移除固定高度限制
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              '加载播放列表中...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _loadFileSystemData();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (!_hasFileSystemData || _fileSystemEpisodes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              color: Colors.white54,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(
              '目录中没有找到视频文件',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 添加顶部边距
        const SizedBox(height: 8),
        // 使用Column和多个Container替代ListView.builder
        for (int index = 0; index < _fileSystemEpisodes.length; index++)
          Builder(
            builder: (context) {
              final filePath = _fileSystemEpisodes[index];
              final isCurrentEpisode = _isCurrentEpisode(filePath);
              final displayName = _getEpisodeDisplayName(filePath);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isCurrentEpisode 
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.transparent,
                  border: isCurrentEpisode
                      ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1)
                      : null,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(
                    displayName,
                    style: TextStyle(
                      color: isCurrentEpisode ? Colors.white : Colors.white.withValues(alpha: 0.87),
                      fontSize: 14,
                      fontWeight: isCurrentEpisode ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isCurrentEpisode
                      ? const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                  onTap: isCurrentEpisode
                      ? null // 当前剧集不可点击
                      : () => _playEpisode(filePath),
                  enabled: !isCurrentEpisode,
                ),
              );
            },
          ),
        // 添加底部边距，确保最后一项不被遮挡
        const SizedBox(height: 16),
      ],
    );
  }
}