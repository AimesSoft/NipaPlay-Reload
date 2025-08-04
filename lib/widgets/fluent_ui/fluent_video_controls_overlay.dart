import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'fluent_player_control_bar.dart';
import 'fluent_player_header.dart';

class FluentVideoControlsOverlay extends StatelessWidget {
  const FluentVideoControlsOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final videoState = Provider.of<VideoPlayerState>(context);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: videoState.showControls ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !videoState.showControls,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                  ),
                ),
                child: const FluentPlayerHeader(),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                  ),
                ),
                child: const FluentPlayerControlBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
