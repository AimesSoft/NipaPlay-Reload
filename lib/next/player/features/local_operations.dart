import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart' hide Action;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/danmaku_matching_service.dart';
import 'package:nipaplay/services/desktop_exit_handler.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/external_player_utils.dart';
import 'package:nipaplay/utils/mpv_utils.dart';
import 'package:window_manager/window_manager.dart';

import '../../capabilities/classic_action.dart';
import '../../danmaku/source.dart' show DanmakuEntry;
import '../../settings/registry.dart';
import '../ports/session_playback.dart';
import 'operation_specs.dart';
import 'windows.dart';

/// The local actions of Next's session. Only shared settings/data services
/// are reused: no Classic player, page or state is read or commanded.
final class NextFeatureOperations implements Capability {
  NextFeatureOperations(this.playback, this.settings);
  final SessionPlayback playback;
  final SettingsRegistry settings;
  bool _quitScheduled = false;

  @override
  List<Action> get actions => [
        for (final entry in featureOperationSpecs.entries)
          ClassicAction(entry.value,
              (input, invocation) => _call(entry.key, input, invocation))
      ];

  Future<JsonMap> _call(String id, JsonMap input, Invocation invocation) async {
    switch (id) {
      case 'playback.levels':
        if (input.containsKey('brightness')) {
          throw const Failure(FailureCode.unavailable,
              'Playback brightness requires a mobile platform.');
        }
        if (input.containsKey('volume')) {
          if (playback.externalHandoff?.active == true) {
            throw const Failure(
                FailureCode.unavailable, '在外部播放器中播放，请在该播放器中调整音量。');
          }
          await settings.set('player.volume', input['volume'], invocation,
              reason: input['reason'] as String?);
          // Also await application; a setting-change event alone is a request.
          await playback.setVolume((input['volume'] as num).toDouble());
        }
        return {
          'volume': playback.volume,
          'brightness': null,
          'brightnessSupported': false,
          'volumeTarget': 'internal_player',
          'playerVolume': playback.volume
        };
      case 'window.state':
        return _windowState();
      case 'window.control':
        return _windowControl(input);
      case 'playback.external_player_path':
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
      case 'app.quit':
        await settings.drain();
        if (!_quitScheduled) {
          _quitScheduled = true;
          Timer(const Duration(seconds: 1), () async {
            await playback.close(reason: 'quit');
            await DesktopExitHandler.instance.quit();
          });
        }
        return {'scheduled': true, 'processId': pid, 'delayMs': 1000};
      case 'danmaku.send':
        return _send(input);
      case 'playback.external.danmaku_state':
      case 'playback.external.danmaku':
        if (playback.externalHandoff?.active != true) {
          throw const Failure(
              FailureCode.unavailable, 'No external player handoff is active.');
        }
        if (id.endsWith('_state')) {
          return {
            'active': true,
            'controlAvailable': false,
            'telemetryAvailable': false,
            'style': null,
            'offsetSeconds': null,
            'rules': const [],
            'items': const [],
            'total': null,
            'nextOffset': null,
            'reason': 'external_player',
            'external': playback.externalHandoff!.facts()
          };
        }
        throw const Failure(
            FailureCode.unavailable, '在外部播放器中播放，NipaPlay 无法控制该播放器的弹幕。',
            details: {'reason': 'external_player', 'controlAvailable': false});
    }
    throw Failure(FailureCode.invalidInput, 'Unknown operation $id.');
  }

