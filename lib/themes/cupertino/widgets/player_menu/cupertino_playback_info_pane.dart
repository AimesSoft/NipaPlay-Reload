import 'package:flutter/cupertino.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoPlaybackInfoPane extends StatelessWidget {
  const CupertinoPlaybackInfoPane({
    super.key,
    required this.videoState,
  });

  final VideoPlayerState videoState;

  @override
  Widget build(BuildContext context) {
    final List<_InfoRow> rows = [
      _InfoRow('作品标题', videoState.animeTitle ?? '未知'),
      _InfoRow('剧集标题', videoState.episodeTitle ?? '未知'),
      _InfoRow('当前位置', _formatDuration(videoState.position)),
      _InfoRow('总时长', _formatDuration(videoState.duration)),
      _InfoRow('播放速度', '${videoState.playbackRate}x'),
      _InfoRow('当前源', videoState.currentVideoPath ?? '未知'),
    ];

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.only(top: topSpacing, bottom: 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              CupertinoListSection.insetGrouped(
                header: const Text('播放信息'),
                children: rows
                    .map(
                      (row) => CupertinoListTile(
                        title: Text(row.title),
                        subtitle: Text(row.value),
                      ),
                    )
                    .toList(),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null || duration.inMilliseconds <= 0) {
      return '未知';
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _InfoRow {
  const _InfoRow(this.title, this.value);
  final String title;
  final String value;
}
