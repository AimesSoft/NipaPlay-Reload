import 'dart:async';

import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart'
    show AdaptiveButton, AdaptiveButtonSize, AdaptiveButtonStyle;
import 'package:nipaplay/themes/cupertino/widgets/player_menu/adaptive_player_menu_primitives.dart';

import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/utils/subtitle_parser.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoSubtitleListPane extends StatefulWidget {
  const CupertinoSubtitleListPane({
    super.key,
    required this.videoState,
  });

  final VideoPlayerState videoState;

  @override
  State<CupertinoSubtitleListPane> createState() =>
      _CupertinoSubtitleListPaneState();
}

class _CupertinoSubtitleListPaneState extends State<CupertinoSubtitleListPane> {
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
  // 预估每项高度（首次定位后按真实布局校准）
  double _estimatedItemHeight = 74;
  // 当前高亮条目的 Key，用于基于真实 RenderBox 精确定位（估算高度存在偏差）
  final GlobalKey _currentItemKey = GlobalKey();

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

        // 解析完成后再取一次播放位置：打开面板到解析完成之间播放会推进，
        // 用打开时的旧位置会定位到第 0 秒附近（用户反馈"打开后默认从第0秒显示"）。
        _currentTimeMs = widget.videoState.position.inMilliseconds;
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
    int start = (centerIndex - _windowSize ~/ 2)
        .clamp(0, _allEntries.length - 1)
        .toInt();
    int end = (start + _windowSize).clamp(0, _allEntries.length).toInt();

    setState(() {
      _windowStartIndex = start;
      _visibleEntries = _allEntries.sublist(start, end);
      _currentLocalIndex = centerIndex - start;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentItem(centerIndex, animated: false);
    });
  }

  // 精确定位到当前高亮条目（与 nipaplay subtitle_list_menu 同策略）：
  // 估算高度与真实条目高度存在偏差（估算 74px，多行台词约 85~110px），
  // 且随窗口内索引线性放大，直接按估算偏移 jumpTo 会把高亮定位到可视区
  // 之外（用户反馈"需要再滑动才能看到高亮"）。
  // 先用估算高度粗定位，真实布局完成后用 Scrollable.ensureVisible 校正；
  // 若目标条目尚未构建，用实测内容高度校准估算值后重跳一次再校正。
  void _scrollToCurrentItem(int globalIndex, {required bool animated}) {
    final localIndex = (globalIndex - _windowStartIndex)
        .clamp(0, _visibleEntries.length - 1)
        .toInt();

    // 1) 粗定位：按当前估算高度跳转
    if (_scrollController.hasClients) {
      final target = (localIndex * _estimatedItemHeight)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      if ((_scrollController.offset - target).abs() > 1) {
        _scrollController.jumpTo(target);
      }
    }

    // 2) 下一帧基于真实布局精确校正
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _calibrateItemHeight();
      final itemContext = _currentItemKey.currentContext;
      if (itemContext != null) {
        Scrollable.ensureVisible(
          itemContext,
          alignment: 0.3,
          duration:
              animated ? const Duration(milliseconds: 240) : Duration.zero,
          curve: Curves.easeInOut,
        );
        return;
      }

      // 3) 目标条目仍未构建：用校准后的高度重跳，再等一帧做最终校正。
      if (!_scrollController.hasClients) return;
      final target = (localIndex * _estimatedItemHeight)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _currentItemKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.3,
            duration:
                animated ? const Duration(milliseconds: 240) : Duration.zero,
            curve: Curves.easeInOut,
          );
        }
      });
    });
  }

  // 用列表实际内容高度校准估算条目高度：
  // 内容高度 = maxScrollExtent + 视口高度，平均条目高度 = 内容高度 / 条目数。
  void _calibrateItemHeight() {
    if (!_scrollController.hasClients || _visibleEntries.isEmpty) return;
    final position = _scrollController.position;
    if (position.viewportDimension <= 0 || position.maxScrollExtent <= 0) {
      return;
    }
    final contentHeight = position.maxScrollExtent + position.viewportDimension;
    final measured = contentHeight / _visibleEntries.length;
    if (measured > 0 &&
        (measured - _estimatedItemHeight).abs() / _estimatedItemHeight > 0.05) {
      _estimatedItemHeight = measured;
    }
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
    // 语义：高亮"正在显示/刚刚播过"的台词。
    // 1) 播放位置落在某条 [start,end] 区间内 → 该条；
    // 2) 处于台词间隙 → 已开始(start<=position)的最后一条。
    // 旧实现返回首条 startTimeMs>=position 的字幕，会跳过正在播的那条；
    // 台词稀疏时（如乐器段 19:00→21:00 无对白）高亮跑到几分钟后（用户反馈）。
    int lastIndex = 0;
    for (int i = 0; i < _allEntries.length; i++) {
      final entry = _allEntries[i];
      if (positionMs >= entry.startTimeMs && positionMs <= entry.endTimeMs) {
        return i;
      }
      if (entry.startTimeMs <= positionMs) {
        lastIndex = i;
      } else {
        // 字幕按起始时间升序；遇到第一条还没开始的即结束扫描
        return lastIndex;
      }
    }
    return lastIndex;
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
      // 窗口更新后重新定位到当前条目（相对滚动位置保持依赖估算高度，需校正）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToCurrentItem(globalIndex, animated: true);
        }
      });
      return;
    }

    if (localIndex != _currentLocalIndex) {
      setState(() {
        _currentLocalIndex = localIndex;
      });

      // 如果当前字幕不在可见区域，等新布局完成后基于真实位置自动滚动
      // （ensureVisible 只在条目不可见时滚动，且基于实际 RenderBox，
      // 不再依赖估算高度，避免高亮被定位到可视区外）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final itemContext = _currentItemKey.currentContext;
        if (itemContext != null) {
          Scrollable.ensureVisible(
            itemContext,
            alignment: 0.3,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
          );
        }
      });
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
                    child: Text(
                      _allEntries.isEmpty
                          ? '正在解析字幕文件…'
                          : '共 ${_allEntries.length} 条字幕，点击任意条目跳转播放位置',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                          ),
                    ),
                  ),
                  AdaptiveButton(
                    label: '重新解析',
                    style: AdaptiveButtonStyle.glass,
                    size: AdaptiveButtonSize.small,
                    onPressed: _isLoading ? null : _loadSubtitles,
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
                child: AdaptivePlayerMenuProgressIndicator(size: 32),
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
                      key: isCurrent ? _currentItemKey : null,
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      child: AdaptivePlayerMenuActionSurface(
                        onTap: () => _seekToTime(entry.startTimeMs),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? CupertinoTheme.of(context)
                                    .primaryColor
                                    .withValues(alpha: 0.12)
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
                  child: AdaptivePlayerMenuProgressIndicator(size: 20),
                ),
              ),
            ),
          );
        }

        return slivers;
      },
    );
  }
}
