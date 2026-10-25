import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class ExternalSubtitleOverlay extends StatefulWidget {
  const ExternalSubtitleOverlay({
    super.key,
  });

  @override
  State<ExternalSubtitleOverlay> createState() =>
      _ExternalSubtitleOverlayState();
}

class _ExternalSubtitleOverlayState extends State<ExternalSubtitleOverlay> {
  // 多字幕分块渲染：每条外挂字幕独立一块（独立延迟/位置/手势）。
  // _editingPath = 当前出框编辑的字幕路径；null = 全部隐藏（不拦截
  // 播放器手势：长按倍速/拖动 seek 直达播放器）。
  String? _editingPath;
  bool _longPressMoved = false; // 长按期间是否发生拖动
  double _dragStartPosition = 100.0; // 长按起点字幕垂直位置
  double _dragStartMarginX = 0.0; // 长按起点水平边距
  // 长按拖动不可变起点：onLongPressMoveUpdate 的 offsetFromOrigin 是
  // 相对按下原点的累计值，必须 起点+累计 计算，不能把结果写回起点变量
  // 再叠加（早期版本越拖越飞的根因）。
  double _dragOriginPosition = 100.0;
  double _dragOriginMarginX = 0.0;
  // 编辑态 pan 拖动阈值：轻触（如点击收框）手指微抖不应移动字幕。
  Offset? _panStart;
  bool _panActuallyMoved = false;

  /// 字幕背景（功能区按钮切换；默认无背景；按字幕路径独立）
  final Map<String, bool> _subtitleBgEnabled = {};
  Timer? _twoFingerTimer; // 双指长按识别定时器
  final Map<int, Offset> _pointerStarts = {};
  VideoPlayerState? _boundVideoState;
  Map<String, String> _visibleTexts = const {};

  Map<String, String> _textSnapshot(VideoPlayerState state) {
    if (!state.shouldRenderCurrentExternalSubtitleInApp() ||
        state.shouldHideSubtitlesForScreenshot) {
      return const {};
    }
    final position = state.playbackTimeMs.value.round();
    return {
      for (final path in state.activeExternalSubtitlePaths)
        path: state.overlaySubtitleTextAt(path, position),
    };
  }

  void _handlePlaybackTime() {
    final state = _boundVideoState;
    if (!mounted || state == null || state.isDisposed) return;
    final next = _textSnapshot(state);
    if (mapEquals(next, _visibleTexts)) return;
    setState(() => _visibleTexts = next);
  }

  // 记录编辑框所属的视频路径：换视频/内核热切换重载时自动收框。
  // 否则框在新视频加载完成后立即显示（同名外挂字幕路径仍命中
  // _editingPath），框层（白边框+按钮）随播放进度每帧重建，与同 Stack
  // 的弹幕层反复合成导致弹幕闪烁（用户反馈）。长按出框不受影响。
  String? _boundMediaPath;
  int? _boundPlaybackGeneration;
  // 出框时的字幕文本：编辑期间若切换到下一句，自动收框——否则框随
  // 新文本缩到很小，收框/按钮点不中、拖动锚点也丢失（用户反馈）。
  String? _editingCueText;
  // 字幕轴同步诊断去重
  String _lastLoggedCueKey = '';
  int _lastSyncLogAtMs = 0;
  static const int _syncLogMinIntervalMs = 1000;

  /// 手势上下文的同步收框（点框外/占位框/面板关闭）：postFrame 版本在
  /// 手势路径上要等下一帧才落位，测试与真机都有可感知延迟。
  void _collapseEditBoxNow(VideoPlayerState videoState) {
    if (!mounted || _editingPath == null) return;
    setState(() {
      _editingPath = null;
      _editingCueText = null;
    });
    _stopTwoFingerLongPress();
    if (!videoState.isDisposed) {
      videoState.setSubtitleEditBoxVisible(false);
      videoState.setSubtitleDragActive(false);
    }
  }