  Future<JsonMap> _send(JsonMap input) async {
    final text = (input['text'] as String).trim();
    final color = input['color'] as String? ?? '#FFFFFF';
    if (text.isEmpty ||
        text.characters.length > 100 ||
        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      throw const Failure(
          FailureCode.invalidInput, 'Use 1–100 characters and #RRGGBB color.');
    }
    final snapshot = playback.snapshot();
    final episode = snapshot.episodeId;
    final port = playback.danmakuPort();
    final target = port.target;
    if (!playback.hasVideo || episode == null || target == null) {
      throw const Failure(FailureCode.unavailable,
          'An identified internal video with a danmaku timeline is required.');
    }
    if (!DandanplayService.isLoggedIn) {
      throw const Failure(FailureCode.unavailable,
          'Complete Dandanplay login through accounts.login first.');
    }
    final time = playback.position.inMilliseconds / 1000;
    final mode = input['mode'] as String? ?? 'scroll';
    final result = await DanmakuMatchingService.instance.sendDanmaku(
        episodeId: episode,
        time: time,
        mode: switch (mode) { 'top' => 5, 'bottom' => 4, _ => 1 },
        color: int.parse(color.substring(1), radix: 16),
        comment: text);
    if (result['success'] != true) {
      throw const Failure(FailureCode.unavailable,
          'The server did not acknowledge the comment.');
    }
    final same = snapshot.sessionId == playback.snapshot().sessionId;
    final echo = same &&
        port.install(target, {
          'id': 'sent:${DateTime.now().microsecondsSinceEpoch}',
          'title': '发送的弹幕',
          'sourceId': 'dandanplay',
          'videoId': '$episode',
        }, [
          DanmakuEntry(
              sourceId: 'dandanplay',
              videoId: '$episode',
              platform: 'dandanplay',
              sourceTimeMs: (time * 1000).round(),
              text: text,
              mode: switch (mode) { 'top' => 5, 'bottom' => 4, _ => 1 },
              colorRgb: int.parse(color.substring(1), radix: 16))
        ]);
    return {
      'sent': true,
      'localEcho': echo,
      'episodeId': episode,
      'timeSeconds': time,
      'mode': mode,
      'color': color
    };
  }

  Future<JsonMap> _windowState() async {
    final w = playback.windows.nativeWindow;
    return {
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
      'detached': playback.windows.detached,
      'pictureInPicture': playback.windows.pictureInPicture,
      'player': {
        'open': w != null && !w.isClosed,
        'fullscreen': w?.isFullscreen ?? false,
        'alwaysOnTop': w?.isAlwaysOnTop ?? false
      },
      for (final target in ['external_controls', 'external_list'])
        target: {'open': false, 'fullscreen': false, 'alwaysOnTop': false}
    };
  }

  Future<JsonMap> _windowControl(JsonMap input) async {
    final command = input['command'] as String;
    final target = input['target'] as String? ?? 'main';
    final enabled = input['enabled'] as bool?;
    if (const ['pip', 'detached', 'fullscreen', 'always_on_top']
            .contains(command) &&
        enabled == null) {
      throw const Failure(
          FailureCode.invalidInput, 'This command requires enabled.');
    }
    if (const ['pip', 'detached'].contains(command)) {
      if (target != 'player')
        throw const Failure(
            FailureCode.invalidInput, 'Use target:player for pip/detached.');
      if (!PlaybackWindows.supported || !playback.hasVideo) {
        throw const Failure(FailureCode.unavailable,
            'An internal video and desktop window support are required.');
      }
      if (enabled!) {
        await playback.detach();
        if (command == 'pip')
          await playback.windows
              .setPictureInPicture(true, playback.videoAspect);
      } else if (command == 'pip') {
        await playback.windows.setPictureInPicture(false, playback.videoAspect);
      } else {
        await playback.windows.returnToMain();
      }
    } else if (target == 'player') {
      final w = playback.windows.nativeWindow;
      if (w == null || w.isClosed)
        throw const Failure(
            FailureCode.unavailable, 'The selected window is not open.');
      await _detachedCommand(w, command, enabled);
    } else if (target != 'main') {
      throw const Failure(FailureCode.unavailable, '在外部播放器中播放，窗口由该播放器管理。');
    } else {
      switch (command) {
        case 'fullscreen':
          await playback.setFullscreen(enabled!);
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
        case 'close':
          await windowManager.hide();
        case 'tray':
          await DesktopExitHandler.instance.minimizeToTray();
        case 'fit_video':
          if (!playback.hasVideo)
            throw const Failure(
                FailureCode.unavailable, 'An internal video is required.');
          await windowManager.setSize(Size(640, 640 / playback.videoAspect));
        default:
          throw const Failure(
              FailureCode.invalidInput, 'Unsupported window command.');
      }
    }
    return _windowState();
  }

  Future<void> _detachedCommand(
      WindowController w, String command, bool? enabled) async {
    switch (command) {
      case 'fullscreen':
        await w.setFullscreen(enabled!);
      case 'always_on_top':
        await w.setAlwaysOnTop(enabled!);
      case 'show':
        await w.show();
      case 'minimize':
        await w.setMinimized(true);
      case 'maximize':
        await w.setMaximized(true);
      case 'restore':
        await w.setMinimized(false);
        await w.setMaximized(false);
      case 'close':
        await playback.windows.returnToMain();
      case 'fit_video':
        await w.setSize(Size(640, 640 / playback.videoAspect));
      default:
        throw const Failure(
            FailureCode.invalidInput, 'Unsupported window command.');
    }
  }
}
