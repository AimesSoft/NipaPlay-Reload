import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoDanmakuListPane extends StatefulWidget {
  const CupertinoDanmakuListPane({
    super.key,
    required this.videoState,
    required this.onBack,
  });

  final VideoPlayerState videoState;
  final VoidCallback onBack;

  @override
  State<CupertinoDanmakuListPane> createState() =>
      _CupertinoDanmakuListPaneState();
}

class _CupertinoDanmakuListPaneState extends State<CupertinoDanmakuListPane> {
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _allDanmakus = [];
  List<Map<String, dynamic>> _visibleDanmakus = [];

  bool _isLoading = true;
  bool _showFiltered = false;
  bool _isWindowLoading = false;
  String _errorMessage = '';

  Timer? _refreshTimer;
  int _windowStartIndex = 0;
  int _currentLocalIndex = -1;
  int _currentTimeMs = 0;

  static const int _windowSize = 180;
  static const int _bufferSize = 80;
  static const double _estimatedItemHeight = 68;

  @override
  void initState() {
    super.initState();
    _loadDanmaku();
    _scrollController.addListener(_handleScroll);
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateCurrentDanmaku();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_isWindowLoading || _allDanmakus.isEmpty) return;
    final position = _scrollController.position.pixels;
    final isNearTop = position < 400;
    final isNearBottom =
        _scrollController.position.maxScrollExtent - position < 400;

