import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'base_settings_menu.dart'; // Import the base menu
import 'dart:async';
import '../utils/globals.dart' as globals;

// Convert to StatefulWidget
class DanmakuListMenu extends StatefulWidget {
  final VoidCallback onClose;

  const DanmakuListMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<DanmakuListMenu> createState() => _DanmakuListMenuState();
}

class _DanmakuListMenuState extends State<DanmakuListMenu> {
  // 滚动控制器
  final ScrollController _scrollController = ScrollController();
  
  // 弹幕数据
  List<Map<String, dynamic>> _allSortedDanmakus = [];
  List<Map<String, dynamic>> _visibleDanmakus = [];
  
  // 状态变量
  bool _isLoading = true;
  String _errorMessage = '';
  Timer? _refreshTimer;
  int _currentDanmakuIndex = -1;
  int _currentTimeMs = 0;
  bool _isAutoScrolling = false;
  bool _showFilteredDanmaku = false; // 是否显示被过滤的弹幕
  
  // 窗口滚动相关参数
  final int _windowSize = 200; // 可见窗口大小
  final int _bufferSize = 100; // 上下缓冲区大小
  int _windowStartIndex = 0; // 当前窗口起始索引
  bool _isLoadingWindow = false;
  
  // 用于计算位置的参数
  final double _estimatedItemHeight = 80.0; // 预估每项高度
  
