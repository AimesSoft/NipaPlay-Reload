import 'package:nipa_harness/nipa_harness.dart';
import 'playback_inspection.dart';

/// The host supplies Classic operations; the capability only describes inputs.
abstract interface class PlaybackControlsPort {
  Future<JsonMap> tracks(JsonMap input);
  Future<JsonMap> selectTrack(JsonMap input);
  Future<JsonMap> loadSubtitle(JsonMap input);
  Future<JsonMap> removeSubtitle(JsonMap input);
  Future<JsonMap> streamOptions(JsonMap input);
  Future<JsonMap> selectStream(JsonMap input);
  Future<JsonMap> external(JsonMap input);
  Future<JsonMap> capture(JsonMap input);
  Future<JsonMap> close(JsonMap input);
  Future<JsonMap> authorizeDirectory(JsonMap input);
}

final class PlaybackControlsCapability implements Capability {
  PlaybackControlsCapability(PlaybackControlsPort port)
      : actions = [
          _Operation(
              'playback.tracks',
              'List player tracks',
              'Lists embedded, mounted external and server audio/subtitle tracks. '
                  'Also lists Next managed danmaku tracks with binding ID and count. Audio/subtitle indexes are scoped to kind and origin; use these values in select_track.',
              Effect.read,
              const ObjectSchema({}),
              port.tracks),
          _Operation(
              'playback.select_track',
              'Select a player track',
              'Select an embedded or server audio/subtitle track, or disable subtitles '
                  'with index -1. Server selection reloads the current stream.',
              Effect.write,
              const ObjectSchema({
                'kind': StringSchema(values: ['audio', 'subtitle']),
                'origin': StringSchema(values: ['embedded', 'server']),
                'index': IntegerSchema(minimum: -1),
              }, required: [
                'kind',
                'origin',
                'index'
              ]),
              port.selectTrack),
          _Operation(
              'playback.load_subtitle',
              'Load an external subtitle',
              'Mount a local subtitle path or HTTP(S) subtitle URL using Classic subtitle '
                  'cache and stack. Returns its local path; activate defaults to true.',
              Effect.write,
              const ObjectSchema({
                'path': StringSchema(minLength: 1),
                'activate': BooleanSchema(),
              }, required: [
                'path'
              ]),
              port.loadSubtitle),
          _Operation(
              'playback.remove_subtitle',
              'Unmount an external subtitle',
              'Unmount a subtitle by its local cache path and update the Classic subtitle '
                  'list. The subtitle file is retained.',
              Effect.write,
              const ObjectSchema({'path': StringSchema(minLength: 1)},
                  required: ['path']),
              port.removeSubtitle),
          _Operation(
              'playback.stream_options',
              'Read stream versions and quality',
              'Reads current Jellyfin/Emby media versions, server tracks, quality presets '
                  'and transcoding settings without exposing authenticated stream URLs.',
              Effect.read,
              const ObjectSchema({}),
              port.streamOptions),
          _Operation(
              'playback.select_stream',
              'Apply stream choices',
              'Applies version, quality, transcoding and server audio/subtitle burn-in '
                  'through Classic stream reload. Quality/transcode settings use the same '
                  'saved defaults as Classic. Omitted fields retain current selections; '
                  'subtitleIndex -1 disables server subtitle selection.',
              Effect.write,
              const ObjectSchema({
                'mediaSourceId': StringSchema(minLength: 1),
                'quality': StringSchema(values: [
                  'auto',
                  'original',
                  'bandwidth40m',
                  'bandwidth20m',
                  'bandwidth10m',
                  'bandwidth5m',
                  'bandwidth2m',
                  'bandwidth1m'
                ]),
                'transcode': BooleanSchema(),
                'audioIndex': IntegerSchema(minimum: 0),
                'subtitleIndex': IntegerSchema(minimum: -1),
                'burnIn': BooleanSchema(),
              }),
              port.selectStream),
          _Operation(
              'playback.external',
              'Control an external player session',
              'Read actual session telemetry, pause, resume, seek or close via Classic '
                  'external console. Unknown progress is null. Unsupported controls fail '
                  'explicitly; commands return observed state which may lag IPC delivery.',
              Effect.write,
              const ObjectSchema({
                'command': StringSchema(
                    values: ['state', 'pause', 'resume', 'seek', 'close']),
                'positionMs': IntegerSchema(minimum: 0),
              }, required: [
                'command'
              ]),
              port.external),
          _Operation(
              'playback.external_state',
              'Read external playback telemetry',
              'Read actual external session progress. Unknown/unavailable telemetry is '
                  'null; mpv is queried through its IPC endpoint.',
              Effect.read,
              const ObjectSchema({}),
              (_) => port.external({'command': 'state'})),
          _Operation(
              'playback.capture',
              'Save a screenshot or GIF',
              'Generate and save media from the current player session. '
                  'Screenshots use the shared save directory unless outputPath is specified. '
                  'includeDanmaku defaults to the screenshot setting. Next captures the '
                  'displayed scene or combines a kernel picture with its displayed overlays. '
                  'Native overlays outside the Flutter scene depend on the driver snapshot. Screenshot '
                  'results report danmakuRequested, danmakuIncluded and danmakuReason. '
                  'danmakuIncluded describes inclusion of the displayed layer, not proof '
                  'of visible comments at this position. '
                  'GIF uses an independent Erika decoder without display overlays and requires '
                  'outputPath, startMs and endMs; maximum duration is 30 seconds. '
                  'Existing output files are never overwritten.',
              Effect.write,
              const ObjectSchema({
                'kind': StringSchema(values: ['screenshot', 'gif']),
                'outputPath': StringSchema(minLength: 1),
                'includeDanmaku': BooleanSchema(),
                'includeSubtitles': BooleanSchema(),
                'startMs': IntegerSchema(minimum: 0),
                'endMs': IntegerSchema(minimum: 1),
                'fps': IntegerSchema(minimum: 1, maximum: 30),
                'width': IntegerSchema(minimum: 2, maximum: 4096),
                'height': IntegerSchema(minimum: 2, maximum: 4096),
                'quality': StringSchema(values: ['normal', 'high']),
              }, required: [
                'kind'
              ]),
              port.capture,
              output: const ObjectSchema({
                'path': StringSchema(),
                'bytes': IntegerSchema(minimum: 0),
                'kind': StringSchema(values: ['screenshot', 'gif']),
                'danmakuRequested': BooleanSchema(
                    description:
                        'Screenshot request after applying the default setting.'),
                'danmakuIncluded': BooleanSchema(
                    description: 'Whether the displayed danmaku layer is included. '
                        'It may be empty; this is not on-screen comment telemetry.'),
                'danmakuReason': StringSchema(
                    nullable: true,
                    description:
                        'Why the screenshot excludes danmaku; null when included.'),
              }, required: [
                'path', 'bytes', 'kind'
              ], additionalProperties: true)),
          _Operation(
              'playback.close',
              'Close current playback',
              'Closes an active external session, otherwise resets the Classic internal '
                  'player and saves progress through its normal exit path.',
              Effect.write,
              const ObjectSchema({}),
              port.close),
          _Operation(
              'playback.authorize_directory',
              'Open directory permission picker',
              'Opens the Classic directory picker and creates its platform access bookmark. '
                  'The user selects the directory; cancellation returns path null.',
              Effect.write,
              const ObjectSchema(
                  {'initialDirectory': StringSchema(minLength: 1)}),
              port.authorizeDirectory),
          if (port is PlaybackInspectionPort) ...PlaybackInspectionCapability(port as PlaybackInspectionPort).actions,
        ];

  @override
  final List<Action> actions;
}

final class PlaybackControlData implements JsonEncodable {
  const PlaybackControlData(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Operation
    extends Action<PlaybackControlData, PlaybackControlData> {
  _Operation(String id, String title, String description, Effect effect,
      ObjectSchema input, this._run,
      {ObjectSchema output = const ObjectSchema({}, additionalProperties: true)})
      : spec = ActionSpec(
            id: id,
            title: title,
            description: description,
            effect: effect,
            input: input,
            output: output);
  final Future<JsonMap> Function(JsonMap) _run;
  @override
  final ActionSpec spec;
  @override
  PlaybackControlData decodeInput(JsonMap json) => PlaybackControlData(json);
  @override
  Future<Outcome<PlaybackControlData>> run(
          PlaybackControlData input, Invocation invocation) async =>
      Completed(PlaybackControlData(await _run(input.value)));
}
