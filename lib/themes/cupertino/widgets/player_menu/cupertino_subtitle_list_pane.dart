import 'dart:async';

import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/utils/subtitle_parser.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoSubtitleListPane extends StatefulWidget {
  const CupertinoSubtitleListPane({
    super.key,
    required this.videoState,
    required this.onBack,
  });

  final VideoPlayerState videoState;
  final VoidCallback onBack;

  @override
  State<CupertinoSubtitleListPane> createState() =>
      _CupertinoSubtitleListPaneState();
}

class _CupertinoSubtitleListPaneState
    extends State<CupertinoSubtitleListPane> {
  final SubtitleService _subtitleService = SubtitleService();
  final ScrollController _scrollController = ScrollController();

  List<SubtitleEntry> _allEntries = [];
  List<SubtitleEntry> _visibleEntries = [];

  bool _isLoading = true;
  bool _isWindowLoading = false;
  String _errorMessage = '';

  int _windowStartIndex = 0;
  int _currentLocalIndex = -1;
  int _currentTimeMs = 0;

  Timer? _refreshTimer;

  static const int _windowSize = 120;
  static const int _bufferSize = 60;
  static const double _estimatedItemHeight = 74;

  @override
  void initState() {
    super.initState();
    _loadSubtitles();
    _scrollController.addListener(_handleScroll);
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateCurrentSubtitle();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_isWindowLoading || _allEntries.isEmpty) return;
    final position = _scrollController.position.pixels;
    final isNearTop = position < 400;
    final isNearBottom =
        _scrollController.position.maxScrollExtent - position < 400;

    if (isNearTop && _windowStartIndex > 0) {
      final newStart = (_windowStartIndex - _bufferSize)
          .clamp(0, _allEntries.length - 1)
          .toInt();
      _updateVisibleWindow(newStart);
    } else if (isNearBottom &&
        _windowStartIndex + _visibleEntries.length < _allEntries.length) {
      int newStart = _windowStartIndex;
      if (_visibleEntries.length >= _windowSize) {
        newStart = _windowStartIndex + (_bufferSize ~/ 2);
      }
      _updateVisibleWindow(newStart);
    }
  }

  Future<void> _loadSubtitles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      _currentTimeMs = widget.videoState.position.inMilliseconds;

      if (widget.videoState.player.activeSubtitleTracks.isEmpty &&
          widget.videoState.getActiveExternalSubtitlePath() == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = '当前未启用任何字幕轨道';
        });
        return;
      }

      String? subtitlePath =
          widget.videoState.getActiveExternalSubtitlePath()?.trim();

      subtitlePath ??= widget.videoState.currentVideoPath != null
          ? _subtitleService
              .findDefaultSubtitleFile(widget.videoState.currentVideoPath!)
          : null;

      if (subtitlePath != null && subtitlePath.isNotEmpty) {
        if (subtitlePath.toLowerCase().endsWith('.sup')) {
          setState(() {
            _isLoading = false;
            _errorMessage = '检测到图像字幕 (.sup)，暂不支持内容预览';
          });
          return;
        }

        final entries = await _subtitleService.parseSubtitleFile(subtitlePath);
        if (!mounted) return;
        if (entries.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = '字幕文件为空或解析失败';
          });
          return;
        }

        setState(() {
          _allEntries = entries;
          _isLoading = false;
        });

        final nearestIndex = _findNearestSubtitleIndex(_currentTimeMs);
        _initializeVisibleWindow(nearestIndex);
      } else {
        final inlineText = widget.videoState.getCurrentSubtitleText();
        if (inlineText.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = '无法解析当前字幕内容';
          });
          return;
        }

        final entry = SubtitleEntry(
          startTimeMs: _currentTimeMs,
          endTimeMs: _currentTimeMs + 4000,
          content: inlineText,
        );

        setState(() {
          _allEntries = [entry];
          _visibleEntries = [entry];
          _isLoading = false;
          _currentLocalIndex = 0;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '加载字幕失败：$e';
      });
    }
  }

  void _initializeVisibleWindow(int centerIndex) {
    int start =
        (centerIndex - _windowSize ~/ 2).clamp(0, _allEntries.length - 1).toInt();
    int end = (start + _windowSize).clamp(0, _allEntries.length).toInt();

    setState(() {
      _windowStartIndex = start;
      _visibleEntries = _allEntries.sublist(start, end);
      _currentLocalIndex = centerIndex - start;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = (_currentLocalIndex.clamp(0, _visibleEntries.length - 1) *
          _estimatedItemHeight);
      _scrollController.jumpTo(target);
    });
  }

  void _updateVisibleWindow(int newStartIndex) {
    if (_isWindowLoading || _allEntries.isEmpty) return;
    setState(() => _isWindowLoading = true);

    final int maxStart =
        (_allEntries.length - _windowSize).clamp(0, _allEntries.length).toInt();
    newStartIndex = newStartIndex.clamp(0, maxStart).toInt();
    final int newEndIndex =
        (newStartIndex + _windowSize).clamp(0, _allEntries.length).toInt();

    setState(() {
      _windowStartIndex = newStartIndex;
      _visibleEntries = _allEntries.sublist(newStartIndex, newEndIndex);
      _isWindowLoading = false;
      _currentLocalIndex = (_currentTimeMs == 0)
          ? -1
          : _findNearestSubtitleIndex(_currentTimeMs) - _windowStartIndex;
    });
  }

  int _findNearestSubtitleIndex(int positionMs) {
    if (_allEntries.isEmpty) return 0;
    for (int i = 0; i < _allEntries.length; i++) {
      if (_allEntries[i].startTimeMs >= positionMs) {
        return i;
      }
    }
    return _allEntries.length - 1;
  }

  void _updateCurrentSubtitle() {
    if (!mounted || _allEntries.isEmpty) return;
    final newPositionMs = widget.videoState.position.inMilliseconds;
    _currentTimeMs = newPositionMs;

    final globalIndex = _findNearestSubtitleIndex(newPositionMs);
    final localIndex = globalIndex - _windowStartIndex;
    final bool insideWindow =
        localIndex >= 0 && localIndex < _visibleEntries.length;

    if (!insideWindow) {
      _updateVisibleWindow(globalIndex - _windowSize ~/ 2);
      return;
    }

    if (localIndex != _currentLocalIndex) {
      setState(() {
        _currentLocalIndex = localIndex;
      });

      if (_scrollController.hasClients) {
        final itemOffset = localIndex * _estimatedItemHeight;
        final visibleStart = _scrollController.offset;
        final visibleEnd =
            visibleStart + _scrollController.position.viewportDimension;

        if (itemOffset < visibleStart ||
            itemOffset > visibleEnd - _estimatedItemHeight) {
          _scrollController.animateTo(
            itemOffset,
            duration: const Duration(milliseconds: 240),
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
      sliversBuilder: (context, topSpacing) {
        final slivers = <Widget>[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '字幕预览',
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .navTitleTextStyle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _allEntries.isEmpty
                              ? '正在解析字幕文件…'
                              : '共 ${_allEntries.length} 条字幕，点击任意条目跳转播放位置',
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
                  ),
                  CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    onPressed: _isLoading ? null : _loadSubtitles,
                    child: const Text('重新解析'),
                  ),
                ],
              ),
            ),
          ),
        ];

        if (_isLoading) {
          slivers.add(
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CupertinoActivityIndicator(radius: 16),
              ),
            ),
          );
        } else if (_errorMessage.isNotEmpty) {
          slivers.add(
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      size: 40,
                      color: CupertinoColors.systemYellow.resolveFrom(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '无法显示字幕内容',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _errorMessage,
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .copyWith(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          slivers.add(
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = _visibleEntries[index];
                    final bool isCurrent = index == _currentLocalIndex;
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: GestureDetector(
                        onTap: () => _seekToTime(entry.startTimeMs),
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
                                  Icon(
                                    CupertinoIcons.clock,
                                    size: 14,
                                    color: isCurrent
                                        ? CupertinoTheme.of(context)
                                            .primaryColor
                                        : CupertinoColors.secondaryLabel
                                            .resolveFrom(context),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    entry.formattedStartTime,
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .textStyle
                                        .copyWith(
                                          fontWeight: isCurrent
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '→ ${entry.formattedEndTime}',
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .textStyle
                                        .copyWith(
                                          color: CupertinoColors.secondaryLabel
                                              .resolveFrom(context),
                                          fontSize: 13,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                entry.content.trim().isEmpty
                                    ? '(空字幕)'
                                    : entry.content,
                                style: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle
                                    .copyWith(
                                      fontSize: 15,
                                      fontWeight: isCurrent
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _visibleEntries.length,
                ),
              ),
            ),
          );
        }

        if (_isWindowLoading) {
          slivers.add(
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Center(
                  child: CupertinoActivityIndicator(radius: 10),
                ),
              ),
            ),
          );
        }

        slivers.add(
          SliverToBoxAdapter(
            child: CupertinoPaneBackButton(onPressed: widget.onBack),
          ),
        );

        return slivers;
      },
    );
  }
}
