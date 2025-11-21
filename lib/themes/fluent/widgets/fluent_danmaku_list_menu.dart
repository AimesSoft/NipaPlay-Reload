import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'dart:async';

class FluentDanmakuListMenu extends StatefulWidget {
  final VideoPlayerState videoState;

  const FluentDanmakuListMenu({
    super.key,
    required this.videoState,
  });

  @override
  State<FluentDanmakuListMenu> createState() => _FluentDanmakuListMenuState();
}

class _FluentDanmakuListMenuState extends State<FluentDanmakuListMenu> {
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _allSortedDanmakus = [];
  List<Map<String, dynamic>> _visibleDanmakus = [];
  List<Map<String, dynamic>> _danmakuList = [];
  
  bool _isLoading = true;
  String _errorMessage = '';
  Timer? _refreshTimer;
  int _currentDanmakuIndex = -1;
  int _currentTimeMs = 0;
  bool _showFilteredDanmaku = false;
  
  // 虚拟滚动参数
  final int _windowSize = 200;
  final int _bufferSize = 100;
  int _windowStartIndex = 0;
  bool _isLoadingWindow = false;
  final double _estimatedItemHeight = 60.0;

  @override
  void initState() {
    super.initState();
    
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _loadDanmakuList();
      }
    });
    
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        _updateCurrentDanmaku();
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
    if (_isLoadingWindow || _allSortedDanmakus.isEmpty) return;
    
    final scrollPosition = _scrollController.position.pixels;
    final isNearTop = scrollPosition < 500;
    final isNearBottom = _scrollController.position.maxScrollExtent - scrollPosition < 500;
    
    if (isNearTop && _windowStartIndex > 0) {
      int newStartIndex = (_windowStartIndex - _bufferSize).clamp(0, _allSortedDanmakus.length - 1);
      _updateVisibleWindow(newStartIndex);
    } else if (isNearBottom && _windowStartIndex + _visibleDanmakus.length < _allSortedDanmakus.length) {
      int newStartIndex = _windowStartIndex;
      if (_visibleDanmakus.length >= _windowSize) {
        newStartIndex = _windowStartIndex + (_bufferSize ~/ 2);
      }
      _updateVisibleWindow(newStartIndex);
    }
  }

  void _loadDanmakuList() {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      _danmakuList = List<Map<String, dynamic>>.from(widget.videoState.danmakuList);
      
      if (_danmakuList.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '没有可用的弹幕数据';
        });
        return;
      }

      // 按时间排序弹幕
      _danmakuList.sort((a, b) {
        final timeA = _parseDanmakuTime(a);
        final timeB = _parseDanmakuTime(b);
        return timeA.compareTo(timeB);
      });

      _allSortedDanmakus = _showFilteredDanmaku ? _danmakuList : _danmakuList.where(_isDanmakuVisible).toList();
      
      setState(() {
        _isLoading = false;
        
        final nearestIndex = _findNearestDanmakuIndex(_currentTimeMs);
        _initializeVisibleWindow(nearestIndex);
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载弹幕列表失败: $e';
      });
    }
  }

  int _parseDanmakuTime(Map<String, dynamic> danmaku) {
    try {
      final timeStr = danmaku['time']?.toString() ?? '0';
      return (double.parse(timeStr) * 1000).round();
    } catch (e) {
      return 0;
    }
  }

  bool _isDanmakuVisible(Map<String, dynamic> danmaku) {
    final content = danmaku['content']?.toString() ?? '';
    return !widget.videoState.danmakuBlockWords.any((word) => content.contains(word));
  }

  String _formatTime(int timeMs) {
    final seconds = timeMs ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _initializeVisibleWindow(int centerIndex) {
    _windowStartIndex = (centerIndex - _windowSize ~/ 2).clamp(0, _allSortedDanmakus.length - _windowSize);
    if (_windowStartIndex < 0) _windowStartIndex = 0;
    
    int windowEndIndex = _windowStartIndex + _windowSize;
    if (windowEndIndex > _allSortedDanmakus.length) {
      windowEndIndex = _allSortedDanmakus.length;
      _windowStartIndex = (windowEndIndex - _windowSize).clamp(0, windowEndIndex);
    }
    
    _visibleDanmakus = _allSortedDanmakus.sublist(_windowStartIndex, windowEndIndex);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final localIndex = centerIndex - _windowStartIndex;
        if (localIndex >= 0 && localIndex < _visibleDanmakus.length) {
          final targetPosition = localIndex * _estimatedItemHeight;
          _scrollController.jumpTo(targetPosition);
        }
      }
    });
  }

  void _updateVisibleWindow(int newStartIndex) {
    if (_isLoadingWindow || _allSortedDanmakus.isEmpty) return;
    
    setState(() {
      _isLoadingWindow = true;
    });
    
    newStartIndex = newStartIndex.clamp(0, _allSortedDanmakus.length - 1);
    int newEndIndex = (newStartIndex + _windowSize * 2).clamp(0, _allSortedDanmakus.length);
    
    setState(() {
      if (newStartIndex != _windowStartIndex) {
        _windowStartIndex = newStartIndex;
        _visibleDanmakus = _allSortedDanmakus.sublist(newStartIndex, newEndIndex);
      } else if (newEndIndex > _windowStartIndex + _visibleDanmakus.length) {
        final additionalDanmakus = _allSortedDanmakus.sublist(
          _windowStartIndex + _visibleDanmakus.length,
          newEndIndex
        );
        _visibleDanmakus.addAll(additionalDanmakus);
      }
      
      _isLoadingWindow = false;
    });
  }

  int _findNearestDanmakuIndex(int currentTimeMs) {
    if (_allSortedDanmakus.isEmpty) return 0;
    
    for (int i = 0; i < _allSortedDanmakus.length; i++) {
      final danmakuTime = _parseDanmakuTime(_allSortedDanmakus[i]);
      if (danmakuTime >= currentTimeMs) {
        return i;
      }
    }
    
    return _allSortedDanmakus.length - 1;
  }

  void _updateCurrentDanmaku() {
    if (!mounted) return;
    
    final currentPositionMs = widget.videoState.position.inMilliseconds;
    _currentTimeMs = currentPositionMs;
    
    if (_allSortedDanmakus.isEmpty) return;
    
    final globalIndex = _findNearestDanmakuIndex(currentPositionMs);
    final localIndex = globalIndex - _windowStartIndex;
    final isInVisibleWindow = localIndex >= 0 && localIndex < _visibleDanmakus.length;
    
    if (!isInVisibleWindow) {
      _updateVisibleWindow(globalIndex - (_windowSize ~/ 2));
      return;
    }
    
    if (localIndex != _currentDanmakuIndex) {
      setState(() {
        _currentDanmakuIndex = localIndex;
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

  Color _getDanmakuTypeColor(int type) {
    switch (type) {
      case 1: return Colors.blue;      // 滚动弹幕
      case 4: return Colors.green;     // 底部弹幕
      case 5: return Colors.orange;    // 顶部弹幕
      default: return Colors.grey;
    }
  }

  String _getDanmakuTypeName(int type) {
    switch (type) {
      case 1: return '滚动';
      case 4: return '底部';
      case 5: return '顶部';
      default: return '其他';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 提示信息和过滤开关
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '弹幕列表 ${_allSortedDanmakus.isNotEmpty ? "(${_allSortedDanmakus.length}条)" : ""}',
                        style: FluentTheme.of(context).typography.bodyStrong,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '点击任意弹幕可跳转到对应时间',
                        style: FluentTheme.of(context).typography.caption?.copyWith(
                          color: FluentTheme.of(context).resources.textFillColorTertiary,
                        ),
                      ),
                    ],
                  ),
                  ToggleSwitch(
                    checked: _showFilteredDanmaku,
                    onChanged: (value) {
                      setState(() {
                        _showFilteredDanmaku = value;
                      });
                      _loadDanmakuList();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _showFilteredDanmaku ? '显示所有弹幕（包含被屏蔽的）' : '只显示可见弹幕',
                style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: FluentTheme.of(context).resources.textFillColorSecondary,
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
        
        // 弹幕列表内容
        Expanded(
          child: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const ProgressRing(strokeWidth: 3),
                      const SizedBox(height: 16),
                      Text(
                        '加载弹幕中...',
                        style: FluentTheme.of(context).typography.body?.copyWith(
                          color: FluentTheme.of(context).resources.textFillColorSecondary,
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
                  : _allSortedDanmakus.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                FluentIcons.comment,
                                size: 48,
                                color: FluentTheme.of(context).resources.textFillColorSecondary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '没有弹幕数据',
                                style: FluentTheme.of(context).typography.bodyLarge?.copyWith(
                                  color: FluentTheme.of(context).resources.textFillColorSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '请先加载弹幕或检查弹幕源设置',
                                style: FluentTheme.of(context).typography.caption?.copyWith(
                                  color: FluentTheme.of(context).resources.textFillColorTertiary,
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
                              itemCount: _visibleDanmakus.length,
                              itemBuilder: (context, index) {
                                final danmaku = _visibleDanmakus[index];
                                final isCurrentDanmaku = index == _currentDanmakuIndex;
                                final content = danmaku['content']?.toString() ?? '';
                                final timeMs = _parseDanmakuTime(danmaku);
                                final type = int.tryParse(danmaku['type']?.toString() ?? '1') ?? 1;
                                final isFiltered = !_isDanmakuVisible(danmaku);
                                
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: HoverButton(
                                    onPressed: () => _seekToTime(timeMs),
                                    builder: (context, states) {
                                      return Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isCurrentDanmaku
                                              ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
                                              : states.isHovered
                                                  ? FluentTheme.of(context).resources.subtleFillColorSecondary
                                                  : Colors.transparent,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: isCurrentDanmaku
                                                ? FluentTheme.of(context).accentColor
                                                : FluentTheme.of(context).resources.controlStrokeColorDefault.withValues(alpha: 0.3),
                                            width: isCurrentDanmaku ? 1 : 0.5,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // 弹幕类型指示器
                                            Container(
                                              width: 4,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: _getDanmakuTypeColor(type),
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                            
                                            const SizedBox(width: 12),
                                            
                                            // 弹幕内容
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // 时间戳和类型
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        FluentIcons.clock,
                                                        size: 12,
                                                        color: isCurrentDanmaku
                                                            ? FluentTheme.of(context).accentColor
                                                            : FluentTheme.of(context).resources.textFillColorSecondary,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        _formatTime(timeMs),
                                                        style: FluentTheme.of(context).typography.caption?.copyWith(
                                                          color: isCurrentDanmaku
                                                              ? FluentTheme.of(context).accentColor
                                                              : FluentTheme.of(context).resources.textFillColorSecondary,
                                                          fontWeight: isCurrentDanmaku ? FontWeight.w600 : FontWeight.normal,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: _getDanmakuTypeColor(type).withValues(alpha: 0.2),
                                                          borderRadius: BorderRadius.circular(2),
                                                        ),
                                                        child: Text(
                                                          _getDanmakuTypeName(type),
                                                          style: FluentTheme.of(context).typography.caption?.copyWith(
                                                            color: _getDanmakuTypeColor(type),
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                      ),
                                                      if (isFiltered) ...[
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.red.withValues(alpha: 0.2),
                                                            borderRadius: BorderRadius.circular(2),
                                                          ),
                                                          child: Text(
                                                            '已屏蔽',
                                                            style: FluentTheme.of(context).typography.caption?.copyWith(
                                                              color: Colors.red,
                                                              fontSize: 10,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  
                                                  const SizedBox(height: 4),
                                                  
                                                  // 弹幕内容
                                                  Text(
                                                    content,
                                                    style: FluentTheme.of(context).typography.body?.copyWith(
                                                      color: isFiltered
                                                          ? FluentTheme.of(context).resources.textFillColorTertiary
                                                          : isCurrentDanmaku
                                                              ? FluentTheme.of(context).accentColor
                                                              : FluentTheme.of(context).resources.textFillColorPrimary,
                                                      fontWeight: isCurrentDanmaku ? FontWeight.w600 : FontWeight.normal,
                                                      decoration: isFiltered ? TextDecoration.lineThrough : null,
                                                    ),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
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