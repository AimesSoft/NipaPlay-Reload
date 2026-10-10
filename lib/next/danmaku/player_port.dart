import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'source.dart';
import 'service.dart';

final class VideoDanmakuPort implements DanmakuPlayerPort {
  const VideoDanmakuPort(this.player, {this.requestChange});
  final VideoPlayerState player;
  final Future<void> Function(
      String bindingId, String operation, Object? value)? requestChange;
  String trackId(String id) => 'next:$id';
  @override
  DanmakuPlaybackTarget? get target => player.currentVideoPath == null
      ? null
      : DanmakuPlaybackTarget(
          player.currentVideoPath!, player.playbackGeneration);
  @override
  Set<String> get managedTracks => player.danmakuTracks.keys
      .where((id) => id.startsWith('next:'))
      .map((id) => id.substring(5))
      .toSet();
  @override
  JsonMap? loaded(String id) {
    final track = player.danmakuTracks[trackId(id)];
    if (track == null) return null;
    return {
      'revision': track['bindingRevision'],
      'cacheRevision': track['cacheRevision'],
      'cacheKey': track['cacheKey'],
      'startMs': track['startMs'],
      'endMs': track['endMs']
    };
  }

  @override
  bool install(
      DanmakuPlaybackTarget target, JsonMap binding, List<DanmakuEntry> entries,
      {int startMs = 0, int? endMs}) {
    final v = binding['video'] as JsonMap;
    return player.installSourceDanmakuTrack(
        trackId: trackId(binding['id'] as String),
        expectedPath: target.path,
        expectedGeneration: target.generation,
        metadata: {
          'name': '${v['sourceId']} · ${v['title']}',
          'source': v['sourceId'],
          'video': v,
          'bindingRevision': binding['revision'],
          'cacheKey': binding['cache_key'],
          'cacheRevision': binding['cache_revision'],
          'aggregation': v['sourceId'] == 'dandanplay',
          'deduplicate': binding['deduplicate'] == 1,
          'startMs': startMs,
          'endMs': endMs
        },
        entries: [
          for (final e in entries)
            if (endMs == null ||
                e.sourceTimeMs + startMs - (binding['offset_ms'] as int) <
                    endMs)
              {...e.toPlayer(), 'time': (e.sourceTimeMs + startMs) / 1000}
        ],
        enabled: binding['enabled'] == 1,
        offsetSeconds: (binding['offset_ms'] as int) / 1000,
        requestChange: requestChange == null
            ? null
            : (operation, value) =>
                requestChange!(binding['id'] as String, operation, value));
  }

  @override
  void remove(String bindingId) =>
      player.removeSourceDanmakuTrack(trackId(bindingId));
}
