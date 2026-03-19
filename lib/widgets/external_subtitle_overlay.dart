import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class ExternalSubtitleOverlay extends StatelessWidget {
  final double currentPositionMs;

  const ExternalSubtitleOverlay({
    super.key,
    required this.currentPositionMs,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, _) {
        if (!videoState.shouldRenderCurrentExternalSubtitleInApp()) {
          return const SizedBox.shrink();
        }

        final subtitleTimeMs =
            currentPositionMs - videoState.subtitleDelaySeconds * 1000;
        final subtitleText =
            videoState.getCurrentExternalSubtitleTextAt(subtitleTimeMs.round());

        if (subtitleText.trim().isEmpty || videoState.subtitleOpacity <= 0) {
          return const SizedBox.shrink();
        }

        return IgnorePointer(
          ignoring: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.of(context).size.width;
              final baseFontSize = (width * 0.03).clamp(18.0, 42.0).toDouble();
              final fontSize = (baseFontSize * videoState.subtitleScale)
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
                fontFamily: videoState.subtitleFontName.isNotEmpty
                    ? videoState.subtitleFontName
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

              return Opacity(
                opacity: videoState.subtitleOpacity.clamp(0.0, 1.0).toDouble(),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24 + videoState.subtitleMarginX,
                    vertical: 16 + videoState.subtitleMarginY,
                  ),
                  child: Align(
                    alignment: Alignment(
                      _resolveHorizontalAlignment(videoState.subtitleAlignX),
                      _resolveVerticalAlignment(videoState.subtitlePosition),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width * 0.9),
                      child: _OutlinedSubtitleText(
                        text: subtitleText,
                        fillStyle: fillStyle,
                        borderStyle: borderStyle,
                        showBorder: videoState.subtitleBorderSize > 0,
                        textAlign: _resolveTextAlign(videoState.subtitleAlignX),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
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

  double _resolveVerticalAlignment(double subtitlePosition) {
    final normalized = subtitlePosition.clamp(
      VideoPlayerState.minSubtitlePosition,
      VideoPlayerState.maxSubtitlePosition,
    );
    return ((normalized / 100) * 1.6 - 0.8).clamp(-0.8, 0.8).toDouble();
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
