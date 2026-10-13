import 'dart:async';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/subtitle_parser.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/media_identity_resolver.dart';
import '../public_url.dart';
import 'classic_action.dart';
import 'video_player_state_port.dart';

abstract interface class PlaybackInspectionPort {
  Future<JsonMap> inspect(String operation, JsonMap input);
}

final class PlaybackInspectionCapability implements Capability {
  PlaybackInspectionCapability(PlaybackInspectionPort port)
      : actions = [
          for (final entry in _specs.entries)
            ClassicAction(
                ActionSpec(
                    id: entry.key,
                    title: entry.key,
                    description: entry.value.$1,
                    effect: entry.value.$2,
                    input: entry.value.$3,
                    output: const ObjectSchema({}, additionalProperties: true)),
                (input, _) => port.inspect(entry.key, input))
        ];
  @override
  final List<Action> actions;
}

const _session = StringSchema(minLength: 1);
const _specs = <String, (String, Effect, ObjectSchema)>{
  'playback.wait': (
    'Bounded observation of this session only. until=ready/playing/paused/buffering/error; timeoutMs <= 30000 (default 5000). Returns matched, timeout, error or session_changed with the observed snapshot. A command being accepted is not evidence of playback success.',
    Effect.read,
    ObjectSchema({
      'sessionId': _session,
      'until': StringSchema(
          values: ['ready', 'playing', 'paused', 'buffering', 'error']),
      'timeoutMs': IntegerSchema(minimum: 0, maximum: 30000)
    }, required: [
      'sessionId',
      'until'
    ])
  ),
  'playback.retry': (
    'Explicitly reload the same internal source through Classic initialization, resolving its source again. Keeps saved progress, detail context and manual danmaku offset. preservePosition defaults true. Result describes observed readiness; further observation uses wait. External reload is unsupported.',
    Effect.write,
    ObjectSchema({'sessionId': _session, 'preservePosition': BooleanSchema()},
        required: ['sessionId'])
  ),
  'playback.chapters': (
    'Read container chapter markers, current index and all detected opening/ending segments with provenance. Empty list means no markers/segments, not permission to invent them.',
    Effect.read,
    ObjectSchema({})
  ),
  'playback.navigate': (
    'Use exactly one chapterIndex, frameDelta (-1 or +1), or skipKind (current/opening/ending). Chapter/skip use the same Classic operation. Frame result reports native or approximate 42ms seek honestly. Accepted command and observed position are distinct.',
    Effect.write,
    ObjectSchema({
      'sessionId': _session,
      'chapterIndex': IntegerSchema(minimum: 0),
      'frameDelta': IntegerSchema(minimum: -1, maximum: 1),
      'skipKind': StringSchema(values: ['current', 'opening', 'ending'])
    }, required: [
      'sessionId'
    ], oneOfRequired: [
      ['chapterIndex'],
      ['frameDelta'],
      ['skipKind']
    ])
  ),
  'playback.playlist': (
    'Read the current playback detail source and its exact ordered cached/loaded episodes. Does not reconstruct a list from catalog IDs. Legacy playback without detail context reports unsupported. Authenticated actualPlayUrl is never returned.',
    Effect.read,
    ObjectSchema({})
  ),
  'subtitle.cues': (
    'Read timed text from active external subtitle tracks, including current cues and surrounding lines. Omit positionMs for current position, context defaults 2 (0–10). Optional startMs/endMs restrict interval; cursor is an index in the session/track cue array, limit defaults 100. Display times include global and per-track delay. Embedded/bitmap text is unavailable without extraction/OCR, explicitly reported. This is the active text timeline, not pixel/OCR observation.',
    Effect.read,
    ObjectSchema({
      'sessionId': _session,
      'positionMs': IntegerSchema(minimum: 0),
      'context': IntegerSchema(minimum: 0, maximum: 10),
      'startMs': IntegerSchema(minimum: 0),
      'endMs': IntegerSchema(minimum: 0),
      'limit': IntegerSchema(minimum: 1, maximum: 500),
      'cursor': IntegerSchema(minimum: 0)
    })
  ),
  'danmaku.entries': (
    'Read the current merged and filtered display timeline near current/positionMs (windowMs default 5000) or explicit startMs/endMs, with stable pagination within this list version. Includes global time mapping, track/source provenance when present. This is the timeline delivered to the renderer, not a claim that each comment is visible in pixels. Raw bound pools remain accessible through danmaku.export.',
    Effect.read,
    ObjectSchema({
      'sessionId': _session,
      'positionMs': IntegerSchema(minimum: 0),
      'windowMs': IntegerSchema(minimum: 0, maximum: 60000),
      'startMs': IntegerSchema(minimum: 0),
      'endMs': IntegerSchema(minimum: 0),
      'limit': IntegerSchema(minimum: 1, maximum: 500),
      'cursor': IntegerSchema(minimum: 0),
      'expectedListVersion': IntegerSchema(minimum: 0)
    })
  ),
};

