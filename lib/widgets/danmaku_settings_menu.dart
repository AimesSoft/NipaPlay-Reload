import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'settings_hint_text.dart';
import 'dart:ui';
import 'settings_slider.dart';
import 'blur_button.dart';
import '../services/manual_danmaku_matcher.dart';
import '../utils/danmaku_history_sync.dart';

class DanmakuSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;
  final VideoPlayerState videoState;

  const DanmakuSettingsMenu({
    super.key,
    required this.onClose,
    required this.videoState,
  });

  @override
  State<DanmakuSettingsMenu> createState() => _DanmakuSettingsMenuState();
}

class _DanmakuSettingsMenuState extends State<DanmakuSettingsMenu> {
  // 屏蔽词输入控制器
  final TextEditingController _blockWordController = TextEditingController();
  // 屏蔽词是否有错误
  bool _hasBlockWordError = false;
  // 错误消息
  String _blockWordErrorMessage = '';

  @override
  void dispose() {
    _blockWordController.dispose();
    super.dispose();
  }

  // 添加屏蔽词
  void _addBlockWord() {
    final word = _blockWordController.text.trim();
    
    // 验证输入
    if (word.isEmpty) {
      setState(() {
        _hasBlockWordError = true;
        _blockWordErrorMessage = '屏蔽词不能为空';
      });
      return;
    }
    
    if (widget.videoState.danmakuBlockWords.contains(word)) {
      setState(() {
        _hasBlockWordError = true;
        _blockWordErrorMessage = '该屏蔽词已存在';
      });
      return;
    }
    
    // 添加屏蔽词
    widget.videoState.addDanmakuBlockWord(word);
    
    // 清空输入框和错误状态
    _blockWordController.clear();
    setState(() {
      _hasBlockWordError = false;
      _blockWordErrorMessage = '';
    });
  }

