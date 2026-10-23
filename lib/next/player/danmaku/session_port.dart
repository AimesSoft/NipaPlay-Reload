import 'dart:async';
import 'dart:isolate';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/utils/dandanplay_comments.dart';
import 'package:nipaplay/utils/danmaku_parser.dart';
import 'package:nipaplay/utils/danmaku_xml_parse.dart';

import '../../danmaku/service.dart';
import '../../danmaku/source.dart';
import '../next_playback.dart';
import 'controller.dart';

/// Binds the existing track service, sidecars and remote tracks to one Next
/// session. Registry rows are small metadata; comment lists live in the worker.
final class SessionDanmakuPort implements PlaybackDanmakuPort {
  SessionDanmakuPort(this.controller, this.currentTarget, {this.requestChange});
  final SessionDanmakuController controller;
  final DanmakuPlaybackTarget? Function() currentTarget;
  final Future<void> Function(String, String, Object?)? requestChange;
  final _tracks = <String, JsonMap>{};
  String? _sessionId;

  void _sync() {
    if (_sessionId == controller.sessionId) return;
    _sessionId = controller.sessionId;
    _tracks.clear();
  }

  @override
  DanmakuPlaybackTarget? get target => currentTarget();
  bool _matches(DanmakuPlaybackTarget expected) =>
      target?.path == expected.path &&
      target?.generation == expected.generation;

  @override
  Set<String> get managedTracks {
    _sync();
    return _tracks.keys.toSet();
  }

  @override
  List<JsonMap> get registry {
    _sync();
    return [for (final entry in _tracks.entries) {
      ...entry.value, 'trackId': entry.key,
      'enabled': entry.value['enabled'] == 1,
      'revision': entry.value['revision'],
      'offsetMs': entry.value['offset_ms'],
      'deduplicate': entry.value['deduplicate'] == 1,
      'bindingId': entry.key,
    }];
  }

  @override
  JsonMap? loaded(String bindingId) {
    _sync();
    final track = _tracks[bindingId];
    if (track == null) return null;
    return {'revision': track['revision'], 'cacheRevision': track['cache_revision'],
      'cacheKey': track['cache_key'], 'startMs': track['startMs'],
      'endMs': track['endMs']};
  }

  @override
  bool install(DanmakuPlaybackTarget expected, JsonMap binding,
      List<DanmakuEntry> entries, {int startMs = 0, int? endMs}) {
    if (!_matches(expected)) return false;
    _sync();
    final id = binding['id'] as String;
    final video = binding['video'] as JsonMap;
    _tracks[id] = {...binding, 'startMs': startMs, 'endMs': endMs,
      'count': entries.length, 'name': video['title'],
      'source': video['sourceId'], 'platform': video['sourceId'],
      'platformVideoId': video['videoId'],
      'origin': binding['local_file'] != null ? 'sidecar'
          : binding['bound_by'] == 'agent' ? 'agent_import'
          : binding['bound_by'] == 'automatic' ? 'playback' : 'binding'};
    controller.install(id, binding, entries, startMs: startMs, endMs: endMs);
    return true;
  }

  @override
  bool reuse(DanmakuPlaybackTarget expected, JsonMap binding) {
    if (!_matches(expected)) return false;
    _sync();
    final id = binding['id'] as String;
    final existing = _tracks[id];
    if (existing == null || existing['cache_key'] != binding['cache_key'] ||
        existing['cache_revision'] != binding['cache_revision']) {
      return false;
    }
    _tracks[id] = {...existing, ...binding};
    controller.update(id, binding);
    return true;
  }

  @override
  void remove(String bindingId) {
    _sync();
    if (_tracks.remove(bindingId) != null) controller.remove(bindingId);
  }

  @override
  bool updateTrack(DanmakuPlaybackTarget expected, String trackId,
      JsonMap properties) {
    if (!_matches(expected)) return false;
    _sync();
    final track = _tracks[trackId];
    if (track == null) return false;
    if (requestChange != null) {
      for (final field in properties.entries) {
        final (operation, value) = switch (field.key) {
          'offsetMs' => ('offset', (field.value as num) / 1000),
          'enabled' => ('enabled', field.value),
          _ => ('', null),
        };
        if (operation.isNotEmpty) {
          unawaited(requestChange!(trackId, operation, value));
        }
      }
    }
    final updated = {...track,
      if (properties.containsKey('offsetMs')) 'offset_ms': properties['offsetMs'],
      if (properties.containsKey('enabled')) 'enabled': properties['enabled'] == true ? 1 : 0,
      if (properties.containsKey('displayFold')) 'deduplicate': properties['displayFold'] == true ? 1 : 0,
    };
    _tracks[trackId] = updated;
    controller.update(trackId, updated);
    return true;
  }

  @override
  Future<bool> restoreClassic(DanmakuPlaybackTarget expected, JsonMap binding) async {
    final video = binding['video'] as JsonMap;
    if (video['sourceId'] != 'dandanplay') return false;
    // The cache is shared data. Its parsing and conversion are background work.
    final comments = await DanmakuCacheManager.getDanmakuFromCache(video['videoId'] as String);
    if (comments == null || !_matches(expected)) return false;
    final videoId = video['videoId'] as String;
    final entries = await Isolate.run(() {
      final rows = parseDanmakuListInBackground(restoreDandanplayOrigins(comments));
      return [for (final row in rows) DanmakuEntry(
        sourceId: 'dandanplay', videoId: videoId,
        platform: row['source'] as String? ?? 'unknown',
        originVideoId: row['platformVideoId'] as String?,
        platformId: row['platformDanmakuId'] as String?,
        sourceTimeMs: ((row['time'] as num) * 1000).round(),
        text: row['content'] as String,
        mode: row['type'] == 'top' ? 5 : row['type'] == 'bottom' ? 4 : 1,
        colorRgb: parseDanmakuColorToInt(row['color']))];
    });
    return install(expected, binding, entries);
  }
}
