import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class FluentPlaybackInfoMenu extends StatelessWidget {
  const FluentPlaybackInfoMenu({
    super.key,
    required this.videoState,
  });

  final VideoPlayerState videoState;

  @override
  Widget build(BuildContext context) {
    final tracks = videoState.danmakuTracks;
    final enabledCount = tracks.keys
        .where((trackId) => videoState.danmakuTrackEnabled[trackId] == true)
        .length;

    Map<String, dynamic>? dandanTrack;
    for (final entry in tracks.entries) {
      final source = entry.value['source']?.toString();
      if (entry.key == 'dandanplay' || source == 'dandanplay') {
        dandanTrack = entry.value;
        break;
      }
    }

    final String? danmakuAnimeId = dandanTrack?['animeId']?.toString() ??
        videoState.animeId?.toString();
    final String? danmakuEpisodeId = dandanTrack?['episodeId']?.toString() ??
        videoState.episodeId?.toString();

    final items = <_InfoRow>[
      _InfoRow('作品标题', videoState.animeTitle ?? '未知'),
      _InfoRow('剧集标题', videoState.episodeTitle ?? '未知'),
      _InfoRow(
        '弹幕轨道',
        tracks.isEmpty ? '无' : '$enabledCount/${tracks.length} 启用',
      ),
      _InfoRow('弹幕合并条数', '${videoState.danmakuList.length}'),
      _InfoRow(
        '弹幕ID',
        (danmakuAnimeId == null && danmakuEpisodeId == null)
            ? '未知'
            : 'animeId=${danmakuAnimeId ?? '-'}, episodeId=${danmakuEpisodeId ?? '-'}',
      ),
      _InfoRow(
        '弹弹play条数',
        dandanTrack?['count'] != null ? '${dandanTrack!['count']}' : '未加载',
      ),
      _InfoRow('当前位置', _formatDuration(videoState.position)),
      _InfoRow('总时长', _formatDuration(videoState.duration)),
      _InfoRow('播放速度', '${videoState.playbackRate}x'),
      _InfoRow('当前源', _formatSource(videoState.currentVideoPath)),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '当前播放状态与弹幕匹配信息',
          style: FluentTheme.of(context).typography.caption?.copyWith(
                color: FluentTheme.of(context).resources.textFillColorSecondary,
              ),
        ),
        const SizedBox(height: 12),
        ...items.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoLabel(
              label: row.title,
              child: Text(
                row.value,
                maxLines: row.title == '当前源' ? 2 : null,
                overflow:
                    row.title == '当前源' ? TextOverflow.ellipsis : TextOverflow.visible,
              ),
            ),
          );
        }),
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

  String _formatSource(String? source) {
    if (source == null || source.isEmpty) return '未知';
    final idx = source.lastIndexOf('/');
    if (idx >= 0 && idx < source.length - 1) {
      return source.substring(idx + 1);
    }
    return source;
  }
}

class _InfoRow {
  const _InfoRow(this.title, this.value);
  final String title;
  final String value;
}
