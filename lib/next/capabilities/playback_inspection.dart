import 'dart:async';
import 'package:nipa_harness/nipa_harness.dart';
import 'classic_action.dart';

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
  'playback.info': (
    'Read what the kernel playing now reports about the media, queried from the kernel at call time: kernel (id mdk/media_kit/video_player/erika, name, configured = the kernel setting), container (format, bitrate bit/s), video (codec, width, height, displayWidth/Height, pixelFormat, hwPixelFormat, fps = declared, measuredFps = output estimate, bitrate bit/s, colorMatrix, colorPrimaries, transfer), decoder (name, hardware, method = active hardware method or decoder, requested = hwdec option or ordered decoder list), frames (dropped by output, decoderDropped, mistimed, delayed, decoded, rendered; counters since the file opened), audio (codec, decoder, sampleRate, channels, channelLayout, sampleFormat, bitrate), output (videoOutput, gpuApi, gpuContext, rate, avsyncSeconds), cache (aheadSeconds, pausedForCache, bufferingPercent) and kernelDetails, the kernel report as given. A value the kernel does not report is null. Includes sessionId, hasVideo and the danmaku renderer.',
    Effect.read,
    ObjectSchema({})
  ),
  'playback.failures': (
    'Read playback failures recorded in this process while Next is on, newest first: failureId, at, sessionId, path, kernel, stage (file_check, stream_session, remote_path, media_open, media_ready_timeout, initialize, invalid_media, web_format, or null), category (file_not_found, permission_denied, unsupported_format, network, unauthorized, source_failed, timeout, unknown), kernelRetryable, messages (player, kernel, media: raw text, redacted), file (exists, readable, osError for a local file, else null). category comes from the local file state, then the kernel text, then the player text, then the stage. Each failure is also the playback.failed event, which persists across restarts. limit defaults to 20.',
    Effect.read,
    ObjectSchema({'limit': IntegerSchema(minimum: 1, maximum: 50)})
  ),
  'playback.cancel_auto_next': (
    'Cancel the running countdown to the next episode, as the countdown bar does. Returns cancelled=false when no countdown runs; state.autoNext shows the countdown before and after.',
    Effect.write,
    ObjectSchema({})
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
