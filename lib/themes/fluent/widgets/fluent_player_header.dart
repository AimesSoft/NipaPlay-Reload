import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class FluentPlayerHeader extends StatelessWidget {
  const FluentPlayerHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final videoState = Provider.of<VideoPlayerState>(context);
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(FluentIcons.back, size: 20),
            onPressed: () async {
              try {
                // 先调用handleBackButton处理截图
                await videoState.handleBackButton();
                // 然后重置播放器状态
                await videoState.resetPlayer();
              } catch (e) {
                // 静默处理错误，保持与nipaplay主题一致的行为
              }
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (videoState.animeTitle != null && videoState.animeTitle!.isNotEmpty)
                  Text(
                    videoState.animeTitle!,
                    style: theme.typography.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (videoState.episodeTitle != null && videoState.episodeTitle!.isNotEmpty)
                  Text(
                    videoState.episodeTitle!,
                    style: theme.typography.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}