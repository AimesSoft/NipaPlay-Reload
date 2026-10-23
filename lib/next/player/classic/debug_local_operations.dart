import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_app_view_presenter.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/lab_profile.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../capabilities/ui_capture.dart';
import '../../instance_facts.dart';

/// Disposable fixture setup and independent Classic observations for lab runs.
void installDebugLocalOperations(VideoPlayerState player) {
  registerExtension('ext.nipaplay.localOperations', (_, params) async {
    try {
      final Object result;
      if (params['op'] == 'seed') {
        final path = params['path']!;
        if (!p.isWithin(LabProfile.root, path)) {
          throw ArgumentError('Fixture must be inside the lab profile.');
        }
        final animeId = int.parse(params['animeId']!);
        final episodeId = int.parse(params['episodeId']!);
        await ServiceProvider.watchHistoryProvider
            .addOrUpdateHistory(WatchHistoryItem(
          filePath: path,
          animeName: '实验短片',
          episodeTitle: '第一集',
          animeId: animeId,
          episodeId: episodeId,
          watchProgress: 0.1,
          lastPosition: 1000,
          duration: 120000,
          lastWatchTime: DateTime.now(),
        ));
        await DanmakuCacheManager.saveDanmakuToCache('$episodeId', animeId, [
          {
            'time': 3.0,
            'content': '蓝色的天空',
            'type': 'scroll',
            'color': 'rgb(255,255,255)',
            'senderId': 'fixture-one',
            'source': 'dandanplay'
          },
          {
            'time': 5.0,
            'content': '实验弹幕',
            'type': 'top',
            'color': 'rgb(255,0,0)',
            'senderId': 'fixture-two',
            'source': 'dandanplay'
          },
        ]);
        await ServiceProvider.watchHistoryProvider.refresh();
        result = {'seeded': true};
      } else if (params['op'] == 'observe') {
        final prefs = await SharedPreferences.getInstance();
        final window = DesktopPlayerWindowService.instance.activeWindow;
        result = {
          'hasVideo': player.hasVideo,
          'path': player.currentVideoPath,
          'volume': player.currentSystemVolume,
          'playerVolume': player.player.volume,
          'savedVolume': prefs.getDouble('player_volume'),
          'manualOffset': player.manualDanmakuOffset,
          'opacity': player.danmakuOpacity,
          'fontSize': player.danmakuFontSize,
          'roots': ServiceProvider.scanService.scannedFolders,
          'savedRoots': prefs.getStringList('nipaplay_scanned_folders'),
          'history': [
            for (final item in await WatchHistoryManager.getAllHistory())
              item.toJson()
          ],
          'tracks': player.danmakuTracks,
          'detachedWindow': window == null
              ? null
              : {
                  'size': {
                    'width': window.size.width,
                    'height': window.size.height
                  },
                  'active': window.isActive,
                  'fullscreen': window.isFullscreen,
                  'alwaysOnTop': window.isAlwaysOnTop,
                },
        };
      } else if (params['op'] == 'capture') {
        // The window as it is, Classic included: a lab handle, not a
        // capability (in Classic none of Nipa's run).
        final info = await PackageInfo.fromPlatform();
        result = await ClassicUiCapture(InstanceFacts(info.version)).capture();
      } else if (params['op'] == 'settings') {
        // Classic's settings at a page (labs…), as its menu opens them.
        final context = globals.navigatorKey.currentState?.overlay?.context;
        if (context == null) throw StateError('No window to show settings in.');
        unawaited(UnifiedAppViewPresenter.show<void>(context,
            viewId: AppPageIds.settings, initialSubpageId: params['page']));
        await Future<void>.delayed(const Duration(milliseconds: 800));
        result = {'shown': params['page']};
      } else if (params['op'] == 'play') {
        // Classic's own way of opening a file, as its file list does.
        result = {
          'started': await PlaybackService()
              .play(PlayableItem(videoPath: params['path']!))
        };
      } else if (params['op'] == 'nipa') {
        final core = ServiceProvider.nextCore;
        result = {
          'nipaRunning': core.nipaRunning,
          'gateOpen': core.nipaGate.open,
          'hooks': await core.hooks.status(),
          'classic': {
            'hasVideo': player.hasVideo,
            'status': player.status.name,
            'path': player.currentVideoPath,
            'positionMs': player.position.inMilliseconds,
          },
        };
      } else {
        throw ArgumentError('Unknown lab operation.');
      }
      return ServiceExtensionResponse.result(jsonEncode(result));
    } catch (error) {
      return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, '$error');
    }
  });
}