final class PlaybackInspection {
  PlaybackInspection(this.state);
  final VideoPlayerState state;
  JsonMap get snapshot => VideoPlayerStatePort(state).snapshot().toJson();
  void _session(JsonMap input) {
    if (input['sessionId'] != null &&
        input['sessionId'] != snapshot['sessionId']) {
      throw const Failure(FailureCode.conflict,
          'Playback session changed. Read playback.state.');
    }
  }

  void _internal() {
    if (snapshot['player'] != 'internal' || state.currentVideoPath == null) {
      throw const Failure(FailureCode.unavailable,
          'This operation requires an internal playback session.');
    }
  }

  Future<JsonMap> call(String operation, JsonMap input) async {
    if (operation != 'playback.wait') _session(input);
    if (operation == 'playback.wait') {
      final deadline = Stopwatch()..start();
      final timeout = input['timeoutMs'] as int? ?? 5000;
      while (true) {
        final value = snapshot;
        if (value['sessionId'] != input['sessionId']) {
          return {'outcome': 'session_changed', 'state': value};
        }
        final until = input['until'];
        final matched = switch (until) {
          'ready' => value['ready'] == true,
          'buffering' => value['buffering'] == true,
          'error' => value['error'] != null,
          'playing' => value['ready'] == true &&
              value['paused'] == false &&
              value['buffering'] == false,
          'paused' => value['paused'] == true,
          _ => false,
        };
        if (matched) return {'outcome': 'matched', 'state': value};
        if (value['error'] != null) return {'outcome': 'error', 'state': value};
        if (deadline.elapsedMilliseconds >= timeout) {
          return {'outcome': 'timeout', 'state': value};
        }
        await Future<void>.delayed(Duration(
            milliseconds:
                (timeout - deadline.elapsedMilliseconds).clamp(1, 50)));
      }
    }
    if (operation != 'playback.retry') _internal();
    switch (operation) {
      case 'playback.retry':
        final requested = state.lastPlaybackRequest;
        if (snapshot['player'] != 'internal' ||
            requested == null ||
            state.status == PlayerStatus.idle ||
            state.status == PlayerStatus.disposed) {
          throw const Failure(FailureCode.unavailable,
              'No active or failed internal playback request is available for retry.');
        }
        final path = requested.videoPath;
        final hadVideo = state.hasVideo;
        final position = state.position;
        final paused = state.isPaused;
        final history = await WatchHistoryManager.getHistoryItem(path);
        _session(input);
        final expectedRequestGeneration = state.playbackRequestGeneration + 1;
        await state.initializePlayer(path,
            historyItem: history,
            actualPlayUrl: requested.actualPlayUrl,
            playbackSession: requested.playbackSession,
            playbackDetailContext:
                requested.detailContext ?? state.playbackDetailContext,
            resetManualDanmakuOffset: false,
            episodeFileSelectionHandled: true,
            manualMatchHandled: true);
        if (state.lastPlaybackRequest?.videoPath != path ||
            state.playbackRequestGeneration != expectedRequestGeneration) {
          throw const Failure(
              FailureCode.conflict, 'Playback changed while retrying.');
        }
        if (state.player.isMediaReady) {
          state.seekTo(input['preservePosition'] == false
              ? Duration.zero
              : hadVideo
                  ? position
                  : Duration(milliseconds: history?.lastPosition ?? 0));
        }
        if (paused && state.player.isMediaReady) state.pause();
        return {'commandStatus': 'accepted', 'state': snapshot};
      case 'playback.chapters':
        return {
          'sessionId': snapshot['sessionId'],
          'items': [
            for (final c in state.chapters)
              {'title': c.title, 'startMs': c.startMs}
          ],
          'index': state.currentChapter,
          'skipSegments': [
            for (final s in state.detectedSkipSegments)
              {
                'kind': s.kind.name,
                'source': s.source.name,
                'startMs': s.start.inMilliseconds,
                'endMs': s.end.inMilliseconds,
                'evidenceCount': s.evidenceCount
              }
          ],
          'activeSkipKind': state.activeSkipSegment?.kind.name
        };
      case 'playback.navigate':
        String method;
        if (input['chapterIndex'] case final int index) {
          if (index >= state.chapters.length) {
            throw const Failure(
                FailureCode.invalidInput, 'Chapter index out of range.');
          }
          await state.seekToChapter(index);
          method = 'chapter';
        } else if (input['frameDelta'] case final int delta) {
          if (delta == 0) {
            throw const Failure(
                FailureCode.invalidInput, 'frameDelta must be -1 or +1.');
          }
          if (delta > 0) {
            state.stepForward();
          } else {
            state.stepBackward();
          }
          final kernel = state.player.getPlayerKernelName().toLowerCase();
          method = delta > 0 && kernel.contains('media')
              ? 'native_frame_step'
              : 'approximate_42ms_seek';
        } else {
          final active = state.activeSkipSegment;
          if (active == null ||
              input['skipKind'] != 'current' &&
                  input['skipKind'] != active.kind.name) {
            throw const Failure(FailureCode.unavailable,
                'Requested skip segment is not active at this position.');
          }
          await state.skipCurrentSegment();
          method = 'skip_segment';
        }
        return {
          'commandStatus': 'accepted',
          'method': method,
          'state': snapshot
        };
      case 'playback.playlist':
        final context = state.playbackDetailContext;
        if (context == null) {
          return {
            'supported': false,
            'source': null,
            'items': <JsonMap>[],
            'currentIndex': null,
            'unsupportedReason': 'no_playback_detail_context'
          };
        }
        final generation = state.playbackGeneration;
        final items = await state.readPlaybackPlaylist();
        if (generation != state.playbackGeneration) {
          throw const Failure(
              FailureCode.conflict, 'Playlist session changed.');
        }
        final key = MediaIdentityResolver.forPath(state.currentVideoPath!);
        return {
          'supported': true,
          'source': context.sourceKey,
          'items': [
            for (final e in items)
              {
                'id': e.id,
                'path': redactPrivateUrls(e.videoPath),
                'title': e.title,
                'episodeId': e.episodeId
              }
          ],
          'currentIndex': items.indexWhere(
              (e) => MediaIdentityResolver.forPath(e.videoPath) == key)
        };
      case 'subtitle.cues':
        return _cues(input);
      case 'danmaku.entries':
        return _danmaku(input);
      default:
        throw const Failure(
            FailureCode.invalidInput, 'Unknown playback operation.');
    }
  }