  @override
  void initState() {
    super.initState();
    
    // 添加调试日志
    debugPrint('DanmakuListMenu: initState - 开始加载弹幕');
    
    // 延迟一点加载，确保VideoPlayerState已完全初始化
    Future.delayed(Duration(milliseconds: 500), () {
      _loadDanmakus();
    });
    
    // 设置定时刷新，跟踪当前播放位置相关的弹幕
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _updateCurrentDanmaku();
    });
    
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }
  
  // 处理滚动事件
  void _handleScroll() {
    if (_isLoadingWindow || _allSortedDanmakus.isEmpty) return;
    
    // 计算当前滚动位置对应的索引
    final scrollPosition = _scrollController.position.pixels;
    final estimatedIndex = (scrollPosition / _estimatedItemHeight).floor();
    
    // 计算滚动到底部或顶部的阈值
    final isNearTop = scrollPosition < 500; // 接近顶部
    final isNearBottom = _scrollController.position.maxScrollExtent - scrollPosition < 500; // 接近底部
    
    // 如果接近顶部或底部，更新窗口
    if (isNearTop && _windowStartIndex > 0) {
      // 向上滚动，显示更多顶部的弹幕
      int newStartIndex = (_windowStartIndex - _bufferSize).clamp(0, _allSortedDanmakus.length - 1);
      _updateVisibleWindow(newStartIndex);
    } else if (isNearBottom && _windowStartIndex + _visibleDanmakus.length < _allSortedDanmakus.length) {
      // 向下滚动，显示更多底部的弹幕
      int newStartIndex = _windowStartIndex;
      // 确保添加新内容但保持部分已有内容
      if (_visibleDanmakus.length >= _windowSize) {
        // 如果当前显示的条目已经达到或超过窗口大小，向下移动窗口
        newStartIndex = _windowStartIndex + (_bufferSize ~/ 2);
      }
      _updateVisibleWindow(newStartIndex);
    }
  }

  // 加载弹幕数据
  Future<void> _loadDanmakus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      _currentTimeMs = videoState.position.inMilliseconds;
      
      // 获取弹幕数据 - 根据_showFilteredDanmaku选择显示全部弹幕还是过滤后的弹幕
      List<Map<String, dynamic>> danmakus;
      if (_showFilteredDanmaku) {
        // 显示全部弹幕（包括被过滤的）
        danmakus = List<Map<String, dynamic>>.from(videoState.danmakuList);
      } else {
        // 只显示未被过滤的弹幕
        danmakus = List<Map<String, dynamic>>.from(videoState.getFilteredDanmakuList());
      }
      
      if (danmakus.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '当前没有弹幕数据';
        });
        return;
      }
      
      // 对弹幕按时间排序
      danmakus.sort((a, b) {
        final timeA = (a['time'] as double?) ?? 0.0;
        final timeB = (b['time'] as double?) ?? 0.0;
        return timeA.compareTo(timeB);
      });
      
      setState(() {
        _allSortedDanmakus = danmakus;
        _isLoading = false;
        
        // 找到当前时间最接近的弹幕索引
        final nearestIndex = _findNearestDanmakuIndex(_currentTimeMs);
        
        // 初始化可见窗口，以当前时间最接近的弹幕为中心
        _initializeVisibleWindow(nearestIndex);
      });
    } catch (e) {
      debugPrint('DanmakuListMenu: 加载弹幕失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '加载弹幕失败: $e';
        });
      }
    }
  }
  
  // 初始化可见窗口
  void _initializeVisibleWindow(int centerIndex) {
    // 计算窗口起始索引，确保不超出边界
    _windowStartIndex = (centerIndex - _windowSize ~/ 2).clamp(0, _allSortedDanmakus.length - _windowSize);
    if (_windowStartIndex < 0) _windowStartIndex = 0;
    
    // 计算窗口结束索引，确保不超出边界
    int windowEndIndex = _windowStartIndex + _windowSize;
    if (windowEndIndex > _allSortedDanmakus.length) {
      windowEndIndex = _allSortedDanmakus.length;
      // 如果总条目不足一个窗口，调整起始索引
      _windowStartIndex = (windowEndIndex - _windowSize).clamp(0, windowEndIndex);
    }
    
    // 更新可见条目
    _visibleDanmakus = _allSortedDanmakus.sublist(_windowStartIndex, windowEndIndex);
    
    // 设置滚动位置到当前时间对应的弹幕
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
  
  // 更新可见窗口
  void _updateVisibleWindow(int newStartIndex) {
    if (_isLoadingWindow || _allSortedDanmakus.isEmpty) return;
    
    setState(() {
      _isLoadingWindow = true;
    });
    
    // 边界检查
    newStartIndex = newStartIndex.clamp(0, _allSortedDanmakus.length - 1);
    
    // 计算窗口结束索引，允许窗口增长
    int newEndIndex = (newStartIndex + _windowSize * 2).clamp(0, _allSortedDanmakus.length);
    
    // 保持当前滚动位置的相对索引
    final currentScrollPosition = _scrollController.hasClients ? _scrollController.position.pixels : 0;
    final currentEstimatedIndex = (currentScrollPosition / _estimatedItemHeight).floor();
    final relativePosition = currentEstimatedIndex - _windowStartIndex;
    
    // 更新窗口索引和可见条目
    setState(() {
      // 如果是新窗口，完全替换
      if (newStartIndex != _windowStartIndex) {
        _windowStartIndex = newStartIndex;
        _visibleDanmakus = _allSortedDanmakus.sublist(newStartIndex, newEndIndex);
      } 
      // 如果是追加内容（向下滚动）
      else if (newEndIndex > _windowStartIndex + _visibleDanmakus.length) {
        // 只添加新内容
        final additionalEntries = _allSortedDanmakus.sublist(
          _windowStartIndex + _visibleDanmakus.length, 
          newEndIndex
        );
        _visibleDanmakus.addAll(additionalEntries);
      }
      
      _isLoadingWindow = false;
    });
    
    // 如果是窗口替换，保持相对滚动位置
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
  
  // 找到离当前时间最近的弹幕索引
  int _findNearestDanmakuIndex(int currentTimeMs) {
    if (_allSortedDanmakus.isEmpty) return 0;
    
    // 将当前时间转换为秒
    final currentTimeSec = currentTimeMs / 1000;
    
    // 查找最接近的弹幕
    int closestIndex = 0;
    double minDistance = double.infinity;
    
    for (int i = 0; i < _allSortedDanmakus.length; i++) {
      final danmaku = _allSortedDanmakus[i];
      final danmakuTime = (danmaku['time'] as double?) ?? 0.0;
      final distance = (danmakuTime - currentTimeSec).abs();
      
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    
    return closestIndex;
  }
  
  // 更新当前高亮的弹幕索引
  void _updateCurrentDanmaku() {
    if (!mounted || _isAutoScrolling) return;
    
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    final currentPositionMs = videoState.position.inMilliseconds;
    _currentTimeMs = currentPositionMs;
    
    // 如果没有弹幕数据，直接返回
    if (_allSortedDanmakus.isEmpty) return;
    
    // 找到当前时间最接近的弹幕全局索引
    final globalIndex = _findNearestDanmakuIndex(currentPositionMs);
    
    // 计算在可见列表中的局部索引
    final localIndex = globalIndex - _windowStartIndex;
    
    // 检查当前弹幕是否在可见窗口中
    final isInVisibleWindow = localIndex >= 0 && localIndex < _visibleDanmakus.length;
    
    // 如果当前弹幕不在可见窗口中，更新窗口
    if (!isInVisibleWindow) {
      _updateVisibleWindow(globalIndex - (_windowSize ~/ 2));
      return;
    }
    
    // 更新高亮索引
    if (localIndex != _currentDanmakuIndex) {
      setState(() {
        _currentDanmakuIndex = localIndex;
      });
      
      // 如果当前弹幕在可见窗口中但不在可见区域，自动滚动到该位置
      if (_scrollController.hasClients) {
        final itemOffset = localIndex * _estimatedItemHeight;
        final visibleStart = _scrollController.offset;
        final visibleEnd = visibleStart + _scrollController.position.viewportDimension;
        
        if (itemOffset < visibleStart || itemOffset > visibleEnd - _estimatedItemHeight) {
          _isAutoScrolling = true;
          _scrollController.animateTo(
            itemOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          ).then((_) {
            _isAutoScrolling = false;
          });
        }
      }
    }
  }
  
  // 跳转到指定时间位置
  void _seekToTime(double timeInSeconds) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    videoState.seekTo(Duration(milliseconds: (timeInSeconds * 1000).toInt()));
  }
  
  // 获取弹幕类型显示文本
  String _getDanmakuTypeText(String? type) {
    switch (type) {
      case 'top': return '顶部';
      case 'bottom': return '底部';
      case 'scroll': return '滚动';
      default: return '滚动';
    }
  }
  
  // 检查弹幕是否被过滤
  bool _isDanmakuFiltered(Map<String, dynamic> danmaku) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    return videoState.shouldBlockDanmaku(danmaku);
  }
  
  // 格式化时间显示
  String _formatTime(double timeInSeconds) {
    final minutes = (timeInSeconds / 60).floor();
    final seconds = (timeInSeconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // 计算字幕列表的适当高度
    final screenHeight = MediaQuery.of(context).size.height;
    final listHeight = globals.isPhone
        ? screenHeight - 150 // 手机屏幕减去标题栏等高度
        : screenHeight - 250; // 桌面屏幕减去标题栏等高度
    
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final totalFilteredCount = videoState.danmakuList.length - videoState.getFilteredDanmakuList().length;
        
        return BaseSettingsMenu(
          title: '弹幕列表 ${_allSortedDanmakus.isNotEmpty ? "(${_allSortedDanmakus.length}条)" : ""}',
          onClose: widget.onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 添加过滤设置开关
              if (totalFilteredCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '显示被过滤的弹幕 (${totalFilteredCount}条)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      Switch(
                        value: _showFilteredDanmaku,
                        onChanged: (value) {
                          setState(() {
                            _showFilteredDanmaku = value;
                          });
                          _loadDanmakus();
                        },
                        activeColor: const Color.fromARGB(255, 255, 255, 255),
                      ),
                    ],
                  ),
                ),
                
              _isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  ),
                )
              : _allSortedDanmakus.isEmpty || _errorMessage.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    child: Center(
                      child: Text(
                        _errorMessage.isEmpty ? '当前没有弹幕' : _errorMessage,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      Container(
                        height: listHeight,
                        child: globals.isPhone 
                          ? ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.only(top: 8, bottom: 16),
                              itemCount: _visibleDanmakus.length,
                              itemBuilder: (context, index) {
                                // 列表项构建代码
                                final danmaku = _visibleDanmakus[index];
                                final timeInSeconds = (danmaku['time'] as double?) ?? 0.0;
                                final content = (danmaku['content'] as String?) ?? '无效弹幕';
                                final type = (danmaku['type'] as String?) ?? 'scroll';
                                final isCurrentDanmaku = index == _currentDanmakuIndex;
                                final isFiltered = _isDanmakuFiltered(danmaku);
                                
                                // 添加在顶部和底部时显示加载更多的逻辑
                                if (index == 0 && _windowStartIndex > 0) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    // 当显示第一项时，考虑加载更上方的内容
                                    if (_scrollController.position.pixels < 100 && !_isLoadingWindow) {
                                      _updateVisibleWindow(_windowStartIndex - _bufferSize);
                                    }
                                  });
                                } else if (index == _visibleDanmakus.length - 1 && 
                                          _windowStartIndex + _visibleDanmakus.length < _allSortedDanmakus.length) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    // 当显示最后一项时，考虑加载更下方的内容
                                    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 100 &&
                                        !_isLoadingWindow) {
                                      _updateVisibleWindow(_windowStartIndex);
                                    }
                                  });
                                }
                                
                                return Material(
                                  color: isCurrentDanmaku 
                                      ? const Color.fromARGB(255, 255, 255, 255).withOpacity(0.3) 
                                      : Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _seekToTime(timeInSeconds),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Colors.white.withOpacity(0.1),
                                            width: 0.5,
                                          ),
                                        ),
                                        // 如果弹幕被过滤，添加背景色
                                        color: isFiltered && _showFilteredDanmaku 
                                            ? Colors.red.withOpacity(0.15) 
                                            : null,
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // 时间和类型
                                          Row(
                                            children: [
                                              Text(
                                                _formatTime(timeInSeconds),
                                                style: TextStyle(
                                                  color: Colors.grey.shade400,
                                                  fontSize: 12,
                                                  fontWeight: isCurrentDanmaku ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  _getDanmakuTypeText(type),
                                                  style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                              const Spacer(),
                                              // 显示过滤状态
                                              if (isFiltered && _showFilteredDanmaku)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    '已过滤',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          // 弹幕内容
                                          Container(
                                            constraints: BoxConstraints(
                                              minHeight: 20,
                                              maxWidth: MediaQuery.of(context).size.width - 50,
                                            ),
                                            child: Text(
                                              content,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: isCurrentDanmaku ? FontWeight.bold : FontWeight.normal,
                                              ),
                                              softWrap: true,
                                              overflow: TextOverflow.visible,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.only(top: 8, bottom: 16),
                                itemCount: _visibleDanmakus.length,
                                itemBuilder: (context, index) {
                                  final danmaku = _visibleDanmakus[index];
                                  final timeInSeconds = (danmaku['time'] as double?) ?? 0.0;
                                  final content = (danmaku['content'] as String?) ?? '无效弹幕';
                                  final type = (danmaku['type'] as String?) ?? 'scroll';
                                  final isCurrentDanmaku = index == _currentDanmakuIndex;
                                  final isFiltered = _isDanmakuFiltered(danmaku);
                                  
                                  // 添加在顶部和底部时显示加载更多的逻辑
                                  if (index == 0 && _windowStartIndex > 0) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      // 当显示第一项时，考虑加载更上方的内容
                                      if (_scrollController.position.pixels < 100 && !_isLoadingWindow) {
                                        _updateVisibleWindow(_windowStartIndex - _bufferSize);
                                      }
                                    });
                                  } else if (index == _visibleDanmakus.length - 1 && 
                                            _windowStartIndex + _visibleDanmakus.length < _allSortedDanmakus.length) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      // 当显示最后一项时，考虑加载更下方的内容
                                      if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 100 &&
                                          !_isLoadingWindow) {
                                        _updateVisibleWindow(_windowStartIndex);
                                      }
                                    });
                                  }
                                  
                                  return Material(
                                    color: isCurrentDanmaku 
                                        ? Colors.blueAccent.withOpacity(0.3) 
                                        : Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _seekToTime(timeInSeconds),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.white.withOpacity(0.1),
                                              width: 0.5,
                                            ),
                                          ),
                                          // 如果弹幕被过滤，添加背景色
                                          color: isFiltered && _showFilteredDanmaku 
                                              ? Colors.red.withOpacity(0.15) 
                                              : null,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // 时间和类型
                                            Row(
                                              children: [
                                                Text(
                                                  _formatTime(timeInSeconds),
                                                  style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                    fontSize: 12,
                                                    fontWeight: isCurrentDanmaku ? FontWeight.bold : FontWeight.normal,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    _getDanmakuTypeText(type),
                                                    style: TextStyle(
                                                      color: Colors.grey.shade400,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                                const Spacer(),
                                                // 显示过滤状态
                                                if (isFiltered && _showFilteredDanmaku)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Text(
                                                      '已过滤',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            // 弹幕内容
                                            Container(
                                              constraints: BoxConstraints(
                                                minHeight: 20,
                                                maxWidth: MediaQuery.of(context).size.width - 50,
                                              ),
                                              child: Text(
                                                content,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: isCurrentDanmaku ? FontWeight.bold : FontWeight.normal,
                                                ),
                                                softWrap: true,
                                                overflow: TextOverflow.visible,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                      ),
                      if (_isLoadingWindow)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
            ],
          ),
        );
      },
    );
  }
} 