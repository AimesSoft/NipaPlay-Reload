import 'package:nipa_harness/nipa_harness.dart';

// Kept byte-for-byte equivalent in input/output schemas to the P1 catalogue.
const _output = ObjectSchema({}, additionalProperties: true);
const _unit = NumberSchema(minimum: 0, maximum: 1);
const featureOperationSpecs = <String, ActionSpec>{
  'playback.external_player_path': ActionSpec(
      id: 'playback.external_player_path',
      title: 'Choose or detect an external player',
      description:
          'command:detect uses NipaPlay installed-mpv detection; command:choose opens the NipaPlay executable picker for the user. '
          'On success saves externalPath and detected externalType through settings provenance. Does not enable external playback. '
          'Cancellation or no installed mpv returns path:null. To use a known installed path directly, set player.externalPath and player.externalType.',
      effect: Effect.write,
      input: ObjectSchema({
        'command': StringSchema(values: ['detect', 'choose']),
        'reason': StringSchema()
      }, required: [
        'command'
      ]),
      output: _output),
  'danmaku.send': ActionSpec(
      id: 'danmaku.send',
      title: 'Send a danmaku comment',
      description:
          'Publish one comment to the currently identified internal playing/paused episode '
          'through NipaPlay DanmakuMatchingService, then echo it in a new NipaPlay local track. '
          'text is trimmed and must contain 1–100 characters; mode defaults to scroll (scroll/top/bottom), '
          'color defaults to #FFFFFF and accepts #RRGGBB. Position is the current playback position in seconds. '
          'Requires Dandanplay login completed by the user; use accounts.login to initiate it. '
          'This publishes online; do not retry a failed/lost response blindly.',
      effect: Effect.write,
      input: ObjectSchema({
        'text': StringSchema(
            minLength: 1, description: '1–100 characters after trimming.'),
        'mode': StringSchema(values: ['scroll', 'top', 'bottom']),
        'color': StringSchema(description: 'RGB hex color, #RRGGBB.')
      }, required: [
        'text'
      ]),
      output: _output),
  'playback.levels': ActionSpec(
      id: 'playback.levels',
      title: 'Read or set playback levels',
      description:
          'Read ordinary internal-player volume and mobile brightness, or set either/both in one call. '
          'Values are 0–1; omitted values are unchanged. Brightness is unavailable on desktop and returned null. '
          'On mobile volume controls system volume. Changes use settings provenance; reason is optional. '
          'For external-player volume use that player UI; these levels belong to NipaPlay internal playback.',
      effect: Effect.write,
      input: ObjectSchema(
          {'volume': _unit, 'brightness': _unit, 'reason': StringSchema()}),
      output: _output),
  'window.state': ActionSpec(
      id: 'window.state',
      title: 'Read window state',
      description:
          'Read actual main/detached player and external console/list window state of this connected instance.',
      effect: Effect.read,
      input: ObjectSchema({}),
      output: _output),
  'window.control': ActionSpec(
      id: 'window.control',
      title: 'Control a window',
      description:
          'Control this connected instance. target defaults to main; player means the detached player. '
          'fullscreen/always_on_top/pip/detached require enabled:true/false. pip/detached require target:player; '
          'enabling detaches the same NipaPlay player without restarting playback. Disabling pip leaves it detached; '
          'disabling detached returns it to main. fit_video requires main/player and an internal video. '
          'show focuses/restores main/player or creates external_controls/external_list for an active external session. '
          'close main hides it (the process and endpoint remain alive); close player returns playback to main; '
          'close external_controls also closes its list, retaining external playback. tray requires main and uses NipaPlay tray/taskbar handling. '
          'Use app.quit to end the instance. No confirmation parameters.',
      effect: Effect.write,
      input: ObjectSchema({
        'target': StringSchema(
            values: ['main', 'player', 'external_controls', 'external_list']),
        'command': StringSchema(values: [
          'fullscreen',
          'pip',
          'detached',
          'fit_video',
          'always_on_top',
          'show',
          'minimize',
          'maximize',
          'restore',
          'close',
          'tray'
        ]),
        'enabled': BooleanSchema()
      }, required: [
        'command'
      ]),
      output: _output),
  'app.quit': ActionSpec(
      id: 'app.quit',
      title: 'Quit the connected application',
      description:
          'Schedule NipaPlay application shutdown in one second after returning a receipt. '
          'This ends the exact NipaPlay instance serving this Agent connection, including its endpoint; subsequent calls fail. '
          'Playback progress and NipaPlay exit cleanup run normally. No user confirmation is needed. '
          'The returned scheduled receipt is journaled before shutdown, not proof of process exit.',
      effect: Effect.write,
      input: ObjectSchema({}),
      output: _output),
  'playback.external.danmaku_state': ActionSpec(
      id: 'playback.external.danmaku_state',
      title: 'Read external session danmaku',
      description:
          'Read external session style, offset, block rules and paginated comments including blocked state. '
          'offset defaults to 0; limit defaults to 100. senderId is for NipaPlay userId rules.',
      effect: Effect.read,
      input: ObjectSchema({
        'offset': IntegerSchema(minimum: 0),
        'limit': IntegerSchema(minimum: 1, maximum: 1000)
      }),
      output: _output),
  'playback.external.danmaku': ActionSpec(
      id: 'playback.external.danmaku',
      title: 'Set external session danmaku',
      description:
          'Patch an active NipaPlay external console session. style fields are opacity 0–1, fontSize 12–60, '
          'outlineWidth 0–5 (0 disables; positive values below 0.5 normalize to 0.5), stacking bool. '
          'offsetSeconds is any finite number; positive delays comments. '
          'rules adds/removes multiple keyword/regex/userId rules; matching and deduplication are case insensitive. '
          'Invalid regex/empty rule rejects the call before changing the session. '
          'sync:from_user first reapplies current user style, then this patch. sync:to_user writes the resulting '
          'style/offset back through NipaPlay setters with provenance. Otherwise changes affect only this session. '
          'ASS reload is queued by Classic; read danmaku_state or capture the external player to observe it.',
      effect: Effect.write,
      input: ObjectSchema({
        'style': ObjectSchema({
          'opacity': _unit,
          'fontSize': NumberSchema(minimum: 12, maximum: 60),
          'outlineWidth': NumberSchema(minimum: 0, maximum: 5),
          'stacking': BooleanSchema()
        }),
        'offsetSeconds': NumberSchema(),
        'sync': StringSchema(values: ['from_user', 'to_user']),
        'rules': ArraySchema(ObjectSchema({
          'operation': StringSchema(values: ['add', 'remove']),
          'type': StringSchema(values: ['keyword', 'regex', 'userId']),
          'value': StringSchema(minLength: 1)
        }, required: [
          'operation',
          'type',
          'value'
        ])),
        'reason': StringSchema()
      }),
      output: _output),
};
