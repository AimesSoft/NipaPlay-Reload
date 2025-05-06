import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../utils/video_player_state.dart';
import '../utils/globals.dart' as globals;

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

  @override
  Widget build(BuildContext context) {
    if (!(widget.videoState.hasVideo && 
          widget.videoState.animeTitle != null && 
          widget.videoState.episodeTitle != null)) {
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
                maxWidth: MediaQuery.of(context).size.width * 0.5,
              ),
              child: IntrinsicWidth(
                child: GlassmorphicContainer(
                  width: double.infinity,
                  height: 48,
                  borderRadius: 24,
                  blur: 20,
                  alignment: Alignment.center,
                  border: 1,
                  linearGradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF808080).withOpacity(0.3),
                      const Color(0xFF808080).withOpacity(0.3),
                    ],
                  ),
                  borderGradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFffffff).withOpacity(0.5),
                      const Color(0xFFFFFFFF).withOpacity(0.5),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          widget.videoState.animeTitle!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 8),
                        MouseRegion(
                          onEnter: (_) {
                            setState(() => _isEpisodeHovered = true);
                          },
                          onExit: (_) {
                            setState(() => _isEpisodeHovered = false);
                          },
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              color: _isEpisodeHovered ? Colors.white : Colors.white70,
                              fontSize: 14,
                            ),
                            child: Text(
                              widget.videoState.episodeTitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
    );
  }
} 