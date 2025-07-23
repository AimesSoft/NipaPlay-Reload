import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:provider/provider.dart';
import '../../utils/video_player_state.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import '../../providers/developer_options_provider.dart';
import 'gpu_danmaku_renderer.dart';
import 'gpu_danmaku_config.dart';
import 'dynamic_font_atlas.dart';

/// GPU弹幕覆盖层组件
///
/// 使用Flutter GPU API和自定义着色器渲染弹幕
/// 它接收已经计算好位置的弹幕列表，并进行高效渲染。
class GPUDanmakuOverlay extends StatefulWidget {
  final List<PositionedDanmakuItem> positionedDanmaku;
  final bool isPlaying;
  final GPUDanmakuConfig config;
  final bool isVisible;
  final double opacity;
  final double currentTime;

  const GPUDanmakuOverlay({
    super.key,
    required this.positionedDanmaku,
    required this.isPlaying,
    required this.config,
    required this.isVisible,
    required this.opacity,
    required this.currentTime,
  });

  /// 预构建弹幕字符集（用于视频初始化时优化）
  ///
  /// 在视频初始化时调用，预扫描所有弹幕文本并生成完整字符图集
  /// 避免播放时的动态图集更新导致的延迟
  static Future<void> prebuildDanmakuCharset(
      List<Map<String, dynamic>> danmakuList) async {
    if (danmakuList.isEmpty) return;

    debugPrint('GPUDanmakuOverlay: 开始预构建弹幕字符集');

    // 提取所有弹幕文本
    final List<String> texts = [];
    for (final danmaku in danmakuList) {
      final text = danmaku['content']?.toString() ?? '';
      if (text.isNotEmpty) {
        texts.add(text);
      }
    }

    if (texts.isEmpty) {
      debugPrint('GPUDanmakuOverlay: 没有弹幕文本，跳过字符集预构建');
      return;
    }

    // 使用全局字体图集管理器进行预构建
    final config = GPUDanmakuConfig();

    try {
      // 使用全局管理器预构建弹幕字符集
      await FontAtlasManager.prebuildFromTexts(
        fontSize: config.fontSize,
        texts: texts,
      );

      debugPrint('GPUDanmakuOverlay: 弹幕字符集预构建完成');
    } catch (e) {
      debugPrint('GPUDanmakuOverlay: 弹幕字符集预构建失败: $e');
    }
  }

  @override
  State<GPUDanmakuOverlay> createState() => _GPUDanmakuOverlayState();
}

class _GPUDanmakuOverlayState extends State<GPUDanmakuOverlay> {
  GPUDanmakuRenderer? _renderer;

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
  }

  void _initializeRenderer() {
    debugPrint('GPUDanmakuOverlay: 初始化渲染器');
    final devOptions = context.read<DeveloperOptionsProvider>();
    _renderer = GPUDanmakuRenderer(
      config: widget.config,
      opacity: widget.opacity,
      isPaused: !widget.isPlaying,
      isVisible: widget.isVisible,
      showCollisionBoxes: devOptions.showGPUDanmakuCollisionBoxes,
      showTrackNumbers: devOptions.showGPUDanmakuTrackNumbers,
      onNeedRepaint: () {
        // This callback might still be useful if the font atlas updates itself
        // and needs to trigger a repaint outside of the renderer's own state changes.
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  void didUpdateWidget(GPUDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    _renderer?.setPaused(!widget.isPlaying);
    _renderer?.setVisibility(widget.isVisible);
    _renderer?.updateOptions(newConfig: widget.config, opacity: widget.opacity);
    if (widget.config.fontSize != oldWidget.config.fontSize) {
      // Font size change requires re-initialization of renderers
      _initializeRenderer();
    }
    
    // Pass the already computed danmaku to the renderer
    // MOVED to build() method to ensure repaint happens.
    // _renderer?.setDanmaku(widget.positionedDanmaku, widget.currentTime);

    // No need for addPostFrameCallback for debug options, can be updated directly.
    _checkDebugOptionsChange();
  }

  /// 检查开发者设置变化
  void _checkDebugOptionsChange() {
    final devOptions = context.read<DeveloperOptionsProvider>();
    _renderer?.updateDebugOptions(
      showCollisionBoxes: devOptions.showGPUDanmakuCollisionBoxes,
      showTrackNumbers: devOptions.showGPUDanmakuTrackNumbers,
    );
  }

  @override
  void dispose() {
    debugPrint('GPUDanmakuOverlay: 释放资源');
    _renderer?.dispose();
    FontAtlasManager.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pass the latest danmaku data to the renderer right before painting.
    // This ensures that even if the widget itself doesn't rebuild,
    // the painter has the most current data.
    _renderer?.setDanmaku(widget.positionedDanmaku, widget.currentTime);

    return CustomPaint(
      painter: _renderer,
      child: const SizedBox.expand(),
    );
  }
} 