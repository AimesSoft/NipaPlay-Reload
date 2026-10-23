import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart' hide Action;
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/danmaku/blocked_item.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/danmaku_matching_service.dart';
import 'package:nipaplay/services/desktop_exit_handler.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/services/external_player_console_window_service.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/external_player_utils.dart';
import 'package:nipaplay/utils/mpv_utils.dart';
import 'package:nipaplay/services/danmaku/danmaku_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:window_manager/window_manager.dart';

import '../../settings/registry.dart';
import '../../capabilities/classic_action.dart';
import '../danmaku/send.dart';
import '../ports/session_playback.dart';
import '../ports/session_ports.dart' show notInPlaybackLayer;
export '../../capabilities/local_operation_titles.dart';

const _output = ObjectSchema({}, additionalProperties: true);
const _unit = NumberSchema(minimum: 0, maximum: 1);

final class LocalPlaybackOperations implements Capability {
  LocalPlaybackOperations(this.player, this.settings, this.context,
      {this.session});
  final VideoPlayerState player;

  /// Next's own playback layer, when it plays instead of Classic's player:
  /// the levels and full screen are its; what it does not do yet is
  /// unavailable.
  final SessionPlayback? session;
  final SettingsRegistry settings;
  final BuildContext Function() context;
  final _desktop = DesktopPlayerWindowService.instance;
  final _consoleWindows = ExternalPlayerConsoleWindowService.instance;
  bool _quitScheduled = false;

  JsonMap _levels() {
    if (session case final session?) {
      return {
        'volume': session.volume,
        'brightness': null,
        'brightnessSupported': false,
        'volumeTarget': 'internal_player',
        'playerVolume': session.volume,
      };
    }
    return {
      'volume': player.currentSystemVolume,
      'brightness':
          globals.isMobilePlatform ? player.currentScreenBrightness : null,
      'brightnessSupported': globals.isMobilePlatform,
      'volumeTarget': globals.isMobilePlatform ? 'system' : 'internal_player',
      'playerVolume': player.player.volume,
    };
  }

  void _requireExternal() {
    if (!ExternalPlayerConsoleService.hasActiveSession) {
      throw const Failure(
          FailureCode.unavailable, 'No external player session is active.');
    }
  }

  JsonMap _externalState({int offset = 0, int limit = 0}) {
    final style = ExternalPlayerConsoleService.getDanmakuStyleSnapshot();
    final items = ExternalPlayerConsoleService.displayDanmakuList;
    return {
      'active': ExternalPlayerConsoleService.hasActiveSession,
      'style': {
        'opacity': style.opacity,
        'fontSize': style.danmakuFontSize,
        'outlineWidth': style.outlineWidth,
        'stacking': style.danmakuAllowStacking
      },
      'offsetSeconds': style.danmakuOffset,
      'rules': [
        for (final rule in ExternalPlayerConsoleService.blockedItems)
          {'type': rule.type.name, 'value': rule.value}
      ],
      'total': items.length,
      'items': [
        for (final item in items.skip(offset).take(limit))
          {
            'index': item.index,
            'text': item.item.content,
            'timeMs': item.item.time.inMilliseconds,
            'startTimeMs': item.startTime.inMilliseconds,
            'blocked': item.isBlocked,
            'active': item.isActive,
            'mode': item.item.mode.typeName,
            'color': '#${item.item.colorRgb.toRadixString(16).padLeft(6, '0')}',
            'senderId': item.item.senderId
          }
      ],
      'nextOffset':
          limit > 0 && offset + limit < items.length ? offset + limit : null,
      'refresh': 'queued',
    };
  }

  WindowController? _window(String target) => switch (target) {
        'player' => _desktop.activeWindow,
        'external_controls' => _consoleWindows.controlsWindow,
        'external_list' => _consoleWindows.danmakuListWindow,
        _ => null,
      };

  Future<JsonMap> _windowState() async => {
        'main': {
          'fullscreen': await windowManager.isFullScreen(),
          'alwaysOnTop': await windowManager.isAlwaysOnTop(),
          'minimized': await windowManager.isMinimized(),
          'maximized': await windowManager.isMaximized(),
          'visible': await windowManager.isVisible(),
          'size': {
            'width': (await windowManager.getSize()).width,
            'height': (await windowManager.getSize()).height
          }
        },
        'detached': _desktop.isPlayerDetached,
        'pictureInPicture': _desktop.isPictureInPicture,
        for (final target in ['player', 'external_controls', 'external_list'])
          target: {
            'open': _window(target) != null && !_window(target)!.isClosed,
            'fullscreen': _window(target)?.isFullscreen ?? false,
            'alwaysOnTop': _window(target)?.isAlwaysOnTop ?? false
          },
      };