  Future<JsonMap> _cues(JsonMap input) async {
    final session = snapshot['sessionId'];
    final position =
        input['positionMs'] as int? ?? state.position.inMilliseconds;
    if (input['endMs'] != null &&
        input['startMs'] != null &&
        (input['endMs'] as int) < (input['startMs'] as int)) {
      throw const Failure(
          FailureCode.invalidInput, 'endMs must be >= startMs.');
    }
    final context = input['context'] as int? ?? 2;
    final all = <JsonMap>[];
    final unsupported = <JsonMap>[];
    for (final path in state.activeExternalSubtitlePaths) {
      final format = path.split('.').last.toLowerCase();
      if (format == 'idx' || format == 'sup') {
        unsupported.add({'path': path, 'reason': 'bitmap_requires_ocr'});
        continue;
      }
      final cached = state.getCachedSubtitle(path);
      final metadata = state.subtitleTrackInfo.values
          .where((t) => t['path'] == path && t['trackId'] != null)
          .firstOrNull;
      final cues = cached?.whereType<SubtitleEntry>().toList() ??
          await SubtitleParser.parseAssFile(path);
      final delay =
          ((state.subtitleDelaySeconds + state.pathSubtitleDelaySeconds(path)) *
                  1000)
              .round();
      final current = cues.indexWhere((c) =>
          c.startTimeMs + delay <= position && c.endTimeMs + delay >= position);
      final anchor = current >= 0
          ? current
          : cues.lastIndexWhere((c) => c.startTimeMs + delay <= position);
      for (var i = 0; i < cues.length; i++) {
        final c = cues[i],
            start = c.startTimeMs + delay,
            end = c.endTimeMs + delay;
        if (input['startMs'] != null || input['endMs'] != null) {
          if (end < (input['startMs'] as int? ?? 0) ||
              start > (input['endMs'] as int? ?? 2147483647)) {
            continue;
          }
        } else if (i < (anchor - context).clamp(0, cues.length) ||
            i > anchor + context) {
          continue;
        }
        all.add({
          'id': '$path:$i',
          'path': path,
          'startMs': start,
          'endMs': end,
          'text': c.content,
          'trackId': metadata?['trackId'],
          'language': metadata?['language'],
          'source': metadata?['source'],
          'current': start <= position && end >= position
        });
      }
    }
    if (state.player.activeSubtitleTracks.isNotEmpty &&
        state.activeExternalSubtitlePaths.isEmpty) {
      unsupported.add({'reason': 'embedded_text_not_extracted'});
    }
    if (session != snapshot['sessionId']) {
      throw const Failure(
          FailureCode.conflict, 'Playback session changed while reading cues.');
    }
    return _page(all, input, {
      'sessionId': session,
      'positionMs': position,
      'unsupported': unsupported
    });
  }