  /// 收起编辑框并清理手势拦截标志（在 build 中检测状态变化后调用，
  /// 通过 postFrame 延迟 setState，避免构建期改状态）。
  void _collapseEditBox(VideoPlayerState videoState) {
    if (_editingPath == null) return;
    final editingPath = _editingPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingPath != editingPath) return;
      setState(() {
        _editingPath = null;
        _editingCueText = null;
      });
      _stopTwoFingerLongPress();
      if (!videoState.isDisposed) {
        videoState.setSubtitleEditBoxVisible(false);
        videoState.setSubtitleDragActive(false);
      }
    });
  }

  void _stopTwoFingerLongPress() {
    _twoFingerTimer?.cancel();
    _twoFingerTimer = null;
    _pointerStarts.clear();
  }

  @override
  void dispose() {
    _stopTwoFingerLongPress();
    _boundVideoState?.playbackTimeMs.removeListener(_handlePlaybackTime);
    final videoState = _boundVideoState;
    if (_editingPath != null && videoState != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (videoState.isDisposed) return;
        videoState.setSubtitleEditBoxVisible(false);
        videoState.setSubtitleDragActive(false);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        if (!identical(_boundVideoState, videoState)) {
          _boundVideoState?.playbackTimeMs.removeListener(_handlePlaybackTime);
          _boundVideoState = videoState;
          videoState.playbackTimeMs.addListener(_handlePlaybackTime);
        }
        _visibleTexts = _textSnapshot(videoState);
        final mediaPath = videoState.currentVideoPath;
        final generation = videoState.playbackGeneration;
        if (mediaPath != _boundMediaPath ||
            generation != _boundPlaybackGeneration) {
          _boundMediaPath = mediaPath;
          _boundPlaybackGeneration = generation;
          _collapseEditBox(videoState);
        }
        final paths = videoState.activeExternalSubtitlePaths;
        if (_editingPath != null && !paths.contains(_editingPath)) {
          _collapseEditBox(videoState);
        }
        if (!videoState.shouldRenderCurrentExternalSubtitleInApp()) {
          return const SizedBox.shrink();
        }
        if (videoState.shouldHideSubtitlesForScreenshot) {
          // 截图设置「隐藏字幕」：仅在截图帧合成期间隐藏外挂字幕叠层，
          // 不影响正常观看。
          return const SizedBox.shrink();
        }
        if (paths.isEmpty) {
          return const SizedBox.shrink();
        }
        // 多字幕分块渲染：每条外挂字幕独立一块（独立时轴延迟/位置/手势），
        // ASS+SRT 混挂时各条可单独调轴与摆位。
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final path in paths)
              Positioned.fill(child: _buildPathBlock(videoState, path)),
          ],
        );
      },
    );
  }

  /// 渲染单条外挂字幕块（占满整个舞台，内部按该条字幕的位置对齐）
  Widget _buildPathBlock(VideoPlayerState videoState, String path) {
    final subtitleTimeMs = videoState.playbackTimeMs.value.round() -
        videoState.overlaySubtitleDelayMs(path);
    final subtitleText = _visibleTexts[path] ?? '';

    // 编辑期间字幕切换到下一句：自动收框——否则框随新文本缩到很小，
    // 收框/设置按钮点不中、拖动锚点也丢失（用户反馈）。间隙期
    // （文本为空）不收框，保留占位框作为拖动锚点。
    if (_editingPath == path &&
        _editingCueText != null &&
        subtitleText.trim().isNotEmpty &&
        subtitleText != _editingCueText &&
        !videoState.subtitleDragActive) {
      _collapseEditBox(videoState);
    }

    // 字幕轴同步诊断：每条字幕首次显示时记录一次，用于比对内核间的时间轴
    _logSubtitleSyncOnce(
      videoState: videoState,
      cueKey: '$path|${subtitleText.hashCode}',
      subtitleTimeMs: subtitleTimeMs,
      path: path,
    );

    // 全局字幕设置（透明度/描边/阴影/对齐等）仅作用于内嵌轨（内核渲染），
    // 外挂叠层不读这些值——用固定基线样式，摆位只听本条字幕的
    // pathSubtitlePosition/marginX（长按拖动）。
    if (subtitleText.trim().isEmpty) {
      // 编辑态（已出框）即使处于两条字幕的空隙也要显示占位框，
      // 否则框突然消失、用户失去拖动锚点。
      if (_editingPath == path) {
        // 空隙期占位框必须可消：垫一层舞台级「点外部收框」命中层，
        // 占位框本身也可点击收框——否则空隙期出现无法交互的小孤框，
        // 只能等下一句字幕出现才能点掉（用户反馈）。
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _collapseEditBoxNow(videoState),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Align(
                  alignment: Alignment(
                    0, // 水平固定居中：全局水平对齐只作用于内嵌轨
                    _resolveVerticalAlignment(
                        videoState.pathSubtitlePosition(path)),
                  ),
                  child: Transform.translate(
                    offset: Offset(videoState.pathSubtitleMarginX(path), 0),
                    // 与编辑态相同的双层结构：占位文本 + 边框层
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _collapseEditBoxNow(videoState),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const SizedBox(
                            width: 120,
                            height: 28,
                            child: Opacity(opacity: 0, child: Text(' ')),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0x99FFFFFF),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    }

    final isEditingThis = _editingPath == path;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final baseFontSize = (width * 0.03).clamp(18.0, 42.0).toDouble();
        final fontSize = (baseFontSize * videoState.srtSubtitleScale)
            .clamp(14.0, 72.0)
            .toDouble();

        final fillStyle = _buildFillStyle(videoState, fontSize);
        final borderStyle = _buildBorderStyle(videoState, fillStyle);
        final bgEnabled = _subtitleBgEnabled[path] ?? false;

        final Widget textBox = ConstrainedBox(
          constraints: BoxConstraints(minWidth: 120, maxWidth: width * 0.9),
          child: bgEnabled
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: _OutlinedSubtitleText(
                    text: subtitleText,
                    fillStyle: fillStyle,
                    borderStyle: borderStyle,
                    showBorder: true,
                    textAlign: TextAlign.center,
                  ),
                )
              : _OutlinedSubtitleText(
                  text: subtitleText,
                  fillStyle: fillStyle,
                  borderStyle: borderStyle,
                  showBorder: true,
                  textAlign: TextAlign.center,
                ),
        );

        Widget positionedContent;
        if (!isEditingThis) {
          // 未出框：长按出框并可顺势拖动调位置（这是字幕区专属手势，
          // 会盖过播放器的长按倍速——倍速请在字幕文本之外长按）；
          // 单击/拖动等其他手势全部透传给播放器。
          positionedContent = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (details) {
              debugPrint('[SubtitleOverlay] 长按出框 path=$path');
              setState(() {
                _editingPath = path;
                _editingCueText = subtitleText; // 记录出框时的文本，供换句自动收框
              });
              videoState.setSubtitleEditBoxVisible(true);
              _longPressMoved = false;
              _dragStartPosition = videoState.pathSubtitlePosition(path);
              _dragStartMarginX = videoState.pathSubtitleMarginX(path);
              // 保存不可变起点，供 MoveUpdate 的「起点+累计偏移」使用
              _dragOriginPosition = _dragStartPosition;
              _dragOriginMarginX = _dragStartMarginX;
              videoState.setSubtitleDragActive(true);
            },
            onLongPressMoveUpdate: (details) {
              if (details.offsetFromOrigin.distance > 8) {
                _longPressMoved = true;
              }
              if (!_longPressMoved) return;
              final v = videoState;
              // offsetFromOrigin 是相对按下原点的累计偏移：一律
              // 「不可变起点 + 累计」，绝不把结果写回起点再叠加
              // （旧实现每帧累加，越拖越飞）。
              v.setPathSubtitleMarginX(
                path,
                (_dragOriginMarginX + details.offsetFromOrigin.dx)
                    .clamp(-500.0, 500.0),
              );
              final stageH = MediaQuery.of(context).size.height;
              v.setPathSubtitlePosition(
                path,
                (_dragOriginPosition +
                        details.offsetFromOrigin.dy / stageH * 100)
                    .clamp(VideoPlayerState.minSubtitlePosition,
                        VideoPlayerState.maxSubtitlePosition),
              );
            },
            onLongPressEnd: (_) {
              videoState.setSubtitleDragActive(false);
              if (_longPressMoved) {
                // 拖动过 -> 松手即收框
                setState(() => _editingPath = null);
                videoState.setSubtitleEditBoxVisible(false);
              }
            },
            child: textBox,
          );
        } else {
          // 编辑态：完整拖动/面板交互（仅作用于当前这条字幕）。
          // 手势分工：pan 负责拖动（带 6px 阈值，防轻触漂移），longPress
          // 负责原地保持框/拖动锁定，Listener 识别双指长按，
          // 避免在同一 GestureDetector 中同时注册 pan 和 scale。
          final Widget dragArea = Listener(
            onPointerDown: (event) {
              _pointerStarts[event.pointer] = event.position;
              if (_pointerStarts.length == 2 && !_panActuallyMoved) {
                _twoFingerTimer?.cancel();
                _twoFingerTimer = Timer(const Duration(milliseconds: 450), () {
                  _twoFingerTimer = null;
                  if (mounted &&
                      _editingPath == path &&
                      _pointerStarts.length >= 2) {
                    _showSubtitleSettingsPanel(context, videoState, path);
                  }
                });
              }
            },
            onPointerMove: (event) {
              final start = _pointerStarts[event.pointer];
              if (start != null && (event.position - start).distance > 8) {
                _twoFingerTimer?.cancel();
                _twoFingerTimer = null;
              }
            },
            onPointerUp: (event) {
              _pointerStarts.remove(event.pointer);
              _twoFingerTimer?.cancel();
              _twoFingerTimer = null;
            },
            onPointerCancel: (event) {
              _pointerStarts.remove(event.pointer);
              _twoFingerTimer?.cancel();
              _twoFingerTimer = null;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (_) {
                // 点击框内非按钮处 -> 收框。onTapUp 是唯一收框入口，
                // onPanEnd 只在真正拖动过时收框，避免点击时双收框。
                setState(() => _editingPath = null);
                _panStart = null;
                _stopTwoFingerLongPress();
                videoState.setSubtitleEditBoxVisible(false);
                videoState.setSubtitleDragActive(false);
              },
              onPanDown: (details) {
                _panStart = details.globalPosition;
                _panActuallyMoved = false;
                _dragStartPosition = videoState.pathSubtitlePosition(path);
                _dragStartMarginX = videoState.pathSubtitleMarginX(path);
                // 不在此处 setSubtitleDragActive(true)：一触即发会残留
                // 拖动态拦截播放器手势（点击收框时手指微抖即触发）。
              },
              onPanUpdate: (details) {
                final start = _panStart;
                if (start == null) return;
                // 6px 最小位移阈值：轻触/微抖不移动字幕
                if (!_panActuallyMoved) {
                  if ((details.globalPosition - start).distance < 6) return;
                  _panActuallyMoved = true;
                  _twoFingerTimer?.cancel();
                  _twoFingerTimer = null;
                  videoState.setSubtitleDragActive(true);
                }
                final v = videoState;
                _dragStartMarginX += details.delta.dx;
                v.setPathSubtitleMarginX(
                  path,
                  _dragStartMarginX.clamp(-500.0, 500.0),
                );
                final stageH = MediaQuery.of(context).size.height;
                _dragStartPosition += details.delta.dy / stageH * 100;
                v.setPathSubtitlePosition(
                  path,
                  _dragStartPosition.clamp(VideoPlayerState.minSubtitlePosition,
                      VideoPlayerState.maxSubtitlePosition),
                );
              },
              onPanEnd: (_) {
                // 真正拖动过才复位拖动态；收框统一交给 onTapUp。
                _panStart = null;
                if (_panActuallyMoved) {
                  _panActuallyMoved = false;
                  _stopTwoFingerLongPress();
                  videoState.setSubtitleDragActive(false);
                  setState(() => _editingPath = null);
                  videoState.setSubtitleEditBoxVisible(false);
                }
              },
              onPanCancel: () {
                // 手势被系统打断（来电/通知等）：必须复位拖动态，
                // 否则残留 true 永久拦截播放器手势。
                _panStart = null;
                _panActuallyMoved = false;
                _stopTwoFingerLongPress();
                videoState.setSubtitleDragActive(false);
              },
              onLongPressStart: (details) {
                debugPrint('[SubtitleOverlay] 长按开始 path=$path');
                _longPressMoved = false;
                _dragStartPosition = videoState.pathSubtitlePosition(path);
                _dragStartMarginX = videoState.pathSubtitleMarginX(path);
                _dragOriginPosition = _dragStartPosition;
                _dragOriginMarginX = _dragStartMarginX;
                videoState.setSubtitleDragActive(true);
              },
              onLongPressMoveUpdate: (details) {
                if (details.offsetFromOrigin.distance > 8) {
                  _longPressMoved = true;
                }
                if (!_longPressMoved) return;
                final v = videoState;
                // 起点+累计偏移（offsetFromOrigin 为累计值，不可再叠加）
                v.setPathSubtitleMarginX(
                  path,
                  (_dragOriginMarginX + details.offsetFromOrigin.dx)
                      .clamp(-500.0, 500.0),
                );
                final stageH = MediaQuery.of(context).size.height;
                v.setPathSubtitlePosition(
                  path,
                  (_dragOriginPosition +
                          details.offsetFromOrigin.dy / stageH * 100)
                      .clamp(VideoPlayerState.minSubtitlePosition,
                          VideoPlayerState.maxSubtitlePosition),
                );
              },
              onLongPressEnd: (_) {
                videoState.setSubtitleDragActive(false);
                if (_longPressMoved) {
                  // 拖动过 -> 松手即锁定收框
                  setState(() => _editingPath = null);
                  _stopTwoFingerLongPress();
                  videoState.setSubtitleEditBoxVisible(false);
                }
                // 原地长按 -> 保持框（双指长按/设置钮弹面板）
              },
              child: textBox,
            ),
          );

          final Widget boxLayer = Stack(
            clipBehavior: Clip.none,
            children: [
              dragArea,
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0x99FFFFFF),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 2,
                top: 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    debugPrint('[SubtitleOverlay] 点击设置按钮');
                    _showSubtitleSettingsPanel(context, videoState, path);
                  },
                  child: const Icon(
                    Icons.tune,
                    size: 18,
                    color: Color(0xFFFFFFFF),
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    debugPrint('[SubtitleOverlay] 点击背景切换按钮');
                    setState(() {
                      // 背景按字幕路径独立开关，多条字幕互不影响
                      _subtitleBgEnabled[path] =
                          !(_subtitleBgEnabled[path] ?? false);
                    });
                  },
                  child: const Icon(
                    Icons.format_color_fill,
                    size: 18,
                    color: Color(0xFFFFFFFF),
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),
            ],
          );

          positionedContent = boxLayer;
        }

        // 底部黑边自动摆位（belowVideo）：混挂时新外挂自动放到视频矩形
        // 以下的黑边区域并水平居中（落点按实时舞台尺寸与视频宽高比计
        // 算，旋转/缩放跟随）；无黑边（视频占满舞台）时回退常规位置。
        // 手动拖动或全局滑块会清除 belowVideo，恢复手动语义。
        final belowVideo =
            !isEditingThis && videoState.pathSubtitleBelowVideo(path);
        var alignmentY =
            _resolveVerticalAlignment(videoState.pathSubtitlePosition(path));
        var translateX = videoState.pathSubtitleMarginX(path);
        if (belowVideo) {
          final stageHeight = constraints.maxHeight;
          final videoRect =
              _stageVideoRect(width, stageHeight, videoState.aspectRatio);
          final barTop = videoRect.bottom.clamp(0.0, stageHeight);
          if (barTop < stageHeight * 0.97) {
            // 黑边中心（舞台坐标）→ Align 映射基于内边距后区域，需换算。
            final barCenterY = barTop + (stageHeight - barTop) / 2;
            const padV = 16.0;
            final paddedH = (stageHeight - padV * 2).clamp(1.0, double.infinity);
            final centerFrac =
                ((barCenterY - padV) / paddedH).clamp(0.0, 1.0);
            alignmentY = centerFrac * 2 - 1;
            translateX = 0; // 黑边区域内水平居中
          }
        }

        final Widget content = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Align(
            alignment: Alignment(0, alignmentY),
            child: Transform.translate(
              offset: Offset(
                translateX,
                0, // 外挂垂直位移独立（pathSubtitlePosition 控制），不跟随全局垂直边距滑块
              ),
              child: positionedContent,
            ),
          ),
        );

        if (!isEditingThis) {
          return content;
        }
        // 编辑态垫一层舞台级「点外部收框」命中层：点击框外任意区域即收
        // 框（框自身的 detector 在上层优先命中，框内交互不受影响）。收框
        // 后该层随之消失，点击恢复正常透传给播放器。
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _collapseEditBoxNow(videoState),
              ),
            ),
            Positioned.fill(child: content),
          ],
        );
      },
    );
  }

  /// 舞台内按 contain 适配的视频显示矩形（黑边在矩形之外）。
  Rect _stageVideoRect(double stageW, double stageH, double aspect) {
    if (aspect <= 0) aspect = 16 / 9;
    double videoW;
    double videoH;
    if (stageW / stageH > aspect) {
      videoH = stageH;
      videoW = stageH * aspect;
    } else {
      videoW = stageW;
      videoH = stageW / aspect;
    }
    final left = (stageW - videoW) / 2;
    final top = (stageH - videoH) / 2;
    return Rect.fromLTWH(left, top, videoW, videoH);
  }

  /// 长按/双指/设置钮弹出的字幕设置面板（按字幕路径独立调时轴延迟）
  void _showSubtitleSettingsPanel(
      BuildContext context, VideoPlayerState videoState, String path) {
    // 字体列表只扫描一次（面板存续期间复用同一个 Future）
    Future<List<String>>? fontListFuture;
    // 历史缓存/远程下载的字体可能从未注册进引擎，打开面板时补注册
    unawaited(videoState.ensureSelectedSubtitleFontsRegistered());
    final previewValue =
        ValueNotifier<double>(videoState.pathSubtitleDelaySeconds(path));
    final delayController = TextEditingController(
      text: _formatDelayInputText(videoState.pathSubtitleDelaySeconds(path)),
    );
    final delayFocusNode = FocusNode();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xF0101010),
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (sheetContext) {
        // 首次点击输入框光标默认停在句首且不闪烁，第二次点击才出现在末
        // 端（用户反馈）：聚焦后显式把光标移到文本末尾并保持可见。
        delayFocusNode.addListener(() {
          if (!delayFocusNode.hasFocus) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!delayFocusNode.hasFocus) return;
            delayController.selection =
                TextSelection.collapsed(
                    offset: delayController.text.length);
          });
        });
        void applyValue(double value) {
          videoState.setPathSubtitleDelaySeconds(path, value);
          previewValue.value = value;
          delayController.text = _formatDelayInputText(value);
        }

        // 输入过程中的实时应用：绝不改写文本框——"-0" 会被
        // _formatDelayInputText 归一化成 "0"，把用户正在输入的负号敲掉，
        // 导致永远输不出 -0.1 这类负小数（用户反馈）。
        void applyTextValue(double value) {
          videoState.setPathSubtitleDelaySeconds(path, value);
          previewValue.value = value;
        }

        // 常用字幕颜色调色板
        const palette = <Color>[
          Colors.white,
          Colors.black,
          Colors.yellow,
          Colors.cyan,
          Color(0xFFFFD54F),
          Color(0xFFFF8A65),
          Color(0xFFAED581),
          Color(0xFF81D4FA),
          Color(0xFFF48FB1),
          Color(0xFFB39DDB),
        ];
        // 键盘避让交给 _SheetKeyboardAvoider：viewInsets 依赖隔离在该
        // 小部件里，键盘动画逐帧只重建它，不重建整块面板内容（点击输入
        // 框时键盘弹出过程的卡顿来源，用户反馈）。
        return _SheetKeyboardAvoider(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '外挂字幕设置（${videoState.externalSubtitleDisplayName(path)}）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text('外挂字幕时轴偏移（正值延后，负值提前）',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<double>(
                    valueListenable: previewValue,
                    builder: (context, value, _) {
                      return Slider(
                        value: value.clamp(
                          videoState.subtitleDelaySliderMinSeconds,
                          videoState.subtitleDelaySliderMaxSeconds,
                        ),
                        min: videoState.subtitleDelaySliderMinSeconds,
                        max: videoState.subtitleDelaySliderMaxSeconds,
                        divisions: videoState.subtitleDelaySliderDivisions,
                        label: _formatDelayDisplayText(value),
                        onChanged: applyValue,
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: delayController,
                          focusNode: delayFocusNode,
                          cursorColor: Colors.amber,
                          showCursor: true,
                          keyboardType: const TextInputType.numberWithOptions(
                              signed: true, decimal: true),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '例如 -12.5 或 8',
                            hintStyle: const TextStyle(color: Colors.white38),
                            labelText: '秒',
                            labelStyle: const TextStyle(color: Colors.white60),
                            enabledBorder: OutlineInputBorder(
                              borderSide:
                                  const BorderSide(color: Colors.white24),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.amber),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                          ),
                          onChanged: (text) {
                            final parsed = double.tryParse(text.trim());
                            if (parsed != null) applyTextValue(parsed);
                          },
                          onSubmitted: (text) {
                            final parsed = double.tryParse(text.trim());
                            if (parsed != null) applyValue(parsed);
                            FocusScope.of(sheetContext).unfocus();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: () => FocusScope.of(sheetContext).unfocus(),
                        icon: const Icon(Icons.check, color: Colors.amber),
                        tooltip: '完成',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('外挂字幕字号（不影响内嵌字幕）',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Consumer<VideoPlayerState>(
                    builder: (context, vs, _) {
                      final scale = vs.srtSubtitleScale;
                      return Slider(
                        value: scale.clamp(0.5, 3.0),
                        min: 0.5,
                        max: 3.0,
                        divisions: 50,
                        label: '${scale.toStringAsFixed(2)}x',
                        onChanged: (value) =>
                            videoState.setSrtSubtitleScale(value),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Text('字体（可多选）',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  StatefulBuilder(
                    builder: (sheetContext, setSheetState) {
                      fontListFuture ??= videoState.listSubtitleFonts();
                      void refreshFonts() {
                        if (!sheetContext.mounted) return;
                        setSheetState(() {
                          fontListFuture = videoState.listSubtitleFonts();
                        });
                      }

                      return Consumer<VideoPlayerState>(
                        builder: (context, vs, _) {
                          return FutureBuilder<List<String>>(
                            future: fontListFuture,
                            builder: (context, snapshot) {
                              final fonts =
                                  snapshot.data ?? const <String>[];
                              final current = vs.externalSubtitleFontName;
                              final selected = current
                                  .split(',')
                                  .map((e) => e.trim())
                                  .where((e) => e.isNotEmpty)
                                  .toSet();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final f in fonts)
                                        FilterChip(
                                          label: Text(f,
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                          selected: selected.contains(f),
                                          onSelected: (sel) {
                                            final next = sel
                                                ? [...selected, f].join(',')
                                                : selected
                                                    .where((e) => e != f)
                                                    .join(',');
                                            videoState
                                                .setExternalSubtitleFontName(
                                                    next);
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () async {
                                            await _showFontMultiSelectDialog(
                                              context,
                                              videoState,
                                              fonts,
                                              onFontsImported: refreshFonts,
                                            );
                                            refreshFonts();
                                          },
                                          icon: const Icon(
                                              Icons.font_download,
                                              size: 16,
                                              color: Colors.white70),
                                          label: const Text('选择字体',
                                              style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13)),
                                          style: _sheetButtonStyle(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              _importExternalSheetFonts(
                                                  videoState, refreshFonts),
                                          icon: const Icon(Icons.file_open,
                                              size: 16,
                                              color: Colors.white70),
                                          label: const Text('导入字体',
                                              style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13)),
                                          style: _sheetButtonStyle(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Text('文字颜色',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Consumer<VideoPlayerState>(
                    builder: (context, vs, _) {
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final color in palette)
                            GestureDetector(
                              onTap: () =>
                                  videoState.setExternalSubtitleColor(color),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color:
                                        vs.externalSubtitleColor.toARGB32() ==
                                                color.toARGB32()
                                            ? Colors.amber
                                            : Colors.white24,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  // 大目标按钮（原先是 16px 小图标，TV 遥控/手指都难命中）。
                  OutlinedButton.icon(
                    onPressed: () => _showHsvPicker(context, videoState),
                    icon: const Icon(Icons.palette,
                        size: 16, color: Colors.white70),
                    label: const Text('全色调色盘',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    style: _sheetButtonStyle(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      delayFocusNode.dispose();
      delayController.dispose();
      // 面板关闭（确认/取消/点外部）即收框：设置已实时应用，留着框只会
      // 在字幕空隙期变成无法交互的孤框。
      if (mounted && _editingPath == path) {
        _collapseEditBoxNow(videoState);
      }
    });
  }

  /// 面板内操作按钮样式（Nipa 深色面板 + amber 焦点/悬停高亮）。
  /// Material 按钮原生支持 D-pad 焦点遍历，TV 遥控可直接移动焦点触发。
  ButtonStyle _sheetButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: const Color(0x22FFFFFF),
      side: const BorderSide(color: Colors.white24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      overlayColor: Colors.amber.withValues(alpha: 0.18),
    );
  }

  /// 字体多选对话框（复选列表，勾选即时生效）：给 TV 遥控一个可焦点遍
  /// 历的大目标入口——FilterChip 小目标在遥控上难命中（用户反馈）。
  /// 导入逻辑与字幕设置菜单一致（移动端多选字体文件 / 桌面端选目录）。
  Future<void> _showFontMultiSelectDialog(
    BuildContext context,
    VideoPlayerState videoState,
    List<String> fonts, {
    required VoidCallback onFontsImported,
  }) async {
    final selected = videoState.externalSubtitleFontName
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    Future<List<String>>? activeFonts;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            activeFonts ??= Future<List<String>>.value(fonts);
            return AlertDialog(
              title: const Text('选择字体（可多选）'),
              content: SizedBox(
                width: 320,
                height: 380,
                child: FutureBuilder<List<String>>(
                  future: activeFonts,
                  builder: (context, snapshot) {
                    final dialogFonts = snapshot.data ?? const <String>[];
                    if (dialogFonts.isEmpty) {
                      return const Center(
                        child: Text('未找到可用字体，可先导入字体文件',
                            style: TextStyle(color: Colors.white54)),
                      );
                    }
                    return ListView(
                      children: [
                        for (var i = 0; i < dialogFonts.length; i++)
                          CheckboxListTile(
                            autofocus: i == 0 && globals.isTelevision,
                            dense: true,
                            value: selected.contains(dialogFonts[i]),
                            title: Text(dialogFonts[i],
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13)),
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selected.add(dialogFonts[i]);
                                } else {
                                  selected.remove(dialogFonts[i]);
                                }
                              });
                              videoState.setExternalSubtitleFontName(
                                  selected.join(','));
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: () => _importExternalSheetFonts(videoState, () {
                    setDialogState(() {
                      activeFonts = videoState.listSubtitleFonts();
                    });
                    onFontsImported();
                  }),
                  icon: const Icon(Icons.file_open,
                      size: 16, color: Colors.white70),
                  label: const Text('导入字体',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  style: _sheetButtonStyle(),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 与字幕设置菜单同一套导入逻辑：iOS/Android 多选字体文件（file_selector
  /// 的目录选择在移动端不支持），桌面端选文件夹整目录导入。导入不自动套
  /// 用字体名，由用户在字体列表里自由勾选。
  static final XTypeGroup _fontXTypeGroup = const XTypeGroup(
    label: 'Font',
    extensions: ['ttf', 'otf', 'ttc'],
    uniformTypeIdentifiers: [
      'public.truetype-font',
      'public.opentype-font',
      'public.font',
      'public.data',
      'public.item',
    ],
  );

  Future<void> _importExternalSheetFonts(
    VideoPlayerState videoState,
    VoidCallback onImported,
  ) async {
    try {
      var count = 0;
      if (!kIsWeb && (io.Platform.isIOS || io.Platform.isAndroid)) {
        final files = await openFiles(acceptedTypeGroups: [_fontXTypeGroup]);
        for (final f in files) {
          await videoState.importSubtitleFontFile(f.path, applyName: false);
          count++;
        }
      } else if (!kIsWeb) {
        final directory = await getDirectoryPath();
        if (directory != null) {
          count = await videoState.importSubtitleFontDirectory(directory);
        }
      }
      debugPrint('[SubtitleOverlay] 导入字体文件 $count 个');
      onImported();
    } catch (e) {
      debugPrint('[SubtitleOverlay] 导入字体失败: $e');
    }
  }

  /// 字幕轴同步诊断：同一条字幕只记一次，且全局每秒最多一条，
  /// 输出 [SubtitleSync] 供日志终端比对内核间的时间轴来源差异。
  void _logSubtitleSyncOnce({
    required VideoPlayerState videoState,
    required String cueKey,
    required int subtitleTimeMs,
    required String path,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (cueKey == _lastLoggedCueKey ||
        nowMs - _lastSyncLogAtMs < _syncLogMinIntervalMs) {
      return;
    }
    _lastLoggedCueKey = cueKey;
    _lastSyncLogAtMs = nowMs;
    debugPrint(
      '[SubtitleSync] kernel=${videoState.player.getPlayerKernelName()} '
      'smooth=${videoState.playbackTimeMs.value.round()}ms '
      'raw=${videoState.player.position}ms '
      'lookup=${subtitleTimeMs}ms '
      'delay=${(videoState.overlaySubtitleDelayMs(path) / 1000).toStringAsFixed(1)}s '
      'file=${path.split('/').last} '
      'cue=${cueKey.length > 24 ? '${cueKey.substring(0, 24)}...' : cueKey}',
    );
  }

  String _formatDelayInputText(double value) {
    if (value.abs() < 0.0001) return '0';
    var text = value.toStringAsFixed(3);
    if (text.contains('.')) {
      text = text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  String _formatDelayDisplayText(double value) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(1)}s';
  }

  // 右下角拉伸手柄：Listener 原生事件，不与长按抢；放在拖动 GestureDetector 外，确保可命中

  double _resolveVerticalAlignment(double subtitlePosition) {
    final normalized = subtitlePosition.clamp(
      VideoPlayerState.minSubtitlePosition,
      VideoPlayerState.maxSubtitlePosition,
    );
    // 0=屏幕顶 100=屏幕底，允许拖到视频外（黑边区）：overlay 是 Positioned.fill
    // 占满整个播放舞台（含视频外区域），视频面 Center(AspectRatio) 居中留黑边。
    return (normalized / 100) * 2.0 - 1.0;
  }

  /// 叠层字幕的填充样式：SRT/VTT 为纯文本渲染，用户选择的字体直接生效
  /// （不需要"样式覆盖=强制"门控；ASS 特效走内核 libass，不经过此叠层）。
  /// 全局设置（粗体/斜体/阴影/描边/对齐/透明度）仅作用于内嵌轨，
  /// 叠层用固定基线，避免全局调整连带改动外挂。
  TextStyle _buildFillStyle(VideoPlayerState videoState, double fontSize) {
    final fontNames = videoState.externalSubtitleFontName
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final fontsApply = fontNames.isNotEmpty;

    return TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      color: videoState.externalSubtitleColor,
      height: 1.28,
      fontFamily: fontsApply && fontNames.isNotEmpty ? fontNames.first : null,
      fontFamilyFallback:
          fontsApply && fontNames.length > 1 ? fontNames.sublist(1) : null,
      shadows: null,
    );
  }

  /// 叠层字幕的描边样式（填充样式的前景描边变体），
  /// 描边宽度固定基线，不跟随全局描边滑块。
  TextStyle _buildBorderStyle(
      VideoPlayerState videoState, TextStyle fillStyle) {
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = VideoPlayerState.defaultSubtitleBorderSize
          .clamp(0.0, 8.0)
          .toDouble()
      // 外挂叠层描边固定黑色（独立于播放器设置/内嵌描边）
      ..color = const Color(0xFF000000);

    return fillStyle.copyWith(
      foreground: borderPaint,
      color: null,
      shadows: null,
    );
  }

  /// 全色调色盘（HSV 三滑块：色相/饱和度/亮度 + 实时预览），
  /// 外挂叠层专属——选色应用 externalSubtitleColor
  Future<void> _showHsvPicker(
    BuildContext context,
    VideoPlayerState videoState,
  ) async {
    var hsv = HSVColor.fromColor(videoState.externalSubtitleColor);
    final picked = await showDialog<Color>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('选择颜色'),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 40,
                      decoration: BoxDecoration(
                        color: hsv.toColor(),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildHsvSliderRow(
                      '色相',
                      hsv.hue,
                      0,
                      360,
                      (v) => setDialogState(() => hsv = hsv.withHue(v)),
                    ),
                    _buildHsvSliderRow(
                      '饱和',
                      hsv.saturation,
                      0,
                      1,
                      (v) => setDialogState(() => hsv = hsv.withSaturation(v)),
                    ),
                    _buildHsvSliderRow(
                      '亮度',
                      hsv.value,
                      0,
                      1,
                      (v) => setDialogState(() => hsv = hsv.withValue(v)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, hsv.toColor()),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
    if (picked != null) {
      videoState.setExternalSubtitleColor(picked);
    }
  }

  Widget _buildHsvSliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _OutlinedSubtitleText extends StatelessWidget {
  final String text;
  final TextStyle fillStyle;
  final TextStyle borderStyle;
  final bool showBorder;
  final TextAlign textAlign;

  const _OutlinedSubtitleText({
    required this.text,
    required this.fillStyle,
    required this.borderStyle,
    required this.showBorder,
    required this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final fillText = Text(
      text,
      textAlign: textAlign,
      softWrap: true,
      style: fillStyle,
    );

    if (!showBorder) {
      return fillText;
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: textAlign,
          softWrap: true,
          style: borderStyle,
        ),
        fillText,
      ],
    );
  }
}

/// 键盘避让容器：把 viewInsets 依赖隔离在这个小部件里，键盘弹出/收起
/// 动画的逐帧 inset 变化只重建这里，不重建整块面板内容（此前整面板挂
/// 在 MediaQuery 上，输入框聚焦时键盘动画每次 tick 全量重建造成卡顿）。
class _SheetKeyboardAvoider extends StatelessWidget {
  final Widget child;

  const _SheetKeyboardAvoider({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}
