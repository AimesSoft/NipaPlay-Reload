import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class ExternalSubtitleOverlay extends StatefulWidget {
  final double currentPositionMs;

  const ExternalSubtitleOverlay({
    super.key,
    required this.currentPositionMs,
  });

  @override
  State<ExternalSubtitleOverlay> createState() => _ExternalSubtitleOverlayState();
}

class _ExternalSubtitleOverlayState extends State<ExternalSubtitleOverlay> {
  // 多字幕分块渲染：每条外挂字幕独立一块（独立延迟/位置/手势）。
  // _editingPath = 当前出框编辑的字幕路径；null = 全部隐藏（不拦截
  // 播放器手势：长按倍速/拖动 seek 直达播放器）。
  String? _editingPath;
  // 记录编辑框所属的视频路径：换视频/重新加载时自动收框，避免新视频一
  // 加载好框就自动出现（同名外挂字幕路径仍命中 _editingPath），框层随
  // 播放进度每帧重建、与同 Stack 弹幕层反复合成导致闪烁。长按出框不受影响。
  String? _boundMediaPath;
  // 出框时的字幕文本：编辑期间字幕切到下一句自动消框（避免框随新文本
  // 缩到很小、点不中收框按钮、拖动锚点丢失）。
  String? _editingCueText;
  bool _longPressMoved = false;  // 长按期间是否发生拖动
  bool _panDragActive = false;  // Pan fallback: 长按未识别前移动也能拖
  double _dragStartPosition = 100.0;  // 长按起点字幕垂直位置
  double _dragStartMarginX = 0.0;    // 长按起点水平边距
  /// 字幕背景（功能区按钮切换；默认无背景）
  bool _subtitleBgEnabled = false;
  Timer? _twoFingerTimer;  // 双指长按识别定时器
  // 字幕轴同步诊断去重
  String _lastLoggedCueKey = '';
  int _lastSyncLogAtMs = 0;
  static const int _syncLogMinIntervalMs = 1000;

