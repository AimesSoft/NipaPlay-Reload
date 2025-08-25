import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:flutter/foundation.dart';

class FluentSubtitleTracksMenu extends StatefulWidget {
  final VideoPlayerState videoState;

  const FluentSubtitleTracksMenu({
    super.key,
    required this.videoState,
  });

  @override
  State<FluentSubtitleTracksMenu> createState() => _FluentSubtitleTracksMenuState();
}

class _FluentSubtitleTracksMenuState extends State<FluentSubtitleTracksMenu> {
  final SubtitleService _subtitleService = SubtitleService();
  List<Map<String, dynamic>> _externalSubtitles = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && widget.videoState.currentVideoPath != null) {
      _loadExternalSubtitles();
    }
  }

  Future<void> _loadExternalSubtitles() async {
    if (widget.videoState.currentVideoPath == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      final subtitles = await _subtitleService.loadExternalSubtitles(widget.videoState.currentVideoPath!);
      
      if (mounted) {
        setState(() {
          _externalSubtitles = subtitles;
          _isLoading = false;
        });
        
        // 检查是否有上次激活的字幕需要自动加载
        await _autoLoadLastActiveSubtitle();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorInfo('加载外部字幕失败: $e');
      }
    }
  }

  Future<void> _autoLoadLastActiveSubtitle() async {
    if (widget.videoState.currentVideoPath == null) return;
    
    final lastActiveIndex = await _subtitleService.getLastActiveSubtitleIndex(widget.videoState.currentVideoPath!);
    
    if (lastActiveIndex != null && lastActiveIndex >= 0 && lastActiveIndex < _externalSubtitles.length) {
      final subtitleInfo = _externalSubtitles[lastActiveIndex];
      final path = subtitleInfo['path'] as String;
      
      // 延迟加载，避免初始化冲突
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _applyExternalSubtitle(path, lastActiveIndex);
        }
      });
    }
  }

  Future<void> _loadExternalSubtitleFile() async {
    if (kIsWeb) {
      _showErrorInfo('Web平台不支持加载本地字幕文件');
      return;
    }

    if (widget.videoState.currentVideoPath == null) {
      _showErrorInfo('没有正在播放的视频文件');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final subtitleInfo = await _subtitleService.pickAndLoadSubtitleFile();
      
      if (subtitleInfo == null) {
        setState(() => _isLoading = false);
        return;
      }

      final fileName = subtitleInfo['name'] as String;
      
      // 检查是否已经存在相同路径的字幕
      final existingIndex = _externalSubtitles.indexWhere((s) => s['path'] == subtitleInfo['path']);
      if (existingIndex >= 0) {
        // 已存在，直接应用这个字幕
        await _applyExternalSubtitle(subtitleInfo['path'] as String, existingIndex);
        _showSuccessInfo('已切换到字幕: $fileName');
        setState(() => _isLoading = false);
        return;
      }

      // 添加新字幕
      final success = await _subtitleService.addExternalSubtitle(widget.videoState.currentVideoPath!, subtitleInfo);
      
      if (success) {
        await _loadExternalSubtitles();
        
        // 应用新添加的字幕
        final newIndex = _externalSubtitles.length - 1;
        await _applyExternalSubtitle(subtitleInfo['path'] as String, newIndex);
        
        _showSuccessInfo('已加载字幕文件: $fileName');
      } else {
        _showErrorInfo('添加字幕文件失败');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorInfo('加载字幕文件失败: $e');
    }
  }

  Future<void> _applyExternalSubtitle(String filePath, int index) async {
    try {
      if (widget.videoState.currentVideoPath == null) return;
      
      // 使用字幕服务设置激活状态
      await _subtitleService.setExternalSubtitleActive(widget.videoState.currentVideoPath!, index, true);
      
      // 应用到播放器
      widget.videoState.forceSetExternalSubtitle(filePath);
      
      // 重新加载显示状态
      await _loadExternalSubtitles();
    } catch (e) {
      _showErrorInfo('应用外部字幕失败: $e');
    }
  }

  Future<void> _switchToEmbeddedSubtitle(int trackIndex) async {
    try {
      if (widget.videoState.currentVideoPath != null) {
        // 禁用所有外部字幕
        for (int i = 0; i < _externalSubtitles.length; i++) {
          await _subtitleService.setExternalSubtitleActive(widget.videoState.currentVideoPath!, i, false);
        }
      }
      
      // 清除外部字幕
      widget.videoState.setExternalSubtitle("");
      
      if (trackIndex >= 0) {
        // 切换到指定的内嵌字幕轨道
        widget.videoState.player.activeSubtitleTracks = [trackIndex];
      } else {
        // 关闭字幕
        widget.videoState.player.activeSubtitleTracks = [];
      }
      
      // 重新加载显示状态
      await _loadExternalSubtitles();
    } catch (e) {
      _showErrorInfo('切换到内嵌字幕失败: $e');
    }
  }

  Future<void> _removeExternalSubtitle(int index) async {
    if (widget.videoState.currentVideoPath == null || index < 0 || index >= _externalSubtitles.length) return;
    
    final subtitleInfo = _externalSubtitles[index];
    final fileName = subtitleInfo['name'] as String;
    
    // 如果当前字幕是激活的，先切换回内嵌字幕
    if (subtitleInfo['isActive'] == true) {
      await _switchToEmbeddedSubtitle(-1);
    }
    
    // 从服务中移除
    final success = await _subtitleService.removeExternalSubtitle(widget.videoState.currentVideoPath!, index);
    
    if (success) {
      await _loadExternalSubtitles();
      _showSuccessInfo('已移除字幕: $fileName');
    } else {
      _showErrorInfo('移除字幕失败');
    }
  }

  void _showSuccessInfo(String message) {
    displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: const Text('成功'),
        content: Text(message),
        severity: InfoBarSeverity.success,
        isLong: false,
      );
    });
  }

  void _showErrorInfo(String message) {
    displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: const Text('错误'),
        content: Text(message),
        severity: InfoBarSeverity.error,
        isLong: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final subtitleTracks = widget.videoState.player.mediaInfo.subtitle;
    final hasEmbeddedSubtitles = subtitleTracks != null && subtitleTracks.isNotEmpty;
    
    return Column(
      children: [
        // 提示信息
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '字幕轨道设置',
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
              const SizedBox(height: 4),
              Text(
                '选择字幕轨道或关闭字幕显示',
                style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: FluentTheme.of(context).resources.textFillColorTertiary,
                ),
              ),
            ],
          ),
        ),
        
        // 加载本地字幕文件按钮
        if (!kIsWeb) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _isLoading 
              ? FilledButton(
                  onPressed: null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      const Text('加载中...'),
                    ],
                  ),
                )
              : FilledButton(
                  onPressed: _loadExternalSubtitleFile,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.add, size: 16),
                      const SizedBox(width: 8),
                      const Text('加载本地字幕文件'),
                    ],
                  ),
                ),
          ),
          const SizedBox(height: 16),
        ],
        
        // 分隔线
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              // 关闭字幕选项
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: HoverButton(
                  onPressed: () async {
                    await _switchToEmbeddedSubtitle(-1);
                  },
                  builder: (context, states) {
                    final isActive = widget.videoState.player.activeSubtitleTracks.isEmpty &&
                                   !_externalSubtitles.any((s) => s['isActive'] == true);
                    
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isActive
                            ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
                            : states.isHovered
                                ? FluentTheme.of(context).resources.subtleFillColorSecondary
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: isActive
                            ? Border.all(
                                color: FluentTheme.of(context).accentColor,
                                width: 1,
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isActive ? FluentIcons.radio_btn_on : FluentIcons.radio_btn_off,
                            size: 16,
                            color: isActive
                                ? FluentTheme.of(context).accentColor
                                : FluentTheme.of(context).resources.textFillColorPrimary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '关闭字幕',
                              style: FluentTheme.of(context).typography.body?.copyWith(
                                color: isActive
                                    ? FluentTheme.of(context).accentColor
                                    : FluentTheme.of(context).resources.textFillColorPrimary,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isActive)
                            Icon(
                              FluentIcons.check_mark,
                              size: 16,
                              color: FluentTheme.of(context).accentColor,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              
              // 外部字幕列表
              if (_externalSubtitles.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '外部字幕',
                    style: FluentTheme.of(context).typography.caption?.copyWith(
                      color: FluentTheme.of(context).resources.textFillColorSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ..._externalSubtitles.asMap().entries.map((entry) {
                  final index = entry.key;
                  final subtitle = entry.value;
                  final isActive = subtitle['isActive'] == true;
                  final fileName = subtitle['name'] as String;
                  final fileType = subtitle['type'] as String;
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: HoverButton(
                      onPressed: () async {
                        if (isActive) {
                          await _switchToEmbeddedSubtitle(-1);
                        } else {
                          final filePath = subtitle['path'] as String;
                          await _applyExternalSubtitle(filePath, index);
                        }
                      },
                      builder: (context, states) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isActive
                                ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
                                : states.isHovered
                                    ? FluentTheme.of(context).resources.subtleFillColorSecondary
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: isActive
                                ? Border.all(
                                    color: FluentTheme.of(context).accentColor,
                                    width: 1,
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isActive ? FluentIcons.radio_btn_on : FluentIcons.radio_btn_off,
                                size: 16,
                                color: isActive
                                    ? FluentTheme.of(context).accentColor
                                    : FluentTheme.of(context).resources.textFillColorPrimary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fileName,
                                      style: FluentTheme.of(context).typography.body?.copyWith(
                                        color: isActive
                                            ? FluentTheme.of(context).accentColor
                                            : FluentTheme.of(context).resources.textFillColorPrimary,
                                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '类型: ${fileType.toUpperCase()}',
                                      style: FluentTheme.of(context).typography.caption?.copyWith(
                                        color: isActive
                                            ? FluentTheme.of(context).accentColor.withValues(alpha: 0.8)
                                            : FluentTheme.of(context).resources.textFillColorSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(FluentIcons.delete, size: 16),
                                onPressed: () => _removeExternalSubtitle(index),
                              ),
                              if (isActive)
                                Icon(
                                  FluentIcons.check_mark,
                                  size: 16,
                                  color: FluentTheme.of(context).accentColor,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                }),
              ],
              
              // 内嵌字幕列表
              if (hasEmbeddedSubtitles) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '内嵌字幕',
                    style: FluentTheme.of(context).typography.caption?.copyWith(
                      color: FluentTheme.of(context).resources.textFillColorSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...subtitleTracks.asMap().entries.map((entry) {
                  final index = entry.key;
                  final track = entry.value;
                  
                  final bool hasActiveExternal = _externalSubtitles.any((s) => s['isActive'] == true);
                  final isActive = !hasActiveExternal && widget.videoState.player.activeSubtitleTracks.contains(index);
                  
                  // 获取轨道信息
                  String title = track.title ?? '轨道 ${index + 1}';
                  String language = track.language ?? '未知';
                  
                  if (language != '未知') {
                    language = _subtitleService.getLanguageName(language);
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: HoverButton(
                      onPressed: () async {
                        if (isActive) {
                          await _switchToEmbeddedSubtitle(-1);
                        } else {
                          await _switchToEmbeddedSubtitle(index);
                        }
                      },
                      builder: (context, states) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isActive
                                ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
                                : states.isHovered
                                    ? FluentTheme.of(context).resources.subtleFillColorSecondary
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: isActive
                                ? Border.all(
                                    color: FluentTheme.of(context).accentColor,
                                    width: 1,
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isActive ? FluentIcons.radio_btn_on : FluentIcons.radio_btn_off,
                                size: 16,
                                color: isActive
                                    ? FluentTheme.of(context).accentColor
                                    : FluentTheme.of(context).resources.textFillColorPrimary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: FluentTheme.of(context).typography.body?.copyWith(
                                        color: isActive
                                            ? FluentTheme.of(context).accentColor
                                            : FluentTheme.of(context).resources.textFillColorPrimary,
                                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '语言: $language',
                                      style: FluentTheme.of(context).typography.caption?.copyWith(
                                        color: isActive
                                            ? FluentTheme.of(context).accentColor.withValues(alpha: 0.8)
                                            : FluentTheme.of(context).resources.textFillColorSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isActive)
                                Icon(
                                  FluentIcons.check_mark,
                                  size: 16,
                                  color: FluentTheme.of(context).accentColor,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                }),
              ],
              
              // 没有字幕的情况
              if (!hasEmbeddedSubtitles && _externalSubtitles.isEmpty) ...[
                const SizedBox(height: 32),
                Center(
                  child: Column(
                    children: [
                      Icon(
                        FluentIcons.closed_caption,
                        size: 48,
                        color: FluentTheme.of(context).resources.textFillColorSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '没有可用的字幕轨道',
                        style: FluentTheme.of(context).typography.bodyLarge?.copyWith(
                          color: FluentTheme.of(context).resources.textFillColorSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        kIsWeb 
                            ? '当前视频没有内嵌字幕轨道' 
                            : '当前视频没有内嵌字幕轨道\n点击上方按钮可加载外部字幕文件',
                        style: FluentTheme.of(context).typography.caption?.copyWith(
                          color: FluentTheme.of(context).resources.textFillColorTertiary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}