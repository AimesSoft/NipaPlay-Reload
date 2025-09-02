import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'dart:async';
import 'dart:io';
import 'package:nipaplay/utils/subtitle_parser.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class SubtitleListMenu extends StatefulWidget {
  final VoidCallback onClose;

  const SubtitleListMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<SubtitleListMenu> createState() => _SubtitleListMenuState();
}

class _SubtitleListMenuState extends State<SubtitleListMenu> {
  final ScrollController _scrollController = ScrollController();
  List<SubtitleEntry> _allSubtitleEntries = []; // 所有字幕条目
  List<SubtitleEntry> _visibleEntries = []; // 当前可见的字幕条目
  bool _isLoading = true;
  String _errorMessage = '';
  Timer? _refreshTimer;
  int _currentSubtitleIndex = -1;
  int _currentTimeMs = 0;
  
  // 窗口滚动相关参数
  final int _windowSize = 100; // 可见窗口大小
  final int _bufferSize = 50; // 上下缓冲区大小
  int _windowStartIndex = 0; // 当前窗口起始索引
  bool _isLoadingWindow = false;
  
  // 用于计算位置的参数
  final double _estimatedItemHeight = 80.0; // 预估每项高度
  
  @override
  void initState() {
    super.initState();
    
    // 延迟一点加载，确保VideoPlayerState已完全初始化
    Future.delayed(const Duration(milliseconds: 500), () {
      // 添加调试日志（移到延迟执行中，避免build过程中触发状态更新）
      debugPrint('SubtitleListMenu: initState - 开始加载字幕');
      _loadSubtitles();
    });
    
    // 设置定时刷新，跟踪当前播放位置相关的字幕
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _updateCurrentSubtitle();
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
    if (_isLoadingWindow || _allSubtitleEntries.isEmpty) return;
    
    // 计算当前滚动位置对应的索引
    final scrollPosition = _scrollController.position.pixels;
    final estimatedIndex = (scrollPosition / _estimatedItemHeight).floor();
    
    // 计算滚动到底部或顶部的阈值
    final isNearTop = scrollPosition < 500; // 接近顶部
    final isNearBottom = _scrollController.position.maxScrollExtent - scrollPosition < 500; // 接近底部
    
    // 如果接近顶部或底部，更新窗口
    if (isNearTop && _windowStartIndex > 0) {
      // 向上滚动，显示更多顶部的字幕
      int newStartIndex = (_windowStartIndex - _bufferSize).clamp(0, _allSubtitleEntries.length - 1);
      _updateVisibleWindow(newStartIndex);
    } else if (isNearBottom && _windowStartIndex + _visibleEntries.length < _allSubtitleEntries.length) {
      // 向下滚动，显示更多底部的字幕
      int newStartIndex = _windowStartIndex;
      // 确保添加新内容但保持部分已有内容
      if (_visibleEntries.length >= _windowSize) {
        // 如果当前显示的条目已经达到或超过窗口大小，向下移动窗口
        newStartIndex = _windowStartIndex + (_bufferSize ~/ 2);
      }
      _updateVisibleWindow(newStartIndex);
    }
  }

  // 加载字幕内容
  Future<void> _loadSubtitles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      _currentTimeMs = videoState.position.inMilliseconds;
      
      // 检查是否有活跃的字幕
      if (videoState.player.activeSubtitleTracks.isEmpty) {
        debugPrint('SubtitleListMenu: 没有活跃的字幕轨道');
        setState(() {
          _isLoading = false;
          _errorMessage = '没有激活的字幕轨道';
        });
        return;
      }
      
      // 获取字幕文件路径
      String? subtitlePath = videoState.getActiveExternalSubtitlePath();
      
      // 打印详细调试信息
      debugPrint('SubtitleListMenu: 字幕路径: $subtitlePath');
      debugPrint('SubtitleListMenu: 活跃轨道: ${videoState.player.activeSubtitleTracks}');
      //debugPrint('SubtitleListMenu: 字幕轨道信息: ${videoState.danmakuTrackInfo}');
      
      // 如果字幕文件存在，尝试直接从文件系统查找匹配的字幕文件
      if (subtitlePath == null || subtitlePath.isEmpty) {
        // 尝试查找视频对应的默认字幕文件
        if (videoState.currentVideoPath != null) {
          final videoFile = File(videoState.currentVideoPath!);
          if (videoFile.existsSync()) {
            final videoDir = videoFile.parent.path;
            final videoName = videoFile.path.split('/').last.split('.').first;
            
            // 常见字幕文件扩展名
            final subtitleExts = ['.srt', '.ass', '.ssa', '.sub'];
            
            // 尝试查找同名字幕文件
            for (final ext in subtitleExts) {
              final potentialPath = '$videoDir/$videoName$ext';
              debugPrint('SubtitleListMenu: 尝试查找字幕文件: $potentialPath');
              if (File(potentialPath).existsSync()) {
                subtitlePath = potentialPath;
                debugPrint('SubtitleListMenu: 找到匹配的字幕文件: $subtitlePath');
                break;
              }
            }
          }
        }
      }
      