  /// 收起编辑框（在 build 中检测到状态变化后调用；postFrame 延迟 setState，
  /// 避免构建期改状态）。
  void _collapseEditBox() {
    if (_editingPath == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingPath == null) return;
      setState(() {
        _editingPath = null;
        _editingCueText = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        if (!videoState.shouldRenderCurrentExternalSubtitleInApp()) {
          return const SizedBox.shrink();
        }
        final paths = videoState.activeExternalSubtitlePaths;
        if (paths.isEmpty) {
          return const SizedBox.shrink();
        }
        // 字幕集合变化（换文件/重新加载）时收起残留编辑框
        if (_editingPath != null && !paths.contains(_editingPath)) {
          _collapseEditBox();
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
    final subtitleTimeMs = widget.currentPositionMs.round() -
        (videoState.pathSubtitleDelaySeconds(path) * 1000).round();
    final subtitleText = videoState.pathSubtitleTextAt(path, subtitleTimeMs);

    // 换视频（切集/重新加载）时收起残留编辑框——避免框在新视频加载完成后
    // 立即自动出现（同名外挂字幕路径仍命中 _editingPath）导致弹幕闪烁。
    final mediaPath = videoState.currentVideoPath;
    if (mediaPath != _boundMediaPath) {
      _boundMediaPath = mediaPath;
      _collapseEditBox();
    }
    // 编辑期间字幕切到下一句自动消框——避免框随新文本缩到很小、点不中
    // 收框按钮、拖动锚点丢失。间隙期（文本为空）不收框，保留拖动锚点。
    if (_editingPath == path &&
        _editingCueText != null &&
        subtitleText.trim().isNotEmpty &&
        subtitleText != _editingCueText) {
      _collapseEditBox();
    }

    // 字幕轴同步诊断：每条字幕首次显示时记录一次，用于比对内核间的时间轴
    _logSubtitleSyncOnce(
      videoState: videoState,
      cueKey: '$path|${subtitleText.hashCode}',
      subtitleTimeMs: subtitleTimeMs,
      path: path,
    );

    if (subtitleText.trim().isEmpty || videoState.subtitleOpacity <= 0) {
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

          final fillStyle = TextStyle(
            fontSize: fontSize,
            fontWeight:
                videoState.subtitleBold ? FontWeight.bold : FontWeight.w500,
            fontStyle: videoState.subtitleItalic
                ? FontStyle.italic
                : FontStyle.normal,
            color: videoState.subtitleColor,
            height: 1.28,
            // 字体仅在 样式覆盖=自定义样式 时应用（用户指定：保持原样/
            // 仅缩放/自动模式下外挂字幕不套用所选字体，使用默认字体）。
            fontFamily: videoState.subtitleOverrideMode ==
                    SubtitleStyleOverrideMode.force
                ? (videoState.subtitleFontName.isNotEmpty
                    ? videoState.subtitleFontName.split(',').first.trim()
                    : null)
                : null,
            fontFamilyFallback: videoState.subtitleOverrideMode ==
                    SubtitleStyleOverrideMode.force
                ? (videoState.subtitleFontName.contains(',')
                    ? videoState.subtitleFontName
                        .split(',')
                        .skip(1)
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList()
                    : null)
                : null,
            shadows: videoState.subtitleShadowOffset > 0
                ? [
                    Shadow(
                      color: videoState.subtitleShadowColor,
                      offset: Offset(0, videoState.subtitleShadowOffset),
                      blurRadius: videoState.subtitleShadowOffset * 2,
                    ),
                  ]
                : null,
          );

          final borderPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth =
                videoState.subtitleBorderSize.clamp(0.0, 8.0).toDouble()
            ..color = videoState.subtitleBorderColor;

          final borderStyle = fillStyle.copyWith(
            foreground: borderPaint,
            color: null,
            shadows: null,
          );

          final Widget textBox = ConstrainedBox(
            constraints: BoxConstraints(minWidth: 120, maxWidth: width * 0.9),
            child: _subtitleBgEnabled
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x99000000),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: _OutlinedSubtitleText(
                      text: subtitleText,
                      fillStyle: fillStyle,
                      borderStyle: borderStyle,
                      showBorder: videoState.subtitleBorderSize > 0,
                      textAlign: _resolveTextAlign(videoState.subtitleAlignX),
                    ),
                  )
                : _OutlinedSubtitleText(
                    text: subtitleText,
                    fillStyle: fillStyle,
                    borderStyle: borderStyle,
                    showBorder: videoState.subtitleBorderSize > 0,
                    textAlign: _resolveTextAlign(videoState.subtitleAlignX),
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
                  _editingCueText = subtitleText; // 供换句自动消框
                });
                videoState.setSubtitleEditBoxVisible(true);
                _longPressMoved = false;
                _dragStartPosition = videoState.pathSubtitlePosition(path);
                _dragStartMarginX = videoState.pathSubtitleMarginX(path);
                videoState.setSubtitleDragActive(true);
              },
              onLongPressMoveUpdate: (details) {
                if (details.offsetFromOrigin.distance > 8) {
                  _longPressMoved = true;
                }
                if (!_longPressMoved) return;
                final v = videoState;
                _dragStartMarginX = (_dragStartMarginX +
                        details.offsetFromOrigin.dx)
                    .clamp(-500.0, 500.0);
                v.setPathSubtitleMarginX(path, _dragStartMarginX);
                final stageH = MediaQuery.of(context).size.height;
                _dragStartPosition = (_dragStartPosition +
                        details.offsetFromOrigin.dy / stageH * 100)
                    .clamp(VideoPlayerState.minSubtitlePosition,
                        VideoPlayerState.maxSubtitlePosition);
                v.setPathSubtitlePosition(path, _dragStartPosition);
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
            // 编辑态：完整拖动/面板交互（仅作用于当前这条字幕）
            final Widget dragArea = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (_) {
                // 点击框内非按钮处 -> 收框
                // onPanDown 无条件已置 dragActive=true，此处必须复位，
                // 否则残留 true 会拦截播放器长按倍速（video_player_ui 653 行）。
                setState(() => _editingPath = null);
                videoState.setSubtitleEditBoxVisible(false);
                videoState.setSubtitleDragActive(false);
              },
              onPanDown: (_) {
                _panDragActive = true;
                _dragStartPosition = videoState.pathSubtitlePosition(path);
                _dragStartMarginX = videoState.pathSubtitleMarginX(path);
                videoState.setSubtitleDragActive(true);
              },
              onPanUpdate: (details) {
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
                _panDragActive = false;
                videoState.setSubtitleDragActive(false);
                setState(() => _editingPath = null);
                videoState.setSubtitleEditBoxVisible(false);
              },
              onLongPressStart: (details) {
                debugPrint('[SubtitleOverlay] 长按开始 path=$path');
                _longPressMoved = false;
                _dragStartPosition = videoState.pathSubtitlePosition(path);
                _dragStartMarginX = videoState.pathSubtitleMarginX(path);
                videoState.setSubtitleDragActive(true);
              },
              onLongPressMoveUpdate: (details) {
                if (details.offsetFromOrigin.distance > 8) {
                  _longPressMoved = true;
                }
                if (!_longPressMoved) return;
                final v = videoState;
                // 用起点+累计偏移，避免 position+offset 反复叠加导致拖不到底
                v.setPathSubtitleMarginX(
                  path,
                  (_dragStartMarginX + details.offsetFromOrigin.dx)
                      .clamp(-500.0, 500.0),
                );
                final stageH = MediaQuery.of(context).size.height;
                v.setPathSubtitlePosition(
                  path,
                  (_dragStartPosition +
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
                  videoState.setSubtitleEditBoxVisible(false);
                }
                // 原地长按 -> 保持框（双指长按/设置钮弹面板）
              },
              onScaleStart: (details) {
                if (details.pointerCount >= 2) {
                  _twoFingerTimer?.cancel();
                  _twoFingerTimer = Timer(const Duration(milliseconds: 450),
                      () {
                    debugPrint('[SubtitleOverlay] 双指长按触发设置面板');
                    _showSubtitleSettingsPanel(context, videoState, path);
                  });
                }
              },
              onScaleUpdate: (_) {
                _twoFingerTimer?.cancel();
                _twoFingerTimer = null;
              },
              onScaleEnd: (_) {
                _twoFingerTimer?.cancel();
                _twoFingerTimer = null;
              },
              child: textBox,
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
                        _subtitleBgEnabled = !_subtitleBgEnabled;
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

          return Opacity(
            opacity: videoState.subtitleOpacity.clamp(0.0, 1.0).toDouble(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Align(
                alignment: Alignment(
                  _resolveHorizontalAlignment(videoState.subtitleAlignX),
                  _resolveVerticalAlignment(
                      videoState.pathSubtitlePosition(path)),
                ),
                child: Transform.translate(
                  offset: Offset(
                    videoState.pathSubtitleMarginX(path),
                    videoState.subtitleMarginY,
                  ),
                  child: positionedContent,
                ),
              ),
            ),
          );
        },
      );
  }

  /// 长按/双指/设置钮弹出的字幕设置面板（按字幕路径独立调时轴延迟）
  void _showSubtitleSettingsPanel(
      BuildContext context, VideoPlayerState videoState, String path) {
    // 字体列表只扫描一次（面板存续期间复用同一个 Future）
    final fontListFuture = _listSubtitleFontNames(videoState);
    // 历史缓存/远程下载的字体可能从未注册进引擎，打开面板时补注册
    unawaited(videoState.ensureSelectedSubtitleFontsRegistered());
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xF0101010),
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (sheetContext) {
        final previewValue =
            ValueNotifier<double>(videoState.pathSubtitleDelaySeconds(path));
        final delayController = TextEditingController(
          text:
              _formatDelayInputText(videoState.pathSubtitleDelaySeconds(path)),
        );
        void applyValue(double value) {
          videoState.setPathSubtitleDelaySeconds(path, value);
          previewValue.value = value;
          delayController.text = _formatDelayInputText(value);
        }
        // 常用字幕颜色调色板
        const palette = <Color>[
          Colors.white, Colors.black, Colors.yellow, Colors.cyan,
          Color(0xFFFFD54F), Color(0xFFFF8A65), Color(0xFFAED581),
          Color(0xFF81D4FA), Color(0xFFF48FB1), Color(0xFFB39DDB),
        ];
        // 键盘弹出时把整块内容抬到键盘上方：底部内边距 = 键盘高度
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
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
                          keyboardType: const TextInputType.numberWithOptions(
                              signed: true, decimal: true),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '例如 -12.5 或 8',
                            hintStyle:
                                const TextStyle(color: Colors.white38),
                            labelText: '秒',
                            labelStyle:
                                const TextStyle(color: Colors.white60),
                            enabledBorder: OutlineInputBorder(
                              borderSide:
                                  const BorderSide(color: Colors.white24),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide:
                                  const BorderSide(color: Colors.amber),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                          ),
                          onChanged: (text) {
                            final parsed = double.tryParse(text.trim());
                            if (parsed != null) applyValue(parsed);
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
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13)),
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
                  Consumer<VideoPlayerState>(
                    builder: (context, vs, _) {
                      return FutureBuilder<List<String>>(
                        future: fontListFuture,
                        builder: (context, snapshot) {
                          final fonts = snapshot.data ?? <String>[];
                          final current = vs.subtitleFontName;
                          final selected = current
                              .split(',')
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toSet();
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final f in fonts)
                                FilterChip(
                                  label: Text(f,
                                      style:
                                          const TextStyle(fontSize: 12)),
                                  selected: selected.contains(f),
                                  onSelected: (sel) {
                                    final next = sel
                                        ? [...selected, f].join(',')
                                        : selected
                                            .where((e) => e != f)
                                            .join(',');
                                    videoState.setSubtitleFontName(next);
                                  },
                                ),
                            ],
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
                                  videoState.setSubtitleColor(color),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: vs.subtitleColor.toARGB32() ==
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
                ],
              ),
            ),
          ),
        );
      },
    );
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
      'smooth=${widget.currentPositionMs.round()}ms '
      'raw=${videoState.player.position}ms '
      'lookup=${subtitleTimeMs}ms '
      'delay=${videoState.pathSubtitleDelaySeconds(path).toStringAsFixed(1)}s '
      'file=${path.split('/').last} '
      'cue=${cueKey.length > 24 ? '${cueKey.substring(0, 24)}...' : cueKey}',
    );
  }

  // 与字幕设置菜单共用同一字体列表（含字体库 subtitle_fonts + 本地 fonts）
  Future<List<String>> _listSubtitleFontNames(VideoPlayerState videoState) {
    return videoState.listSubtitleFonts();
  }


  String _formatDelayInputText(double value) {
    if (value.abs() < 0.0001) return '0';
    var text = value.toStringAsFixed(3);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  String _formatDelayDisplayText(double value) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(1)}s';
  }

  // 右下角拉伸手柄：Listener 原生事件，不与长按抢；放在拖动 GestureDetector 外，确保可命中

  // 右下角拉伸手柄：Listener 原生事件，不与长按抢；放在拖动 GestureDetector 外，确保可命中

  double _resolveHorizontalAlignment(SubtitleAlignX alignX) {
    switch (alignX) {
      case SubtitleAlignX.left:
        return -1;
      case SubtitleAlignX.center:
        return 0;
      case SubtitleAlignX.right:
        return 1;
    }
  }

  TextAlign _resolveTextAlign(SubtitleAlignX alignX) {
    switch (alignX) {
      case SubtitleAlignX.left:
        return TextAlign.left;
      case SubtitleAlignX.center:
        return TextAlign.center;
      case SubtitleAlignX.right:
        return TextAlign.right;
    }
  }

  double _resolveVerticalAlignment(double subtitlePosition) {
    final normalized = subtitlePosition.clamp(
      VideoPlayerState.minSubtitlePosition,
      VideoPlayerState.maxSubtitlePosition,
    );
    // 0=屏幕顶 100=屏幕底，允许拖到视频外（黑边区）：overlay 是 Positioned.fill
    // 占满整个播放舞台（含视频外区域），视频面 Center(AspectRatio) 居中留黑边。
    return (normalized / 100) * 2.0 - 1.0;
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