  // 构建屏蔽词展示UI
  Widget _buildBlockWordsList() {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        if (videoState.danmakuBlockWords.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            child: Text(
              '暂无屏蔽词',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
            ),
          );
        }
        
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: videoState.danmakuBlockWords.map((word) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          word,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => videoState.removeDanmakuBlockWord(word),
                          child: const Icon(Icons.close, size: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return BaseSettingsMenu(
          title: '弹幕设置',
          onClose: widget.onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 弹幕开关
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '显示弹幕',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Switch(
                          value: videoState.danmakuVisible,
                          onChanged: (value) {
                            videoState.setDanmakuVisible(value);
                          },
                        ),
                      ],
                    ),
                    const SettingsHintText('开启后在视频上显示弹幕内容'),
                  ],
                ),
              ),
              // 手动匹配弹幕
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlurButton(
                      text: '手动匹配弹幕',
                      icon: Icons.search,
                      onTap: () async {
                        final result = await ManualDanmakuMatcher.instance.showManualMatchDialog(context);
                          
                        if (result != null) {
                          
                          // 如果用户选择了弹幕，重新加载弹幕
                          final episodeId = result['episodeId']?.toString() ?? '';
                          final animeId = result['animeId']?.toString() ?? '';
                          
                          if (episodeId.isNotEmpty && animeId.isNotEmpty) {
                            
                            // 调用新的弹幕历史同步方法来更新历史记录
                            try {
                              final currentVideoPath = widget.videoState.currentVideoPath;
                              if (currentVideoPath != null) {
                                await DanmakuHistorySync.updateHistoryWithDanmakuInfo(
                                  videoPath: currentVideoPath,
                                  episodeId: episodeId,
                                  animeId: animeId,
                                  animeTitle: result['animeTitle']?.toString(),
                                  episodeTitle: result['episodeTitle']?.toString(),
                                );
                                
                                // 立即更新视频播放器状态中的动漫和剧集标题
                                widget.videoState.setAnimeTitle(result['animeTitle']?.toString());
                                widget.videoState.setEpisodeTitle(result['episodeTitle']?.toString());
                              }
                            } catch (e) {
                              // 即使历史记录同步失败，也要继续加载弹幕
                            }
                            
                            // 直接调用 loadDanmaku，不检查 mounted 状态
                            // 因为 videoState 是独立的状态管理对象，不依赖于当前组件的生命周期
                            widget.videoState.loadDanmaku(episodeId, animeId);
                          }
                        }
                      },
                      expandHorizontally: true,
                    ),
                    const SettingsHintText('手动搜索并选择匹配的弹幕文件'),
                  ],
                ),
              ),
              // 弹幕透明度
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsSlider(
                      value: videoState.danmakuOpacity,
                      onChanged: (v) => videoState.setDanmakuOpacity(v),
                      label: '弹幕透明度',
                      displayTextBuilder: (v) => '${(v * 100).toInt()}%',
                      min: 0.0,
                      max: 1.0,
                    ),
                    const SizedBox(height: 4),
                    const SettingsHintText('拖动滑块调整弹幕透明度'),
                  ],
                ),
              ),
              // 弹幕屏蔽词
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
                child: Consumer<VideoPlayerState>(
                  builder: (context, videoState, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '弹幕屏蔽词',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            // 毛玻璃效果的白色添加按钮
                            BlurButton(
                              icon: Icons.add,
                              text: '添加',
                              onTap: () => _addBlockWord(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // 添加输入框
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                            child: Container(
                              height: 40, // 设置固定高度
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _hasBlockWordError 
                                    ? Colors.redAccent.withOpacity(0.8) 
                                    : Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Center( // 使用Center包装确保垂直居中
                                child: TextField(
                                  controller: _blockWordController,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: InputDecoration(
                                    hintText: '输入要屏蔽的关键词',
                                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0), // 垂直padding设为0
                                    isDense: true,
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.clear, color: Colors.white70, size: 18),
                                      onPressed: () => _blockWordController.clear(),
                                      tooltip: '',
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ),
                                  onSubmitted: (_) => _addBlockWord(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 错误信息
                        if (_hasBlockWordError)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 12),
                            child: Text(
                              _blockWordErrorMessage,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          ),
                        const SizedBox(height: 8),
                        _buildBlockWordsList(),
                        const SettingsHintText('包含屏蔽词的弹幕将被过滤不显示'),
                      ],
                    );
                  }
                ),
              ),
              // 弹幕堆叠开关
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '弹幕堆叠',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Switch(
                          value: videoState.danmakuStacking,
                          onChanged: (value) {
                            videoState.setDanmakuStacking(value);
                          },
                        ),
                      ],
                    ),
                    const SettingsHintText('允许多条弹幕重叠显示，适合弹幕密集场景'),
                  ],
                ),
              ),
              // 合并相同弹幕开关
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '合并相同弹幕',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Switch(
                          value: videoState.mergeDanmaku,
                          onChanged: (value) {
                            videoState.setMergeDanmaku(value);
                          },
                        ),
                      ],
                    ),
                    const SettingsHintText('将内容相同的弹幕合并为一条显示，减少屏幕干扰'),
                  ],
                ),
              ),

              // 弹幕类型屏蔽（移除标题，只保留开关）
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Consumer<VideoPlayerState>(
                  builder: (context, videoState, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部弹幕屏蔽
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '屏蔽顶部弹幕',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            Switch(
                              value: videoState.blockTopDanmaku,
                              onChanged: (value) {
                                videoState.setBlockTopDanmaku(value);
                              },
                            ),
                          ],
                        ),
                        // 底部弹幕屏蔽
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '屏蔽底部弹幕',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            Switch(
                              value: videoState.blockBottomDanmaku,
                              onChanged: (value) {
                                videoState.setBlockBottomDanmaku(value);
                              },
                            ),
                          ],
                        ),
                        // 滚动弹幕屏蔽
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '屏蔽滚动弹幕',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            Switch(
                              value: videoState.blockScrollDanmaku,
                              onChanged: (value) {
                                videoState.setBlockScrollDanmaku(value);
                              },
                            ),
                          ],
                        ),
                        const SettingsHintText('选择屏蔽特定类型的弹幕，对应类型的弹幕将不会显示'),
                      ],
                    );
                  }
                ),
              ),
              // 时间轴告知开关（移到最底部）
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '时间轴告知',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Switch(
                          value: videoState.isTimelineDanmakuEnabled,
                          onChanged: (value) {
                            videoState.toggleTimelineDanmaku(value);
                          },
                        ),
                      ],
                    ),
                    const SettingsHintText('在视频特定进度(25%/50%/75%/90%)显示弹幕提示'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// 新增弹幕透明度滑块组件
class _DanmakuOpacitySlider extends StatefulWidget {
  final VideoPlayerState videoState;
  const _DanmakuOpacitySlider({required this.videoState});

  @override
  State<_DanmakuOpacitySlider> createState() => _DanmakuOpacitySliderState();
}

class _DanmakuOpacitySliderState extends State<_DanmakuOpacitySlider> {
  final GlobalKey _sliderKey = GlobalKey();
  bool _isHovering = false;
  bool _isThumbHovered = false;
  bool _isDragging = false;
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(BuildContext context, double progress) {
    _removeOverlay();
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox == null) return;
    final position = sliderBox.localToGlobal(Offset.zero);
    final size = sliderBox.size;
    final bubbleX = position.dx + (progress * size.width) - 20;
    final bubbleY = position.dy - 40;
    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: bubbleX,
              top: bubbleY,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '${(widget.videoState.danmakuOpacity * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateOpacityFromPosition(Offset localPosition) {
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox != null) {
      final width = sliderBox.size.width;
      final progress = (localPosition.dx / width).clamp(0.0, 1.0);
      widget.videoState.setDanmakuOpacity(progress);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '弹幕透明度',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        MouseRegion(
          onEnter: (_) {
            setState(() {
              _isHovering = true;
            });
          },
          onExit: (_) {
            setState(() {
              _isHovering = false;
              _isThumbHovered = false;
            });
          },
          onHover: (event) {
            if (!_isHovering || _isDragging) return;
            final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
            if (sliderBox != null) {
              final localPosition = sliderBox.globalToLocal(event.position);
              final width = sliderBox.size.width;
              final progress = (localPosition.dx / width).clamp(0.0, 1.0);
              final thumbRect = Rect.fromLTWH(
                (widget.videoState.danmakuOpacity * width) - 8,
                16,
                16,
                16
              );
              setState(() {
                _isThumbHovered = thumbRect.contains(localPosition);
              });
            }
          },
          child: GestureDetector(
            onHorizontalDragStart: (details) {
              setState(() => _isDragging = true);
              _updateOpacityFromPosition(details.localPosition);
              _showOverlay(context, widget.videoState.danmakuOpacity);
            },
            onHorizontalDragUpdate: (details) {
              _updateOpacityFromPosition(details.localPosition);
              if (_overlayEntry != null) {
                _showOverlay(context, widget.videoState.danmakuOpacity);
              }
            },
            onHorizontalDragEnd: (details) {
              setState(() => _isDragging = false);
              _removeOverlay();
            },
            onTapDown: (details) {
              setState(() => _isDragging = true);
              _updateOpacityFromPosition(details.localPosition);
              _showOverlay(context, widget.videoState.danmakuOpacity);
            },
            onTapUp: (details) {
              setState(() => _isDragging = false);
              _removeOverlay();
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  key: _sliderKey,
                  clipBehavior: Clip.none,
                  children: [
                    // 背景轨道
                    Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // 进度轨道
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 20,
                      child: FractionallySizedBox(
                        widthFactor: widget.videoState.danmakuOpacity,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.3),
                                blurRadius: 2,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 滑块
                    Positioned(
                      left: (widget.videoState.danmakuOpacity * constraints.maxWidth) - (_isThumbHovered || _isDragging ? 8 : 6),
                      top: 22 - (_isThumbHovered || _isDragging ? 8 : 6),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          width: _isThumbHovered || _isDragging ? 16 : 12,
                          height: _isThumbHovered || _isDragging ? 16 : 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: _isThumbHovered || _isDragging ? 6 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        const SettingsHintText('拖动滑块调整弹幕透明度'),
      ],
    );
  }
} 