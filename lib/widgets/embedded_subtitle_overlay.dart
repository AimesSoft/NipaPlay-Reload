import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

/// 内嵌字幕整块移动模式的渲染层。
///
/// 内核只解码不渲染（sub-visibility=no），App 按 sub-text 轮询取文本整
/// 块渲染：双语两行是一个 Widget——位置滑块移动整块、行距永不随 libass
/// 的逐行插值收拢；水平边距按屏幕像素生效（与 ASS PlayRes 坐标系无关）。
/// 全局字幕设置（大小/位置/边距/对齐/透明度/描边/阴影/粗斜体/颜色）
/// 在此模式下全部直接作用于这块文本。
class EmbeddedSubtitleOverlay extends StatelessWidget {
  const EmbeddedSubtitleOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        if (!videoState.embeddedSubtitleOverlayMode) {
          return const SizedBox.shrink();
        }
        if (videoState.isKernelRenderedExternalAssActive) {
          // 外挂 ASS 由内核 libass 按脚本样式渲染（\pos 定位/彩色注解），
          // sub-text 纯文本块会把它压成白色居中文字，必须整层退位。
          return const SizedBox.shrink();
        }
        if (videoState.shouldHideSubtitlesForScreenshot) {
          // 截图「隐藏字幕」：仅在截图帧合成期间隐藏，不影响观看。
          return const SizedBox.shrink();
        }
        final text = videoState.embeddedSubtitleOverlayDisplayText;
        if (text.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.of(context).size.width;
            final baseFontSize = (width * 0.03).clamp(18.0, 42.0).toDouble();
            final fontSize =
                (baseFontSize * videoState.subtitleScale).clamp(14.0, 72.0);

            final shadowOffset = videoState.subtitleShadowOffset;
            final fillStyle = TextStyle(
              fontSize: fontSize,
              fontWeight:
                  videoState.subtitleBold ? FontWeight.bold : FontWeight.w500,
              fontStyle:
                  videoState.subtitleItalic ? FontStyle.italic : FontStyle.normal,
              color: videoState.subtitleColor,
              height: 1.3,
              shadows: shadowOffset > 0
                  ? [
                      Shadow(
                        color: videoState.subtitleShadowColor,
                        offset: Offset(0, shadowOffset),
                        blurRadius: shadowOffset * 2,
                      ),
                    ]
                  : null,
            );

            final borderSize = videoState.subtitleBorderSize;
            final Widget textBlock = borderSize > 0
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        text,
                        textAlign: _resolveTextAlign(videoState.subtitleAlignX),
                        softWrap: true,
                        style: fillStyle.copyWith(
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeJoin = StrokeJoin.round
                            ..strokeWidth = borderSize.clamp(0.0, 8.0)
                            ..color = videoState.subtitleBorderColor,
                          color: null,
                          shadows: null,
                        ),
                      ),
                      Text(
                        text,
                        textAlign: _resolveTextAlign(videoState.subtitleAlignX),
                        softWrap: true,
                        style: fillStyle,
                      ),
                    ],
                  )
                : Text(
                    text,
                    textAlign: _resolveTextAlign(videoState.subtitleAlignX),
                    softWrap: true,
                    style: fillStyle,
                  );

        return Opacity(
          opacity: videoState.subtitleOpacity.clamp(0.0, 1.0),
          child: LayoutBuilder(
            builder: (context, stage) {
              // 字幕块约束在视频显示矩形内（黑边不可达）：位置 100=视频
              // 底边，与内核 sub-pos 语义一致；水平边距保持舞台像素
              // （竖屏下视频宽=舞台宽，距离不变）。
              final videoRect = _videoRect(
                stage.maxWidth,
                stage.maxHeight,
                videoState.aspectRatio,
              );
              return Stack(
                children: [
                  Positioned(
                    left: videoRect.left,
                    top: videoRect.top,
                    width: videoRect.width,
                    height: videoRect.height,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      child: Align(
                        alignment: Alignment(
                          _resolveHorizontalAlignment(
                              videoState.subtitleAlignX),
                          // 垂直边距与内核路径同一折算：10px ≈ 1% 位置
                          // 百分比、向上移动，与位置滑块同通道叠加。
                          _resolveVerticalAlignment(
                              (videoState.subtitlePosition -
                                      videoState.subtitleMarginY * 0.1)
                                  .clamp(0.0, 100.0)),
                        ),
                        child: Transform.translate(
                          offset: Offset(videoState.subtitleMarginX, 0),
                          child: textBlock,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
          },
        );
      },
    );
  }

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

  /// 0=视频顶 100=视频底（与内核 sub-pos 同参照：整块移动模式下位置滑
  /// 块的语义与内核模式一致，字幕永不进入黑边）。
  double _resolveVerticalAlignment(double subtitlePosition) {
    final normalized = subtitlePosition.clamp(
      VideoPlayerState.minSubtitlePosition,
      VideoPlayerState.maxSubtitlePosition,
    );
    return (normalized / 100) * 2.0 - 1.0;
  }

  /// 按播放舞台尺寸与视频宽高比计算 contain 适配后的视频显示矩形
  /// （视频面是 Center+AspectRatio 居中，黑边在矩形之外）。
  Rect _videoRect(double stageW, double stageH, double aspect) {
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
}