  JsonMap _danmaku(JsonMap input) {
    if (input['expectedListVersion'] != null &&
        input['expectedListVersion'] != state.danmakuListVersion) {
      throw const Failure(FailureCode.conflict,
          'Danmaku timeline changed; restart pagination.');
    }
    final position =
        input['positionMs'] as int? ?? state.position.inMilliseconds;
    final window = input['windowMs'] as int? ?? 5000;
    final start = input['startMs'] as int? ?? position - window,
        end = input['endMs'] as int? ?? position + window;
    if (end < start) {
      throw const Failure(
          FailureCode.invalidInput, 'endMs must be >= startMs.');
    }
    final offset =
        ((state.manualDanmakuOffset + state.autoDanmakuOffset) * 1000).round();
    final rows = <JsonMap>[];
    for (final e in state.getFilteredDanmakuList().asMap().entries) {
      final mapped = ((e.value['time'] as num) * 1000).round() - offset;
      if (mapped < start || mapped > end) continue;
      rows.add({
        'id': '${state.danmakuListVersion}:${e.key}',
        'mappedTimeMs': mapped,
        'text': e.value['content'],
        'trackId': e.value['nextTrackId'],
        'provenance': e.value['originSource'],
        'platform': e.value['source'],
        'sourceId': e.value['sourceId'],
        'foldMembers': e.value['displayMembers'],
        'sourceTimeMs': e.value['sourceTimeMs']
      });
    }
    return _page(rows, input, {
      'sessionId': snapshot['sessionId'],
      'listVersion': state.danmakuListVersion,
      'view': 'display_timeline',
      'positionMs': position
    });
  }

  JsonMap _page(List<JsonMap> rows, JsonMap input, JsonMap facts) {
    final cursor = input['cursor'] as int? ?? 0,
        limit = input['limit'] as int? ?? 100;
    final page = rows.skip(cursor).take(limit).toList();
    return {
      ...facts,
      'items': page,
      'nextCursor':
          cursor + page.length < rows.length ? cursor + page.length : null,
      'total': rows.length
    };
  }
}
