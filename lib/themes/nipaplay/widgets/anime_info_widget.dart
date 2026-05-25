import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as p;
import 'control_shadow.dart';
import 'dart:math' as math;
import 'package:characters/characters.dart';
// import 'package:nipaplay/utils/globals.dart' as globals; // globals is not used in this snippet

class AnimeInfoWidget extends StatefulWidget {
  final VideoPlayerState videoState;
  final double? maxWidth;

  const AnimeInfoWidget({
    super.key,
    required this.videoState,
    this.maxWidth,
  });

  @override
  State<AnimeInfoWidget> createState() => _AnimeInfoWidgetState();
}

class _AnimeInfoWidgetState extends State<AnimeInfoWidget> {
  static const String _ellipsis = '...';

  String? _resolveTitle(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _resolveFileName(String? path) {
    final trimmed = path?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _resolveTitle(p.basenameWithoutExtension(trimmed));
  }

  double _measureTextWidth({
    required BuildContext context,
    required String text,
    required TextStyle style,
  }) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return painter.width;
  }

  String _fitTextToWidth({
    required BuildContext context,
    required String text,
    required TextStyle style,
    required double maxWidth,
  }) {
    if (text.isEmpty || maxWidth <= 0) return '';
    if (_measureTextWidth(context: context, text: text, style: style) <=
        maxWidth) {
      return text;
    }

    final ellipsisWidth =
        _measureTextWidth(context: context, text: _ellipsis, style: style);
    if (ellipsisWidth > maxWidth) {
      return '';
    }

    final clusters = text.characters.toList(growable: false);
    int left = 0;
    int right = clusters.length;
    while (left < right) {
      final mid = (left + right + 1) >> 1;
      final candidate = '${clusters.take(mid).join()}$_ellipsis';
      if (_measureTextWidth(context: context, text: candidate, style: style) <=
          maxWidth) {
        left = mid;
      } else {
        right = mid - 1;
      }
    }

    if (left <= 0) return _ellipsis;
    return '${clusters.take(left).join()}$_ellipsis';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.videoState.hasVideo) {
      return const SizedBox.shrink();
    }

    final animeTitle = _resolveTitle(widget.videoState.animeTitle);
    final episodeTitle = _resolveTitle(widget.videoState.episodeTitle);
    final fileTitle = _resolveFileName(widget.videoState.currentVideoPath);
    final displayTitle = animeTitle ?? fileTitle ?? episodeTitle;
    final screenWidth = MediaQuery.of(context).size.width;
    final preferredMaxInfoWidth = widget.maxWidth ?? screenWidth * 0.72;
    final maxInfoWidth = math.min(
      screenWidth * 0.72,
      math.max(80.0, preferredMaxInfoWidth),
    );
    if (displayTitle == null) {
      return const SizedBox.shrink();
    }

    const titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );
    const episodeStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
    );

    const titleGap = 8.0;
    final hasEpisode = episodeTitle != null && episodeTitle != displayTitle;
    String? episodeText;
    double episodeWidth = 0;
    const titleWidthCapFactor = 0.62;
    const episodeWidthCapFactor = 0.34;
    final hasEpisodeSpace = hasEpisode;

    if (hasEpisodeSpace) {
      final fittedEpisodeText = _fitTextToWidth(
        context: context,
        text: episodeTitle!,
        style: episodeStyle,
        maxWidth: maxInfoWidth * episodeWidthCapFactor,
      );
      if (fittedEpisodeText.isNotEmpty) {
        episodeText = fittedEpisodeText;
        episodeWidth = _measureTextWidth(
          context: context,
          text: fittedEpisodeText,
          style: episodeStyle,
        );
      }
    }

    final titleMaxWidth = hasEpisodeSpace
        ? math.max(
            24.0,
            math.min(
              maxInfoWidth * titleWidthCapFactor,
              maxInfoWidth - episodeWidth - titleGap,
            ),
          )
        : maxInfoWidth;
    final fittedTitleText = _fitTextToWidth(
      context: context,
      text: displayTitle,
      style: titleStyle,
      maxWidth: titleMaxWidth,
    );
    final titleWidth = _measureTextWidth(
      context: context,
      text: fittedTitleText,
      style: titleStyle,
    );

    return AnimatedSlide(
      duration: const Duration(milliseconds: 150),
      offset: Offset(widget.videoState.showControls ? 0 : -0.1, 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxInfoWidth),
        child: MouseRegion(
          onEnter: (_) {
            widget.videoState.setControlsHovered(true);
          },
          onExit: (_) {
            widget.videoState.setControlsHovered(false);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(
                  width: titleWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ControlTextShadow(
                      child: Text(
                        fittedTitleText,
                        style: titleStyle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ),
                ),
                if (episodeText != null && episodeText.isNotEmpty) ...[
                  const SizedBox(width: titleGap),
                  SizedBox(
                    width: episodeWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: episodeStyle,
                        child: ControlTextShadow(
                          child: Text(
                            episodeText,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
