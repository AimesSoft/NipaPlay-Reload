import 'package:flutter/material.dart';
import 'dart:ui';
import '../utils/video_player_state.dart';
import 'package:provider/provider.dart';
import '../utils/globals.dart' as globals;
import 'base_settings_menu.dart';
import 'dart:io';

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

  Future<void> _playEpisode(String filePath) async {
    try {
      debugPrint('[播放列表] 开始播放剧集: $filePath');
      
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);

      if (mounted) {
        // 检查文件是否存在
        final file = File(filePath);
        if (!file.existsSync()) {
          throw Exception('文件不存在: $filePath');
        }
        
        // 先执行播放逻辑
        await videoState.initializePlayer(filePath);
        debugPrint('[播放列表] 文件路径播放完成');
        
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
    final fileName = filePath.split('/').last;
    // 移除文件扩展名
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return nameWithoutExt;
  }

  bool _isCurrentEpisode(String filePath) {
    return filePath == _currentFilePath;
  }

  @override
  Widget build(BuildContext context) {
    // 计算播放列表的适当高度
    final screenHeight = MediaQuery.of(context).size.height;
    final listHeight = globals.isPhone
        ? screenHeight - 150 // 手机屏幕减去标题栏高度
        : screenHeight - 200; // 桌面屏幕减去标题栏高度
    
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
          
          // 内容区域  
          SizedBox(
            height: listHeight,
            child: _buildContent(),
          ),
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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _fileSystemEpisodes.length,
      itemBuilder: (context, index) {
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
    );
  }
} 