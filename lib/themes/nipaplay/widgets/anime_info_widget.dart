import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as p;
import 'control_shadow.dart';
// import 'package:nipaplay/utils/globals.dart' as globals; // globals is not used in this snippet

class AnimeInfoWidget extends StatefulWidget {
  final VideoPlayerState videoState;

  const AnimeInfoWidget({
    super.key,
    required this.videoState,
  });

  @override
  State<AnimeInfoWidget> createState() => _AnimeInfoWidgetState();
}

class _AnimeInfoWidgetState extends State<AnimeInfoWidget> {
  bool _isEpisodeHovered = false;

  String? _resolveTitle(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _resolveFileName(String? path) {
    final trimmed = path?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _resolveTitle(p.basenameWithoutExtension(trimmed));
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
    if (displayTitle == null) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: widget.videoState.showControls ? 1.0 : 0.0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 150),
        offset: Offset(widget.videoState.showControls ? 0 : -0.1, 0),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.4,
          ),
          child: IntrinsicWidth(
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
                    Flexible(
                      child: ControlTextShadow(
                        child: Text(
                          displayTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (episodeTitle != null &&
                        episodeTitle != displayTitle) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: MouseRegion(
                          onEnter: (_) {
                            setState(() => _isEpisodeHovered = true);
                          },
                          onExit: (_) {
                            setState(() => _isEpisodeHovered = false);
                          },
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            child: ControlTextShadow(
                              child: Text(
                                episodeTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
        ),
      ),
    );
  }
} 
