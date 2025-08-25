import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/utils/subtitle_parser.dart';
import 'dart:async';

class FluentSubtitleListMenu extends StatefulWidget {
  final VideoPlayerState videoState;

  const FluentSubtitleListMenu({
    super.key,
    required this.videoState,
  });

  @override
  State<FluentSubtitleListMenu> createState() => _FluentSubtitleListMenuState();
}

class _FluentSubtitleListMenuState extends State<FluentSubtitleListMenu> {
  final SubtitleService _subtitleService = SubtitleService();
  final ScrollController _scrollController = ScrollController();
  List<SubtitleEntry> _allSubtitleEntries = [];
  List<SubtitleEntry> _visibleEntries = [];
  bool _isLoading = true;
  String _errorMessage = '';
  Timer? _refreshTimer;
  int _currentSubtitleIndex = -1;
  int _currentTimeMs = 0;

  // 虚拟滚动参数
  final int _windowSize = 100;
  final int _bufferSize = 50;
  int _windowStartIndex = 0;
  bool _isLoadingWindow = false;
  final double _estimatedItemHeight = 80.0;

  @override
  void initState() {
    super.initState();
    
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _loadSubtitles();
      }
    });
    
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        _updateCurrentSubtitle();
      }
    });
    
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_isLoadingWindow || _allSubtitleEntries.isEmpty) return;
    
    final scrollPosition = _scrollController.position.pixels;
    final isNearTop = scrollPosition < 500;
    final isNearBottom = _scrollController.position.maxScrollExtent - scrollPosition < 500;
    
    if (isNearTop && _windowStartIndex > 0) {
      int newStartIndex = (_windowStartIndex - _bufferSize).clamp(0, _allSubtitleEntries.length - 1);
      _updateVisibleWindow(newStartIndex);
    } else if (isNearBottom && _windowStartIndex + _visibleEntries.length < _allSubtitleEntries.length) {
      int newStartIndex = _windowStartIndex;
      if (_visibleEntries.length >= _windowSize) {
        newStartIndex = _windowStartIndex + (_bufferSize ~/ 2);
      }
      _updateVisibleWindow(newStartIndex);
    }
  }

  Future<void> _loadSubtitles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      _currentTimeMs = widget.videoState.position.inMilliseconds;
      
      if (widget.videoState.player.activeSubtitleTracks.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '没有激活的字幕轨道';
        });
        return;
      }
      
      String? subtitlePath = widget.videoState.getActiveExternalSubtitlePath();
      
      if (subtitlePath == null || subtitlePath.isEmpty) {
        // 尝试查找默认字幕文件
        if (widget.videoState.currentVideoPath != null) {
          subtitlePath = _subtitleService.findDefaultSubtitleFile(widget.videoState.currentVideoPath!);
        }
      }
      
      if (subtitlePath != null && subtitlePath.isNotEmpty) {
        final entries = await _subtitleService.parseSubtitleFile(subtitlePath);
        
        if (mounted) {
          setState(() {
            _allSubtitleEntries = entries;
            _isLoading = false;
            
            if (entries.isEmpty) {
              _errorMessage = '字幕文件解析后没有内容，可能格式不兼容';
              return;
            }
            
            final nearestIndex = _findNearestSubtitleIndex(_currentTimeMs);
            _initializeVisibleWindow(nearestIndex);
          });
        }
      } else {
        // 处理内嵌字幕
        final subtitleText = widget.videoState.getCurrentSubtitleText();
        
        if (subtitleText.isNotEmpty) {
          final currentEntry = SubtitleEntry(
            startTimeMs: _currentTimeMs - 1000,
            endTimeMs: _currentTimeMs + 4000,
            content: subtitleText,
          );
          
          setState(() {
            _allSubtitleEntries = [currentEntry];
            _visibleEntries = [currentEntry];
            _currentSubtitleIndex = 0;
            _isLoading = false;
          });
          return;
        }
        
        setState(() {
          _isLoading = false;
          _errorMessage = '无法解析字幕内容，请确保已正确加载字幕文件';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '加载字幕失败: $e';
        });
      }
    }
  }

  void _initializeVisibleWindow(int centerIndex) {
    _windowStartIndex = (centerIndex - _windowSize ~/ 2).clamp(0, _allSubtitleEntries.length - _windowSize);
    if (_windowStartIndex < 0) _windowStartIndex = 0;
    
    int windowEndIndex = _windowStartIndex + _windowSize;
    if (windowEndIndex > _allSubtitleEntries.length) {
      windowEndIndex = _allSubtitleEntries.length;
      _windowStartIndex = (windowEndIndex - _windowSize).clamp(0, windowEndIndex);
    }
    
    _visibleEntries = _allSubtitleEntries.sublist(_windowStartIndex, windowEndIndex);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final localIndex = centerIndex - _windowStartIndex;
        if (localIndex >= 0 && localIndex < _visibleEntries.length) {
          final targetPosition = localIndex * _estimatedItemHeight;
          _scrollController.jumpTo(targetPosition);
        }
      }
    });
  }

  void _updateVisibleWindow(int newStartIndex) {
    if (_isLoadingWindow || _allSubtitleEntries.isEmpty) return;
    
    setState(() {
      _isLoadingWindow = true;
    });
    
    newStartIndex = newStartIndex.clamp(0, _allSubtitleEntries.length - 1);
    int newEndIndex = (newStartIndex + _windowSize * 2).clamp(0, _allSubtitleEntries.length);
    
    final currentScrollPosition = _scrollController.hasClients ? _scrollController.position.pixels : 0;
    final currentEstimatedIndex = (currentScrollPosition / _estimatedItemHeight).floor();
    final relativePosition = currentEstimatedIndex - _windowStartIndex;
    
    setState(() {
      if (newStartIndex != _windowStartIndex) {
        _windowStartIndex = newStartIndex;
        _visibleEntries = _allSubtitleEntries.sublist(newStartIndex, newEndIndex);
      } else if (newEndIndex > _windowStartIndex + _visibleEntries.length) {
        final additionalEntries = _allSubtitleEntries.sublist(
          _windowStartIndex + _visibleEntries.length, 
          newEndIndex
        );
        _visibleEntries.addAll(additionalEntries);
      }
      
      _isLoadingWindow = false;
    });
    
    if (newStartIndex != _windowStartIndex && relativePosition >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final newScrollPosition = (relativePosition + newStartIndex) * _estimatedItemHeight;
          if (newScrollPosition != currentScrollPosition) {
            _scrollController.jumpTo(newScrollPosition);
          }
        }
      });
    }
  }

  int _findNearestSubtitleIndex(int currentTimeMs) {
    if (_allSubtitleEntries.isEmpty) return 0;
    
    for (int i = 0; i < _allSubtitleEntries.length; i++) {
      final entry = _allSubtitleEntries[i];
      if (currentTimeMs >= entry.startTimeMs && currentTimeMs <= entry.endTimeMs) {
        return i;
      }
    }
    
    int closestIndex = 0;
    int minDistance = -1;
    
    for (int i = 0; i < _allSubtitleEntries.length; i++) {
      final entry = _allSubtitleEntries[i];
      final distance = (entry.startTimeMs - currentTimeMs).abs();
      
      if (minDistance == -1 || distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    
    return closestIndex;
  }

  void _updateCurrentSubtitle() {
    if (!mounted) return;
    
    final currentPositionMs = widget.videoState.position.inMilliseconds;
    _currentTimeMs = currentPositionMs;
    
    final hasActiveSubtitles = widget.videoState.player.activeSubtitleTracks.isNotEmpty;
    final subtitlePath = widget.videoState.getActiveExternalSubtitlePath();
    
    if (hasActiveSubtitles && subtitlePath == null) {
      final newSubtitleText = widget.videoState.getCurrentSubtitleText();
      
      if (newSubtitleText.isNotEmpty) {
        final currentEntry = SubtitleEntry(
          startTimeMs: _currentTimeMs - 1000,
          endTimeMs: _currentTimeMs + 4000,
          content: newSubtitleText,
        );
        
        setState(() {
          _allSubtitleEntries = [currentEntry];
          _visibleEntries = [currentEntry];
          _currentSubtitleIndex = 0;
        });
        return;
      }
    }
    
    if (_allSubtitleEntries.isEmpty) return;
    
    final globalIndex = _findNearestSubtitleIndex(currentPositionMs);
    final localIndex = globalIndex - _windowStartIndex;
    final isInVisibleWindow = localIndex >= 0 && localIndex < _visibleEntries.length;
    
    if (!isInVisibleWindow) {
      _updateVisibleWindow(globalIndex - (_windowSize ~/ 2));
      return;
    }
    
    if (localIndex != _currentSubtitleIndex) {
      setState(() {
        _currentSubtitleIndex = localIndex;
      });
      
      if (_scrollController.hasClients) {
        final itemOffset = localIndex * _estimatedItemHeight;
        final visibleStart = _scrollController.offset;
        final visibleEnd = visibleStart + _scrollController.position.viewportDimension;
        
        if (itemOffset < visibleStart || itemOffset > visibleEnd - _estimatedItemHeight) {
          _scrollController.animateTo(
            itemOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    }
  }

  void _seekToTime(int timeMs) {
    widget.videoState.seekTo(Duration(milliseconds: timeMs));
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveSubtitles = widget.videoState.player.activeSubtitleTracks.isNotEmpty;
    
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
                '字幕列表 ${_allSubtitleEntries.isNotEmpty ? "(${_allSubtitleEntries.length}条)" : ""}',
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
              const SizedBox(height: 4),
              Text(
                '点击任意字幕可跳转到对应时间',
                style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: FluentTheme.of(context).resources.textFillColorTertiary,
                ),
              ),
            ],
          ),
        ),
        
        // 分隔线
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        
        // 字幕列表内容
        Expanded(
          child: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const ProgressRing(strokeWidth: 3),
                      const SizedBox(height: 16),
                      Text(
                        '加载字幕中...',
                        style: FluentTheme.of(context).typography.body?.copyWith(
                          color: FluentTheme.of(context).resources.textFillColorSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : !hasActiveSubtitles
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            FluentIcons.closed_caption,
                            size: 48,
                            color: FluentTheme.of(context).resources.textFillColorSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '没有激活的字幕轨道',
                            style: FluentTheme.of(context).typography.bodyLarge?.copyWith(
                              color: FluentTheme.of(context).resources.textFillColorSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '请在字幕轨道设置中激活字幕',
                            style: FluentTheme.of(context).typography.caption?.copyWith(
                              color: FluentTheme.of(context).resources.textFillColorTertiary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _errorMessage.isNotEmpty
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
                              Text(
                                _errorMessage,
                                style: FluentTheme.of(context).typography.caption?.copyWith(
                                  color: FluentTheme.of(context).resources.textFillColorTertiary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : _allSubtitleEntries.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    FluentIcons.closed_caption,
                                    size: 48,
                                    color: FluentTheme.of(context).resources.textFillColorSecondary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '当前字幕轨道没有可显示的字幕内容',
                                    style: FluentTheme.of(context).typography.bodyLarge?.copyWith(
                                      color: FluentTheme.of(context).resources.textFillColorSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Stack(
                              children: [
                                ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.all(8),
                                  itemCount: _visibleEntries.length,
                                  itemBuilder: (context, index) {
                                    final entry = _visibleEntries[index];
                                    final isCurrentSubtitle = index == _currentSubtitleIndex;
                                    
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: HoverButton(
                                        onPressed: () => _seekToTime(entry.startTimeMs),
                                        builder: (context, states) {
                                          return Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: isCurrentSubtitle
                                                  ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
                                                  : states.isHovered
                                                      ? FluentTheme.of(context).resources.subtleFillColorSecondary
                                                      : Colors.transparent,
                                              borderRadius: BorderRadius.circular(4),
                                              border: isCurrentSubtitle
                                                  ? Border.all(
                                                      color: FluentTheme.of(context).accentColor,
                                                      width: 1,
                                                    )
                                                  : Border.all(
                                                      color: FluentTheme.of(context).resources.controlStrokeColorDefault.withValues(alpha: 0.3),
                                                      width: 0.5,
                                                    ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // 时间戳行
                                                Row(
                                                  children: [
                                                    Icon(
                                                      FluentIcons.clock,
                                                      size: 12,
                                                      color: isCurrentSubtitle
                                                          ? FluentTheme.of(context).accentColor
                                                          : FluentTheme.of(context).resources.textFillColorSecondary,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      entry.formattedStartTime,
                                                      style: FluentTheme.of(context).typography.caption?.copyWith(
                                                        color: isCurrentSubtitle
                                                            ? FluentTheme.of(context).accentColor
                                                            : FluentTheme.of(context).resources.textFillColorSecondary,
                                                        fontWeight: isCurrentSubtitle ? FontWeight.w600 : FontWeight.normal,
                                                      ),
                                                    ),
                                                    Text(
                                                      ' → ',
                                                      style: FluentTheme.of(context).typography.caption?.copyWith(
                                                        color: FluentTheme.of(context).resources.textFillColorTertiary,
                                                      ),
                                                    ),
                                                    Text(
                                                      entry.formattedEndTime,
                                                      style: FluentTheme.of(context).typography.caption?.copyWith(
                                                        color: isCurrentSubtitle
                                                            ? FluentTheme.of(context).accentColor
                                                            : FluentTheme.of(context).resources.textFillColorSecondary,
                                                        fontWeight: isCurrentSubtitle ? FontWeight.w600 : FontWeight.normal,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                // 字幕内容
                                                Text(
                                                  entry.content,
                                                  style: FluentTheme.of(context).typography.body?.copyWith(
                                                    color: isCurrentSubtitle
                                                        ? FluentTheme.of(context).accentColor
                                                        : FluentTheme.of(context).resources.textFillColorPrimary,
                                                    fontWeight: isCurrentSubtitle ? FontWeight.w600 : FontWeight.normal,
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
                                
                                // 加载指示器
                                if (_isLoadingWindow)
                                  Positioned(
                                    top: 16,
                                    right: 16,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: FluentTheme.of(context).resources.solidBackgroundFillColorSecondary,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
                                        ),
                                      ),
                                      child: const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: ProgressRing(strokeWidth: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
        ),
      ],
    );
  }
}