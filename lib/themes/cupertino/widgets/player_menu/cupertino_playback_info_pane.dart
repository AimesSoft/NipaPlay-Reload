import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoPlaybackInfoPane extends StatelessWidget {
  const CupertinoPlaybackInfoPane({
    super.key,
    required this.videoState,
    required this.onBack,
  });

  final VideoPlayerState videoState;
  final VoidCallback onBack;

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
        (videoState.animeId != null ? videoState.animeId.toString() : null);
    final String? danmakuEpisodeId = dandanTrack?['episodeId']?.toString() ??
        (videoState.episodeId != null ? videoState.episodeId.toString() : null);

    final List<_InfoRow> rows = [
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
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: onBack),
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