  Future<JsonMap> _control(JsonMap input, Invocation invocation) async {
    if (!globals.isDesktop) {
      throw const Failure(FailureCode.unavailable,
          'Window control requires a desktop platform.');
    }
    final command = input['command'] as String;
    final target = input['target'] as String? ?? 'main';
    final enabled = input['enabled'] as bool?;
    if (['fullscreen', 'pip', 'detached', 'always_on_top'].contains(command) &&
        enabled == null) {
      throw const Failure(
          FailureCode.invalidInput, 'This command requires enabled.');
    }
    if (session != null && ['pip', 'detached', 'fit_video'].contains(command)) {
      notInPlaybackLayer('window',
          'Next\'s playback layer does not move the video to its own window or fit the window to it yet.');
    }
    if (['pip', 'detached', 'fit_video'].contains(command) &&
        !player.hasVideo) {
      throw const Failure(
          FailureCode.unavailable, 'An internal video is required.');
    }
    if (['pip', 'detached'].contains(command) && target != 'player' ||
        command == 'tray' && target != 'main' ||
        command == 'fit_video' && target != 'main' && target != 'player') {
      throw const Failure(FailureCode.invalidInput,
          'Use player for pip/detached; main for tray; main/player for fit_video.');
    }
    if (command == 'pip' || command == 'detached') {
      if (!DesktopPlayerWindowService.isFeatureEnabled) {
        throw const Failure(FailureCode.unavailable,
            'Independent player windows are unavailable on this platform.');
      }
      if (enabled!) {
        final opened = await _desktop.detachPlayer(context(), player);
        if (!opened) {
          throw const Failure(
              FailureCode.unavailable, 'Could not detach the player.');
        }
        if (command == 'pip') await _desktop.enterPictureInPicture();
      } else if (command == 'pip') {
        await _desktop.exitPictureInPicture();
      } else {
        await _desktop.returnPlayerToMain();
      }
    } else if (target != 'main') {
      if (command == 'show' && target != 'player') {
        _requireExternal();
        if (target == 'external_controls') {
          await _consoleWindows.showControlsWindow();
        } else {
          await _consoleWindows.showDanmakuListWindow();
        }
      } else {
        final window = _window(target);
        if (window == null || window.isClosed) {
          throw const Failure(
              FailureCode.unavailable, 'The selected window is not open.');
        }
        switch (command) {
          case 'fullscreen':
            if (Platform.isMacOS) {
              await const MethodChannel('nipaplay/desktop_multi_window_host')
                  .invokeMethod<void>('setAgentFullscreen', {
                'viewId': window.flutterView.viewId,
                'enabled': enabled!,
              });
            } else {
              await window.setFullscreen(enabled!);
            }
          case 'always_on_top':
            await window.setAlwaysOnTop(enabled!);
          case 'show':
            await window.show();
          case 'minimize':
            await window.setMinimized(true);
          case 'maximize':
            await window.setMaximized(true);
          case 'restore':
            await window.setMinimized(false);
            await window.setMaximized(false);
          case 'fit_video':
            await _desktop.resizeDetachedWindowToVideo();
          case 'close':
            if (target == 'player') {
              await _desktop.returnPlayerToMain();
            } else if (target == 'external_controls') {
              await _consoleWindows.closeControlsWindow();
            } else {
              await _consoleWindows.closeDanmakuListWindow();
            }
          default:
            throw const Failure(
                FailureCode.invalidInput, 'Unsupported window command.');
        }
      }
    } else {
      switch (command) {
        case 'fullscreen':
          if (session case final session?) {
            await session.setFullscreen(enabled!);
          } else if (await windowManager.isFullScreen() != enabled) {
            await player.toggleFullscreen();
          }
        case 'always_on_top':
          await windowManager.setAlwaysOnTop(enabled!);
        case 'show':
          await DesktopExitHandler.instance.showMainWindow();
        case 'minimize':
          await windowManager.minimize();
        case 'maximize':
          await windowManager.maximize();
        case 'restore':
          await windowManager.restore();
          await windowManager.unmaximize();
        case 'fit_video':
          await player.resizeWindowToVideoSize();
        case 'tray':
          await DesktopExitHandler.instance.minimizeToTray();
        case 'close':
          await windowManager.hide();
        default:
          throw const Failure(
              FailureCode.invalidInput, 'Unsupported window command.');
      }
    }
    return _windowState();
  }

  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'playback.external_player_path',
                title: 'Choose or detect an external player',
                description:
                    'command:detect uses Classic installed-mpv detection; command:choose opens the Classic executable picker for the user. '
                    'On success saves externalPath and detected externalType through settings provenance. Does not enable external playback. '
                    'Cancellation or no installed mpv returns path:null. To use a known installed path directly, set player.externalPath and player.externalType.',
                effect: Effect.write,
                input: ObjectSchema({
                  'command': StringSchema(values: ['detect', 'choose']),
                  'reason': StringSchema()
                }, required: [
                  'command'
                ]),
                output: _output), (input, invocation) async {
          if (!globals.isDesktop) {
            throw const Failure(
                FailureCode.unavailable, 'External players require desktop.');
          }
          final path = input['command'] == 'detect'
              ? await detectInstalledMpv()
              : await FilePickerService().pickExternalPlayerExecutable();
          if (path == null) return {'path': null};
          final type = detectExternalPlayerType(path).name;
          await settings.set('player.externalPath', path, invocation,
              reason: input['reason'] as String?);
          await settings.set('player.externalType', type, invocation,
              reason: input['reason'] as String?);
          return {'path': path, 'type': type};
        }),
        ClassicAction(
            const ActionSpec(
                id: 'danmaku.send',
                title: 'Send a danmaku comment',
                description:
                    'Publish one comment to the currently identified internal playing/paused episode '
                    'through Classic DanmakuMatchingService, then echo it in a new Classic local track. '
                    'text is trimmed and must contain 1–100 characters; mode defaults to scroll (scroll/top/bottom), '
                    'color defaults to #FFFFFF and accepts #RRGGBB. Position is the current playback position in seconds. '
                    'Requires Dandanplay login completed by the user; use accounts.login to initiate it. '
                    'This publishes online; do not retry a failed/lost response blindly.',
                effect: Effect.write,
                input: ObjectSchema({
                  'text': StringSchema(
                      minLength: 1,
                      description: '1–100 characters after trimming.'),
                  'mode': StringSchema(values: ['scroll', 'top', 'bottom']),
                  'color': StringSchema(description: 'RGB hex color, #RRGGBB.')
                }, required: [
                  'text'
                ]),
                output: _output), (input, _) async {
          final text = (input['text'] as String).trim();
          if (text.isEmpty) {
            throw const Failure(
                FailureCode.invalidInput, 'Comment text cannot be empty.');
          }
          if (text.characters.length > 100) {
            throw const Failure(FailureCode.invalidInput,
                'Comment text is limited to 100 characters.');
          }
          final mode = input['mode'] as String? ?? 'scroll';
          final color = input['color'] as String? ?? '#FFFFFF';
          if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
            throw const Failure(
                FailureCode.invalidInput, 'Use an RGB hex color: #RRGGBB.');
          }
          if (session != null) {
            return sendSessionDanmaku(session!,
                text: text, mode: mode, color: color);
          }
          if (!player.hasVideo ||
              player.episodeId == null ||
              ExternalPlayerConsoleService.hasActiveSession) {
            throw const Failure(FailureCode.unavailable,
                'An identified internal video is required.');
          }
          if (!DandanplayService.isLoggedIn) {
            throw const Failure(FailureCode.unavailable,
                'Complete Dandanplay login through accounts.login first.');
          }
          final time = player.position.inSeconds.toDouble();
          final episodeId = player.episodeId!;
          final path = player.currentVideoPath;
          final result = await DanmakuMatchingService.instance.sendDanmaku(
              episodeId: episodeId,
              time: time,
              mode: switch (mode) { 'top' => 5, 'bottom' => 4, _ => 1 },
              color: int.parse(color.substring(1), radix: 16),
              comment: text);
          if (result['success'] != true || result['danmaku'] is! Map) {
            throw const Failure(FailureCode.unavailable,
                'Classic did not acknowledge the comment.');
          }
          final echo =
              player.episodeId == episodeId && player.currentVideoPath == path;
          if (echo) {
            player.addDanmakuToNewTrack(
                Map<String, dynamic>.from(result['danmaku'] as Map));
          }
          return {
            'sent': true,
            'localEcho': echo,
            'episodeId': episodeId,
            'timeSeconds': time,
            'mode': mode,
            'color': color
          };
        }),
        ClassicAction(
            const ActionSpec(
                id: 'playback.levels',
                title: 'Read or set playback levels',
                description:
                    'Read ordinary internal-player volume and mobile brightness, or set either/both in one call. '
                    'Values are 0–1; omitted values are unchanged. Brightness is unavailable on desktop and returned null. '
                    'On mobile volume controls system volume. Changes use settings provenance; reason is optional. '
                    'For external-player volume use that player UI; these levels belong to Classic internal playback.',
                effect: Effect.write,
                input: ObjectSchema({
                  'volume': _unit,
                  'brightness': _unit,
                  'reason': StringSchema()
                }),
                output: _output), (input, invocation) async {
          if (input.containsKey('brightness') && !globals.isMobilePlatform) {
            throw const Failure(FailureCode.unavailable,
                'Playback brightness requires a mobile platform.');
          }
          for (final kind in ['volume', 'brightness']) {
            if (input.containsKey(kind)) {
              await settings.set('player.$kind', input[kind], invocation,
                  reason: input['reason'] as String?);
            }
          }
          return _levels();
        }),
        ClassicAction(
            const ActionSpec(
                id: 'window.state',
                title: 'Read window state',
                description:
                    'Read actual main/detached player and external console/list window state of this connected instance.',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: _output), (_, __) async {
          if (!globals.isDesktop) {
            throw const Failure(
                FailureCode.unavailable, 'Desktop windows are unavailable.');
          }
          return _windowState();
        }),
        ClassicAction(
            const ActionSpec(
                id: 'window.control',
                title: 'Control a window',
                description:
                    'Control this connected instance. target defaults to main; player means the detached player. '
                    'fullscreen/always_on_top/pip/detached require enabled:true/false. pip/detached require target:player; '
                    'enabling detaches the same Classic player without restarting playback. Disabling pip leaves it detached; '
                    'disabling detached returns it to main. fit_video requires main/player and an internal video. '
                    'show focuses/restores main/player or creates external_controls/external_list for an active external session. '
                    'close main hides it (the process and endpoint remain alive); close player returns playback to main; '
                    'close external_controls also closes its list, retaining external playback. tray requires main and uses Classic tray/taskbar handling. '
                    'Use app.quit to end the instance. No confirmation parameters.',
                effect: Effect.write,
                input: ObjectSchema({
                  'target': StringSchema(values: [
                    'main',
                    'player',
                    'external_controls',
                    'external_list'
                  ]),
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
            _control),
        ClassicAction(
            const ActionSpec(
                id: 'app.quit',
                title: 'Quit the connected application',
                description:
                    'Schedule Classic application shutdown in one second after returning a receipt. '
                    'This ends the exact NipaPlay instance serving this Agent connection, including its endpoint; subsequent calls fail. '
                    'Playback progress and Classic exit cleanup run normally. No user confirmation is needed. '
                    'The returned scheduled receipt is journaled before shutdown, not proof of process exit.',
                effect: Effect.write,
                input: ObjectSchema({}),
                output: _output), (_, __) async {
          if (!globals.isDesktop) {
            throw const Failure(FailureCode.unavailable,
                'Application shutdown requires desktop.');
          }
          await settings.drain();
          if (!_quitScheduled) {
            _quitScheduled = true;
            Timer(const Duration(seconds: 1),
                () => unawaited(DesktopExitHandler.instance.quit()));
          }
          return {'scheduled': true, 'processId': pid, 'delayMs': 1000};
        }),
        ClassicAction(
            const ActionSpec(
                id: 'playback.external.danmaku_state',
                title: 'Read external session danmaku',
                description:
                    'Read external session style, offset, block rules and paginated comments including blocked state. '
                    'offset defaults to 0; limit defaults to 100. senderId is for Classic userId rules.',
                effect: Effect.read,
                input: ObjectSchema({
                  'offset': IntegerSchema(minimum: 0),
                  'limit': IntegerSchema(minimum: 1, maximum: 1000)
                }),
                output: _output), (input, _) async {
          _requireExternal();
          return _externalState(
              offset: (input['offset'] as num?)?.toInt() ?? 0,
              limit: (input['limit'] as num?)?.toInt() ?? 100);
        }),
        ClassicAction(
            const ActionSpec(
                id: 'playback.external.danmaku',
                title: 'Set external session danmaku',
                description:
                    'Patch an active Classic external console session. style fields are opacity 0–1, fontSize 12–60, '
                    'outlineWidth 0–5 (0 disables; positive values below 0.5 normalize to 0.5), stacking bool. '
                    'offsetSeconds is any finite number; positive delays comments. '
                    'rules adds/removes multiple keyword/regex/userId rules; matching and deduplication are case insensitive. '
                    'Invalid regex/empty rule rejects the call before changing the session. '
                    'sync:from_user first reapplies current user style, then this patch. sync:to_user writes the resulting '
                    'style/offset back through Classic setters with provenance. Otherwise changes affect only this session. '
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
                    'type':
                        StringSchema(values: ['keyword', 'regex', 'userId']),
                    'value': StringSchema(minLength: 1)
                  }, required: [
                    'operation',
                    'type',
                    'value'
                  ])),
                  'reason': StringSchema()
                }),
                output: _output), (input, invocation) async {
          _requireExternal();
          final rules = (input['rules'] as List? ?? []).cast<JsonMap>();
          final patch = input['style'] as JsonMap? ?? {};
          for (final value in [
            ...patch.values.whereType<num>(),
            if (input['offsetSeconds'] != null) input['offsetSeconds'] as num
          ]) {
            if (!value.isFinite) {
              throw const Failure(FailureCode.invalidInput,
                  'Danmaku style and offset numbers must be finite.');
            }
          }
          for (final rule in rules) {
            final value = (rule['value'] as String).trim();
            if (value.isEmpty) {
              throw const Failure(
                  FailureCode.invalidInput, 'A block rule cannot be empty.');
            }
            if (rule['type'] == 'regex') {
              try {
                RegExp(value, caseSensitive: false);
              } on FormatException {
                throw const Failure(
                    FailureCode.invalidInput, 'Invalid block-rule regex.');
              }
            }
          }
          if (input['sync'] == 'from_user') {
            ExternalPlayerConsoleService.applyDanmakuStyle(
                DanmakuService.getCurrentDanmakuStyle());
          }
          final style = ExternalPlayerConsoleService.getDanmakuStyleSnapshot()
              .copyWith(
                  opacity: (patch['opacity'] as num?)?.toDouble(),
                  danmakuFontSize: (patch['fontSize'] as num?)?.toDouble(),
                  outlineWidth: (patch['outlineWidth'] as num?)?.toDouble(),
                  danmakuAllowStacking: patch['stacking'] as bool?,
                  danmakuOffset: (input['offsetSeconds'] as num?)?.toDouble());
          ExternalPlayerConsoleService.applyDanmakuStyle(style);
          for (final rule in rules) {
            final type = BlockedItemType.values.byName(rule['type'] as String);
            final value = (rule['value'] as String).trim();
            if (rule['operation'] == 'add') {
              ExternalPlayerConsoleService.addBlockedItem(value, type);
            } else {
              for (final item in ExternalPlayerConsoleService.blockedItems
                  .where((item) =>
                      item.type == type &&
                      item.value.toLowerCase() == value.toLowerCase())
                  .toList()) {
                ExternalPlayerConsoleService.removeBlockedItem(item);
              }
            }
          }
          if (input['sync'] == 'to_user') {
            await runZoned(() async {
              await player.setDanmakuOpacity(style.opacity);
              await player.setDanmakuFontSize(style.danmakuFontSize,
                  commit: true);
              await player.setNext2DanmakuOutlineWidth(style.outlineWidth);
              await player.setDanmakuStacking(style.danmakuAllowStacking);
              player.setManualDanmakuOffset(style.danmakuOffset);
              await settings.drain();
            }, zoneValues: {
              SettingsAccess.invocationKey: invocation,
              SettingsAccess.reasonKey: input['reason']
            });
          }
          return _externalState();
        }),
      ];
}
