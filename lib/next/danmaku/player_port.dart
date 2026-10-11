import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/utils/danmaku_parser.dart';
import 'package:nipaplay/utils/dandanplay_comments.dart';
import 'package:nipaplay/utils/danmaku_track_timing.dart';
import 'source.dart';
import 'service.dart';

final class VideoDanmakuPort
    implements DanmakuPlayerPort, DanmakuTrackRegistry, DanmakuTrackUpdater {
  const VideoDanmakuPort(this.player, {this.requestChange});
  final VideoPlayerState player;
  final Future<void> Function(
      String bindingId, String operation, Object? value)? requestChange;
  String trackId(String id) =>
      player.danmakuTracks.entries
          .where((e) => e.value['bindingId'] == id)
          .map((e) => e.key)
          .firstOrNull ??
      'next:$id';
  @override
  bool updateTrack(
      DanmakuPlaybackTarget expected, String id, JsonMap properties) {
    if (target?.path != expected.path ||
        target?.generation != expected.generation) {
      return false;
    }
    final track = player.danmakuTracks[id];
    if (track == null || track['bindingId'] != null) return false;
    if (id == 'timeline' && properties.containsKey('offsetMs')) {
      throw const Failure(FailureCode.invalidInput,
          'The live timeline track does not support a fixed offset.');
    }
    if (properties.containsKey('displayFold')) {
      track['deduplicate'] = properties['displayFold'];
    }
    if (properties.containsKey('offsetMs')) {
      player.setDanmakuTrackOffset(id, (properties['offsetMs'] as int) / 1000);
    }
    player.toggleDanmakuTrack(
        id,
        properties['enabled'] as bool? ??
            player.danmakuTrackEnabled[id] == true);
    return true;
  }

  @override
  List<JsonMap> get registry => [
        for (final e in player.danmakuTracks.entries)
          {
            'trackId': e.key,
            'name': e.value['name'],
            'source': e.value['source'],
            'origin': e.value['origin'] ?? 'auto_remote',
            if (e.value['provenance'] != null)
              'provenance': e.value['provenance'],
            'platform': e.value['platform'] ??
                (e.key == 'dandanplay' ? 'dandanplay' : 'unknown'),
            'platformVideoId': e.value['platformVideoId'] ??
                (e.key == 'dandanplay' ? player.episodeId?.toString() : null),
            'filePath': e.value['filePath'],
            'bindingId': e.value['bindingId'],
            if (e.value['bindingRevision'] != null)
              'revision': e.value['bindingRevision'],
            if (e.value['entityId'] != null) 'entityId': e.value['entityId'],
            'offsetMs': (DanmakuTrackTiming.offsetOf(e.value) * 1000).round(),
            'deduplicate': e.value['deduplicate'] != false,
            'count': e.value['count'] ?? 0,
            'enabled': player.danmakuTrackEnabled[e.key] == true
          }
      ];
  @override
  bool reuse(DanmakuPlaybackTarget target, JsonMap binding) {
    final video = binding['video'] as JsonMap;
    final track = registry
        .where((t) =>
            t['platform'] == video['sourceId'] &&
            t['platformVideoId'] == video['videoId'])
        .firstOrNull;
    if (track == null) return false;
    return player.bindExistingDanmakuTrack(track['trackId'] as String,
        expectedPath: target.path,
        expectedGeneration: target.generation,
        metadata: _metadata(binding, 0, null),
        enabled: binding['enabled'] == 1,
        offsetSeconds: (binding['offset_ms'] as int) / 1000,
        requestChange: requestChange == null
            ? null
            : (op, value) =>
                requestChange!(binding['id'] as String, op, value));
  }

  JsonMap _metadata(JsonMap binding, int startMs, int? endMs) => {
        'bindingId': binding['id'],
        'entityId': binding['entity_id'],
        'bindingRevision': binding['revision'],
        'cacheKey': binding['cache_key'],
        'cacheRevision': binding['cache_revision'],
        'deduplicate': binding['deduplicate'] == 1,
        'startMs': startMs,
        'endMs': endMs
      };
  @override
  Future<bool> restoreClassic(
      DanmakuPlaybackTarget target, JsonMap binding) async {
    final video = binding['video'] as JsonMap;
    if (video['sourceId'] != 'dandanplay') return false;
    final cached = await DanmakuCacheManager.getDanmakuFromCache(
        video['videoId'] as String);
    if (cached == null) return false;
    if (reuse(target, binding)) return true;
    return player.installSourceDanmakuTrack(
        trackId: 'dandanplay',
        expectedPath: target.path,
        expectedGeneration: target.generation,
        metadata: {
          ..._metadata(binding, 0, null),
          'name': '弹弹play',
          'origin': 'binding',
          'source': 'dandanplay',
          'platform': 'dandanplay',
          'platformVideoId': video['videoId'],
          'aggregation': true
        },
        entries: parseDanmakuListInBackground(restoreDandanplayOrigins(cached)),
        enabled: binding['enabled'] == 1,
        offsetSeconds: (binding['offset_ms'] as int) / 1000,
        requestChange: requestChange == null
            ? null
            : (op, value) =>
                requestChange!(binding['id'] as String, op, value));
  }

  @override
  DanmakuPlaybackTarget? get target => player.currentVideoPath == null
      ? null
      : DanmakuPlaybackTarget(
          player.currentVideoPath!, player.playbackGeneration,
          durationMs: player.duration.inMilliseconds);
  @override
  Set<String> get managedTracks => player.danmakuTracks.values
      .where((t) => t['bindingId'] != null)
      .map((t) => t['bindingId'] as String)
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
    final local = v['sourceId'] == 'local';
    final provenance = local
        ? localDanmakuProvenance(entries)
        : {'platform': v['sourceId'], 'platformVideoId': v['videoId']};
    return player.installSourceDanmakuTrack(
        trackId: v['sourceId'] == 'dandanplay'
            ? 'dandanplay'
            : trackId(binding['id'] as String),
        expectedPath: target.path,
        expectedGeneration: target.generation,
        metadata: {
          ..._metadata(binding, startMs, endMs),
          'origin': binding['provenance'] != null
              ? binding['bound_by'] == 'agent'
                  ? 'agent_import'
                  : 'manual_import'
              : local
                  ? 'manual_import'
                  : 'binding',
          if (binding['provenance'] != null)
            'provenance': binding['provenance'],
          ...provenance,
          if (local) 'filePath': v['videoId'],
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