      if (subtitlePath != null && subtitlePath.isNotEmpty) {
        debugPrint('SubtitleListMenu: 正在加载外部字幕文件: $subtitlePath');
        
        // 检查文件是否存在
        final subtitleFile = File(subtitlePath);
        if (!subtitleFile.existsSync()) {
          debugPrint('SubtitleListMenu: 字幕文件不存在: $subtitlePath');
          setState(() {
            _isLoading = false;
            _errorMessage = '字幕文件不存在或无法访问: $subtitlePath';
          });
          return;
        }
        
        // 尝试直接解析文件，不使用缓存
        debugPrint('SubtitleListMenu: 开始解析字幕文件...');
        final entries = await SubtitleParser.parseAssFile(subtitlePath);
        debugPrint('SubtitleListMenu: 解析完成，共 ${entries.length} 条字幕');
        
        if (mounted) {
          setState(() {
            _allSubtitleEntries = entries;
            _isLoading = false;
            
            if (entries.isEmpty) {
              _errorMessage = '字幕文件解析后没有内容，可能格式不兼容';
              return;
            }
            
            // 找到当前时间最接近的字幕索引
            final nearestIndex = _findNearestSubtitleIndex(_currentTimeMs);
            
            // 初始化可见窗口，以当前时间最接近的字幕为中心
            _initializeVisibleWindow(nearestIndex);
            
            // 将解析结果缓存到VideoPlayerState中
            if (subtitlePath != null) {
              videoState.preloadSubtitleFile(subtitlePath);
            }
          });
        }
      } else {
        // 处理内嵌字幕
        debugPrint('SubtitleListMenu: 没有找到外部字幕文件，尝试处理内嵌字幕');
        
        // 尝试获取当前字幕文本
        final subtitleText = videoState.getCurrentSubtitleText();
        debugPrint('SubtitleListMenu: 当前字幕文本: $subtitleText');
        
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
        
        // 如果完全无法获取字幕内容
        setState(() {
          _isLoading = false;
          _errorMessage = '无法解析字幕内容，请确保已正确加载字幕文件';
        });
      }
    } catch (e) {
      debugPrint('SubtitleListMenu: 加载字幕失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '加载字幕失败: $e';
        });
      }
    }
  }
  
  // 初始化可见窗口
  void _initializeVisibleWindow(int centerIndex) {
    // 计算窗口起始索引，确保不超出边界
    _windowStartIndex = (centerIndex - _windowSize ~/ 2).clamp(0, _allSubtitleEntries.length - _windowSize);
    if (_windowStartIndex < 0) _windowStartIndex = 0;
    
    // 计算窗口结束索引，确保不超出边界
    int windowEndIndex = _windowStartIndex + _windowSize;
    if (windowEndIndex > _allSubtitleEntries.length) {
      windowEndIndex = _allSubtitleEntries.length;
      // 如果总条目不足一个窗口，调整起始索引
      _windowStartIndex = (windowEndIndex - _windowSize).clamp(0, windowEndIndex);
    }
    
    // 更新可见条目
    _visibleEntries = _allSubtitleEntries.sublist(_windowStartIndex, windowEndIndex);
    
    // 设置滚动位置到当前时间对应的字幕
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
  
  // 更新可见窗口
  void _updateVisibleWindow(int newStartIndex) {
    if (_isLoadingWindow || _allSubtitleEntries.isEmpty) return;
    
    setState(() {
      _isLoadingWindow = true;
    });
    
    // 边界检查
    newStartIndex = newStartIndex.clamp(0, _allSubtitleEntries.length - 1);
    
    // 计算窗口结束索引，允许窗口增长
    int newEndIndex = (newStartIndex + _windowSize * 2).clamp(0, _allSubtitleEntries.length);
    
    // 保持当前滚动位置的相对索引
    final currentScrollPosition = _scrollController.hasClients ? _scrollController.position.pixels : 0;
    final currentEstimatedIndex = (currentScrollPosition / _estimatedItemHeight).floor();
    final relativePosition = currentEstimatedIndex - _windowStartIndex;
    
    // 更新窗口索引和可见条目
    setState(() {
      // 如果是新窗口，完全替换
      if (newStartIndex != _windowStartIndex) {
        _windowStartIndex = newStartIndex;
        _visibleEntries = _allSubtitleEntries.sublist(newStartIndex, newEndIndex);
      } 
      // 如果是追加内容（向下滚动）
      else if (newEndIndex > _windowStartIndex + _visibleEntries.length) {
        // 只添加新内容
        final additionalEntries = _allSubtitleEntries.sublist(
          _windowStartIndex + _visibleEntries.length, 
          newEndIndex
        );
        _visibleEntries.addAll(additionalEntries);
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
  
  // 找到离当前时间最近的字幕索引
  int _findNearestSubtitleIndex(int currentTimeMs) {
    if (_allSubtitleEntries.isEmpty) return 0;
    
    // 首先查找当前时间在字幕时间范围内的索引
    for (int i = 0; i < _allSubtitleEntries.length; i++) {
      final entry = _allSubtitleEntries[i];
      if (currentTimeMs >= entry.startTimeMs && currentTimeMs <= entry.endTimeMs) {
        return i;
      }
    }
    
    // 如果没有匹配的，查找最接近的字幕
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
  
  // 更新当前高亮的字幕索引
  void _updateCurrentSubtitle() {
    if (!mounted) return;
    
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    final currentPositionMs = videoState.position.inMilliseconds;
    _currentTimeMs = currentPositionMs;
    
    // 如果是内嵌字幕且没有外部字幕文件
    final hasActiveSubtitles = videoState.player.activeSubtitleTracks.isNotEmpty;
    final subtitlePath = videoState.getActiveExternalSubtitlePath();
    
    // 对于内嵌字幕，需要定期更新内容
    if (hasActiveSubtitles && subtitlePath == null) {
      final newSubtitleText = videoState.getCurrentSubtitleText();
      
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
    
    // 为外部字幕文件更新高亮索引
    if (_allSubtitleEntries.isEmpty) return;
    
    // 找到当前时间最接近的字幕全局索引
    final globalIndex = _findNearestSubtitleIndex(currentPositionMs);
    
    // 计算在可见列表中的局部索引
    final localIndex = globalIndex - _windowStartIndex;
    
    // 检查当前字幕是否在可见窗口中
    final isInVisibleWindow = localIndex >= 0 && localIndex < _visibleEntries.length;
    
    // 如果当前字幕不在可见窗口中，更新窗口
    if (!isInVisibleWindow) {
      _updateVisibleWindow(globalIndex - (_windowSize ~/ 2));
      return;
    }
    
    // 更新高亮索引
    if (localIndex != _currentSubtitleIndex) {
      setState(() {
        _currentSubtitleIndex = localIndex;
      });
      
      // 如果当前字幕在可见窗口中但不在可见区域，自动滚动到该位置
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
  
  // 跳转到指定时间位置
  void _seekToTime(int timeMs) {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    videoState.seekTo(Duration(milliseconds: timeMs));
  }
  
  // 获取全局索引对应的显示文本（用于调试）
  String _getIndexLabel(int index) {
    return '${_windowStartIndex + index}/${_allSubtitleEntries.length}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // 当前是否有字幕轨道激活
        final hasActiveSubtitles = videoState.player.activeSubtitleTracks.isNotEmpty;
        
        // 计算字幕列表的适当高度
        final screenHeight = MediaQuery.of(context).size.height;
        final listHeight = globals.isPhone
            ? screenHeight - 150 // 手机屏幕减去标题栏等高度
            : screenHeight - 250; // 桌面屏幕减去标题栏等高度
        
        // 估计总滚动高度（用于提供滚动条的正确比例）
        final estimatedTotalHeight = _allSubtitleEntries.length * _estimatedItemHeight;
        final visibleHeight = _visibleEntries.length * _estimatedItemHeight;
        
        return BaseSettingsMenu(
          title: '字幕列表 ${_allSubtitleEntries.isNotEmpty ? "(${_allSubtitleEntries.length}条)" : ""}',
          onClose: widget.onClose,
          content: _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 2,
                  ),
                ),
              )
            : !hasActiveSubtitles
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  child: Center(
                    child: Text(
                      '没有激活的字幕轨道\n请在字幕轨道设置中激活字幕',
                      locale:Locale("zh","CN"),
style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _allSubtitleEntries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    child: Center(
                      child: Text(
                        '当前字幕轨道没有可显示的字幕内容',
                        locale:Locale("zh","CN"),
style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      SizedBox(
                        height: listHeight,
                        child: globals.isPhone
                          ? ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.only(top: 8, bottom: 16),
                              itemCount: _visibleEntries.length,
                              itemBuilder: (context, index) {
                                final entry = _visibleEntries[index];
                                final isCurrentSubtitle = index == _currentSubtitleIndex;
                                
                                // 添加在顶部和底部时显示加载更多的逻辑
                                if (index == 0 && _windowStartIndex > 0) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    // 当显示第一项时，考虑加载更上方的内容
                                    if (_scrollController.position.pixels < 100 && !_isLoadingWindow) {
                                      _updateVisibleWindow(_windowStartIndex - _bufferSize);
                                    }
                                  });
                                } else if (index == _visibleEntries.length - 1 && 
                                          _windowStartIndex + _visibleEntries.length < _allSubtitleEntries.length) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    // 当显示最后一项时，考虑加载更下方的内容
                                    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 100 &&
                                        !_isLoadingWindow) {
                                      _updateVisibleWindow(_windowStartIndex);
                                    }
                                  });
                                }
                                
                                return Material(
                                  color: isCurrentSubtitle 
                                      ? const Color.fromARGB(255, 255, 255, 255).withOpacity(0.15) 
                                      : Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _seekToTime(entry.startTimeMs),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Colors.white.withOpacity(0.1),
                                            width: 0.5,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // 时间戳
                                          Row(
                                            children: [
                                              Text(
                                                entry.formattedStartTime,
                                                locale:Locale("zh","CN"),
style: TextStyle(
                                                  color: Colors.grey.shade400,
                                                  fontSize: 12,
                                                  fontWeight: isCurrentSubtitle ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                              const Text(
                                                ' → ',
                                                locale:Locale("zh","CN"),
style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              Text(
                                                entry.formattedEndTime,
                                                locale:Locale("zh","CN"),
style: TextStyle(
                                                  color: Colors.grey.shade400,
                                                  fontSize: 12,
                                                  fontWeight: isCurrentSubtitle ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                              const Spacer(),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          // 字幕内容
                                          Container(
                                            constraints: BoxConstraints(
                                              minHeight: 20,
                                              maxWidth: MediaQuery.of(context).size.width - 50,
                                            ),
                                            child: Text(
                                              entry.content,
                                              locale:Locale("zh","CN"),
style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: isCurrentSubtitle ? FontWeight.bold : FontWeight.normal,
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
                                itemCount: _visibleEntries.length,
                                itemBuilder: (context, index) {
                                  final entry = _visibleEntries[index];
                                  final isCurrentSubtitle = index == _currentSubtitleIndex;
                                  
                                  // 添加在顶部和底部时显示加载更多的逻辑
                                  if (index == 0 && _windowStartIndex > 0) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      // 当显示第一项时，考虑加载更上方的内容
                                      if (_scrollController.position.pixels < 100 && !_isLoadingWindow) {
                                        _updateVisibleWindow(_windowStartIndex - _bufferSize);
                                      }
                                    });
                                  } else if (index == _visibleEntries.length - 1 && 
                                            _windowStartIndex + _visibleEntries.length < _allSubtitleEntries.length) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      // 当显示最后一项时，考虑加载更下方的内容
                                      if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 100 &&
                                          !_isLoadingWindow) {
                                        _updateVisibleWindow(_windowStartIndex);
                                      }
                                    });
                                  }
                                  
                                  return Material(
                                    color: isCurrentSubtitle 
                                        ? const Color.fromARGB(255, 255, 255, 255).withOpacity(0.15) 
                                        : Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _seekToTime(entry.startTimeMs),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.white.withOpacity(0.1),
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // 时间戳
                                            Row(
                                              children: [
                                                Text(
                                                  entry.formattedStartTime,
                                                  locale:Locale("zh","CN"),
style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.normal,
                                                  ),
                                                ),
                                                Text(
                                                  ' → ',
                                                  locale:Locale("zh","CN"),
style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                Text(
                                                  entry.formattedEndTime,
                                                  locale:Locale("zh","CN"),
style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.normal,
                                                  ),
                                                ),
                                                const Spacer(),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            // 字幕内容
                                            Container(
                                              constraints: BoxConstraints(
                                                minHeight: 20,
                                                maxWidth: MediaQuery.of(context).size.width - 50,
                                              ),
                                              child: Text(
                                                entry.content,
                                                locale:Locale("zh","CN"),
style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: isCurrentSubtitle ? FontWeight.bold : FontWeight.normal,
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
        );
      },
    );
  }
} 