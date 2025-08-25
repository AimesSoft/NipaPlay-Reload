import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class FluentPlayerControlBar extends StatefulWidget {
  const FluentPlayerControlBar({super.key});

  @override
  State<FluentPlayerControlBar> createState() => _FluentPlayerControlBarState();
}

class _FluentPlayerControlBarState extends State<FluentPlayerControlBar> {
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${duration.inHours > 0 ? '${twoDigits(duration.inHours)}:' : ''}$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final videoState = Provider.of<VideoPlayerState>(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProgressBar(videoState),
          Row(
            children: [
              _buildPlayPauseButton(videoState),
              _buildSkipButton(videoState, isForward: false),
              _buildSkipButton(videoState, isForward: true),
              const SizedBox(width: 8),
              _buildTimeLabel(videoState),
              const Spacer(),
              _buildSettingsButton(videoState),
              _buildFullscreenButton(videoState),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(VideoPlayerState videoState) {
    return Slider(
      value: videoState.position.inMilliseconds.toDouble(),
      min: 0.0,
      max: videoState.duration.inMilliseconds.toDouble(),
      onChanged: (value) {
        videoState.seekTo(Duration(milliseconds: value.toInt()));
      },
    );
  }

  Widget _buildPlayPauseButton(VideoPlayerState videoState) {
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
        child: Icon(
          videoState.status == PlayerStatus.playing ? FluentIcons.pause : FluentIcons.play,
          key: ValueKey<bool>(videoState.status == PlayerStatus.playing),
          size: 24,
        ),
      ),
      onPressed: () => videoState.togglePlayPause(),
    );
  }

  Widget _buildSkipButton(VideoPlayerState videoState, {required bool isForward}) {
    final icon = isForward ? FluentIcons.fast_forward : FluentIcons.rewind;
    final tooltip = isForward ? '快进 10 秒' : '快退 10 秒';
    final action = isForward ? () => videoState.seekTo(videoState.position + const Duration(seconds: 10)) : () => videoState.seekTo(videoState.position - const Duration(seconds: 10));

    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: action,
      ),
    );
  }

  Widget _buildTimeLabel(VideoPlayerState videoState) {
    return Text(
      '${_formatDuration(videoState.position)} / ${_formatDuration(videoState.duration)}',
      style: FluentTheme.of(context).typography.caption,
    );
  }

  Widget _buildSettingsButton(VideoPlayerState videoState) {
    return Tooltip(
      message: '设置',
      child: IconButton(
        icon: Icon(
          FluentIcons.settings,
          size: 20,
          color: videoState.showRightMenu 
            ? FluentTheme.of(context).accentColor 
            : null,
        ),
        onPressed: () {
          videoState.toggleRightMenu();
        },
      ),
    );
  }

  Widget _buildFullscreenButton(VideoPlayerState videoState) {
    return Tooltip(
      message: videoState.isFullscreen ? '退出全屏' : '全屏',
      child: IconButton(
        icon: Icon(
          videoState.isFullscreen ? FluentIcons.back_to_window : FluentIcons.full_screen,
          size: 20,
        ),
        onPressed: () => videoState.toggleFullscreen(),
      ),
    );
  }
}