    if (isNearTop && _windowStartIndex > 0) {
      final newStart = (_windowStartIndex - _bufferSize)
          .clamp(0, _allDanmakus.length - 1)
          .toInt();
      _updateVisibleWindow(newStart);
    } else if (isNearBottom &&
        _windowStartIndex + _visibleDanmakus.length < _allDanmakus.length) {
      int newStart = _windowStartIndex;
      if (_visibleDanmakus.length >= _windowSize) {
        newStart = _windowStartIndex + (_bufferSize ~/ 2);
      }
      _updateVisibleWindow(newStart);
    }
  }

  void _loadDanmaku() {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final danmakus =
          List<Map<String, dynamic>>.from(widget.videoState.danmakuList);
      if (danmakus.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '暂无弹幕数据';
        });
        return;
      }

      danmakus.sort((a, b) {
        final timeA = _parseDanmakuTime(a);
        final timeB = _parseDanmakuTime(b);
        return timeA.compareTo(timeB);
      });

      _allDanmakus = _showFiltered
          ? danmakus
          : danmakus.where(_isDanmakuVisible).toList();

      setState(() {
        _isLoading = false;
      });

      final nearest = _findNearestDanmakuIndex(
        widget.videoState.position.inMilliseconds,
      );
      _initializeWindow(nearest);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载弹幕失败：$e';
      });
    }
  }

  int _parseDanmakuTime(Map<String, dynamic> danmaku) {
    final timeStr = danmaku['time']?.toString() ?? '0';
    return (double.tryParse(timeStr) ?? 0) * 1000 ~/ 1;
  }

  bool _isDanmakuVisible(Map<String, dynamic> danmaku) {
    final text = danmaku['content']?.toString() ?? '';
    return !widget.videoState.danmakuBlockWords
        .any((word) => text.contains(word));
  }

  String _formatTime(int timeMs) {
    final totalSeconds = timeMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _initializeWindow(int centerIndex) {
    int start =
        (centerIndex - _windowSize ~/ 2).clamp(0, _allDanmakus.length - 1);
    int end = (start + _windowSize).clamp(0, _allDanmakus.length);

    setState(() {
      _windowStartIndex = start;
      _visibleDanmakus = _allDanmakus.sublist(start, end);
      _currentLocalIndex = centerIndex - start;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final offset = (_currentLocalIndex.clamp(0, _visibleDanmakus.length - 1) *
          _estimatedItemHeight);
      _scrollController.jumpTo(offset);
    });
  }

  void _updateVisibleWindow(int newStartIndex) {
    if (_isWindowLoading || _allDanmakus.isEmpty) return;

    setState(() => _isWindowLoading = true);

    final int maxStart =
        (_allDanmakus.length - _windowSize).clamp(0, _allDanmakus.length).toInt();
    newStartIndex = newStartIndex.clamp(0, maxStart);
    final int newEnd =
        (newStartIndex + _windowSize).clamp(0, _allDanmakus.length);

    setState(() {
      _windowStartIndex = newStartIndex;
      _visibleDanmakus = _allDanmakus.sublist(newStartIndex, newEnd);
      _isWindowLoading = false;
      _currentLocalIndex =
          _findNearestDanmakuIndex(_currentTimeMs) - _windowStartIndex;
    });
  }

  int _findNearestDanmakuIndex(int currentTimeMs) {
    if (_allDanmakus.isEmpty) return 0;
    for (int i = 0; i < _allDanmakus.length; i++) {
      final time = _parseDanmakuTime(_allDanmakus[i]);
      if (time >= currentTimeMs) return i;
    }
    return _allDanmakus.length - 1;
  }

  void _updateCurrentDanmaku() {
    if (_allDanmakus.isEmpty) return;
    _currentTimeMs = widget.videoState.position.inMilliseconds;
    final globalIndex = _findNearestDanmakuIndex(_currentTimeMs);
    final localIndex = globalIndex - _windowStartIndex;
    final bool insideWindow =
        localIndex >= 0 && localIndex < _visibleDanmakus.length;

    if (!insideWindow) {
      _updateVisibleWindow(globalIndex - _windowSize ~/ 2);
      return;
    }

    if (localIndex != _currentLocalIndex) {
      setState(() => _currentLocalIndex = localIndex);

      if (_scrollController.hasClients) {
        final offset = localIndex * _estimatedItemHeight;
        final visibleStart = _scrollController.offset;
        final visibleEnd =
            visibleStart + _scrollController.position.viewportDimension;

        if (offset < visibleStart ||
            offset > visibleEnd - _estimatedItemHeight) {
          _scrollController.animateTo(
            offset,
            duration: const Duration(milliseconds: 260),
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
    return CupertinoBottomSheetContentLayout(
      controller: _scrollController,
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '弹幕列表',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .navTitleTextStyle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _visibleDanmakus.isEmpty
                          ? '暂无可显示的弹幕'
                          : '共 ${_visibleDanmakus.length} 条（当前视图）',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('显示被屏蔽'),
                    const SizedBox(width: 6),
                    CupertinoSwitch(
                      value: _showFiltered,
                      onChanged: (value) {
                        setState(() => _showFiltered = value);
                        _loadDanmaku();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_isLoading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CupertinoActivityIndicator(radius: 16),
            ),
          )
        else if (_errorMessage.isNotEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _errorMessage,
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final danmaku = _visibleDanmakus[index];
                  final bool isCurrent = index == _currentLocalIndex;
                  final int timeMs = _parseDanmakuTime(danmaku);
                  final String content =
                      danmaku['content']?.toString() ?? '(空弹幕)';
                  final int type =
                      int.tryParse(danmaku['type']?.toString() ?? '1') ?? 1;
                  final bool isFiltered = !_isDanmakuVisible(danmaku);

                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: GestureDetector(
                      onTap: () => _seekToTime(timeMs),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? CupertinoTheme.of(context)
                                  .primaryColor
                                  .withOpacity(0.12)
                              : CupertinoColors.systemGrey6
                                  .resolveFrom(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? CupertinoTheme.of(context).primaryColor
                                : CupertinoColors.separator
                                    .resolveFrom(context),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(CupertinoIcons.clock, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  _formatTime(timeMs),
                                  style: TextStyle(
                                    fontWeight: isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _buildTag(
                                  context,
                                  _danmakuTypeLabel(type),
                                  color: _typeColor(type),
                                ),
                                if (isFiltered) ...[
                                  const SizedBox(width: 6),
                                  _buildTag(
                                    context,
                                    '已屏蔽',
                                    color: CupertinoColors.systemRed,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              content,
                              style: TextStyle(
                                color: isFiltered
                                    ? CupertinoColors.secondaryLabel
                                        .resolveFrom(context)
                                    : null,
                                decoration: isFiltered
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: _visibleDanmakus.length,
              ),
            ),
          ),
        if (_isWindowLoading)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: CupertinoActivityIndicator(radius: 10),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: widget.onBack),
        ),
      ],
    );
  }

  Widget _buildTag(BuildContext context, String text,
      {Color color = CupertinoColors.activeBlue}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _typeColor(int type) {
    switch (type) {
      case 4:
        return CupertinoColors.activeGreen;
      case 5:
        return CupertinoColors.activeOrange;
      default:
        return CupertinoColors.activeBlue;
    }
  }

  String _danmakuTypeLabel(int type) {
    switch (type) {
      case 4:
        return '底部';
      case 5:
        return '顶部';
      default:
        return '滚动';
    }
  }
}
