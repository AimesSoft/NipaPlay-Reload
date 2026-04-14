import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/player_menu/player_menu_definition_builder.dart';
import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class PlayerRemoteControlBridge {
  PlayerRemoteControlBridge._();

  static final PlayerRemoteControlBridge instance =
      PlayerRemoteControlBridge._();

  VideoPlayerState? _videoState;
  DateTime? _lastCommandAt;

  void attach(VideoPlayerState state) {
    _videoState = state;
  }

  void detach(VideoPlayerState state) {
    if (identical(_videoState, state)) {
      _videoState = null;
    }
  }

  bool get isAttached => _videoState != null;

  Future<Map<String, dynamic>> buildPayload({
    String? paneId,
    bool includeParameters = false,
  }) async {
    final enabled = await RemoteControlSettings.isReceiverEnabled();
    final state = _videoState;
    final normalizedPaneId = paneId?.trim();
    final shouldIncludeParameters =
        includeParameters || (normalizedPaneId?.isNotEmpty ?? false);
    if (state == null) {
      return {
        'receiverEnabled': enabled,
        'available': false,
        'message': '播放器尚未初始化',
        'snapshot': _buildUnavailableSnapshot(),
        'menus': const <Map<String, dynamic>>[],
        'parameters': const <Map<String, dynamic>>[],
      };
    }

    final menuItems = _buildVisibleMenuItems(state);
    final parameters = shouldIncludeParameters
        ? await _buildParameters(
            state,
            menuItems,
            paneId: normalizedPaneId,
          )
        : const <Map<String, dynamic>>[];

    return {
      'receiverEnabled': enabled,
      'available': true,
      'message': enabled ? 'ok' : '被遥控端已关闭',
      'snapshot': _buildSnapshot(state),
      'menus': menuItems,
      'parameters': parameters,
      'lastCommandAt': _lastCommandAt?.toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> executeCommand(
    String command,
    Map<String, dynamic> args,
  ) async {
    final state = _videoState;
    if (state == null) {
      return {
        'success': false,
        'message': '播放器未就绪',
        'payload': await buildPayload(),
      };
    }

    final receiverEnabled = await RemoteControlSettings.isReceiverEnabled();
    if (!receiverEnabled) {
      return {
        'success': false,
        'message': '被遥控端已关闭',
        'payload': await buildPayload(),
      };
    }

    try {
      switch (command) {
        case 'play_previous_episode':
          await state.playPreviousEpisode();
          break;
        case 'toggle_play_pause':
          state.togglePlayPause();
          break;
        case 'play_next_episode':
          await state.playNextEpisode();
          break;
        case 'skip':
          state.skip();
          break;
        case 'seek_by_seconds':
          final seconds = _asDouble(args['seconds'], fallback: 0);
          final delta = Duration(milliseconds: (seconds * 1000).round());
          state.seekTo(state.position + delta);
          break;
        case 'send_danmaku':
          await _sendDanmaku(state, args);
          break;
        case 'set_parameter':
          final key = args['key']?.toString() ?? '';
          await _setParameter(state, key, args['value']);
          break;
        default:
          return {
            'success': false,
            'message': '未知命令: $command',
            'payload': await buildPayload(),
          };
      }

      _lastCommandAt = DateTime.now();
      return {
        'success': true,
        'message': 'ok',
        'payload': await buildPayload(),
      };
    } catch (e) {
      return {
        'success': false,
        'message': '执行失败: $e',
        'payload': await buildPayload(),
      };
    }
  }

  Map<String, dynamic> _buildUnavailableSnapshot() {
    return {
      'status': 'idle',
      'hasVideo': false,
      'isPaused': true,
      'canPlayPreviousEpisode': false,
      'canPlayNextEpisode': false,
      'positionMs': 0,
      'durationMs': 0,
      'progress': 0,
    };
  }

  Map<String, dynamic> _buildSnapshot(VideoPlayerState state) {
    return {
      'status': state.status.name,
      'hasVideo': state.hasVideo,
      'isPaused': state.isPaused,
      'canPlayPreviousEpisode': state.canPlayPreviousEpisode,
      'canPlayNextEpisode': state.canPlayNextEpisode,
      'positionMs': state.position.inMilliseconds,
      'durationMs': state.duration.inMilliseconds,
      'progress': state.progress,
      'bufferedPositionMs': state.bufferedPosition,
      'playbackRate': state.playbackRate,
      'speedBoostRate': state.speedBoostRate,
      'skipSeconds': state.skipSeconds,
      'seekStepSeconds': state.seekStepSeconds,
      'currentVideoPath': state.currentVideoPath,
      'animeTitle': state.animeTitle,
      'episodeTitle': state.episodeTitle,
      'animeId': state.animeId,
      'episodeId': state.episodeId,
      'danmakuTrackCount': state.danmakuTracks.length,
      'danmakuVisible': state.danmakuVisible,
      'subtitleTrackCount': state.player.mediaInfo.subtitle?.length ?? 0,
      'audioTrackCount': state.player.mediaInfo.audio?.length ?? 0,
      'isStreaming':
          (state.currentVideoPath?.startsWith('jellyfin://') ?? false) ||
              (state.currentVideoPath?.startsWith('emby://') ?? false),
    };
  }

  List<Map<String, dynamic>> _buildVisibleMenuItems(VideoPlayerState state) {
    final kernelType = PlayerFactory.getKernelType();
    final definitions = PlayerMenuDefinitionBuilder(
      context: PlayerMenuContext(videoState: state, kernelType: kernelType),
    ).build();

    return definitions
        .map(
          (item) => {
            'paneId': item.paneId.name,
            'category': item.category.name,
            'icon': item.icon.name,
            'title': item.title,
          },
        )
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _buildParameters(
    VideoPlayerState state,
    List<Map<String, dynamic>> menuItems, {
    String? paneId,
  }) async {
    final visiblePaneIds = menuItems
        .map((item) => item['paneId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (paneId != null && paneId.isNotEmpty) {
      visiblePaneIds.removeWhere((id) => id != paneId);
    }

    bool paneVisible(PlayerMenuPaneId paneId) =>
        visiblePaneIds.contains(paneId.name);

    final params = <Map<String, dynamic>>[];

    void addBool({
      required PlayerMenuPaneId paneId,
      required String key,
      required String label,
      required bool value,
    }) {
      if (!paneVisible(paneId)) return;
      params.add({
        'paneId': paneId.name,
        'key': key,
        'label': label,
        'type': 'bool',
        'value': value,
      });
    }

    void addDouble({
      required PlayerMenuPaneId paneId,
      required String key,
      required String label,
      required double value,
      double? min,
      double? max,
      double? step,
    }) {
      if (!paneVisible(paneId)) return;
      params.add({
        'paneId': paneId.name,
        'key': key,
        'label': label,
        'type': 'double',
        'value': value,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (step != null) 'step': step,
      });
    }

    void addInt({
      required PlayerMenuPaneId paneId,
      required String key,
      required String label,
      required int value,
      int? min,
      int? max,
      int? step,
    }) {
      if (!paneVisible(paneId)) return;
      params.add({
        'paneId': paneId.name,
        'key': key,
        'label': label,
        'type': 'int',
        'value': value,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (step != null) 'step': step,
      });
    }

    void addEnum({
      required PlayerMenuPaneId paneId,
      required String key,
      required String label,
      required String value,
      required List<Map<String, dynamic>> options,
    }) {
      if (!paneVisible(paneId)) return;
      params.add({
        'paneId': paneId.name,
        'key': key,
        'label': label,
        'type': 'enum',
        'value': value,
        'options': options,
      });
    }

    void addSelect({
      required PlayerMenuPaneId paneId,
      required String key,
      required String label,
      required dynamic value,
      required List<Map<String, dynamic>> options,
      bool nullable = false,
    }) {
      if (!paneVisible(paneId)) return;
      params.add({
        'paneId': paneId.name,
        'key': key,
        'label': label,
        'type': 'select',
        'value': value,
        'options': options,
        'nullable': nullable,
      });
    }

    void addString({
      required PlayerMenuPaneId paneId,
      required String key,
      required String label,
      required String value,
    }) {
      if (!paneVisible(paneId)) return;
      params.add({
        'paneId': paneId.name,
        'key': key,
        'label': label,
        'type': 'string',
        'value': value,
      });
    }

    void addReadOnly({
      required PlayerMenuPaneId paneId,
      required String key,
      required String label,
      required dynamic value,
    }) {
      if (!paneVisible(paneId)) return;
      params.add({
        'paneId': paneId.name,
        'key': key,
        'label': label,
        'type': 'readonly',
        'value': value,
      });
    }

    if (paneVisible(PlayerMenuPaneId.subtitleSettings)) {
      addEnum(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.overrideMode',
        label: '字幕样式接管',
        value: state.subtitleOverrideMode.name,
        options: SubtitleStyleOverrideMode.values
            .map((item) => {'value': item.name, 'label': item.name})
            .toList(growable: false),
      );
      addDouble(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.scale',
        label: '字幕大小',
        value: state.subtitleScale,
        min: VideoPlayerState.minSubtitleScale,
        max: VideoPlayerState.maxSubtitleScale,
        step: 0.05,
      );
      addDouble(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.delaySeconds',
        label: '字幕时间偏移',
        value: state.subtitleDelaySeconds,
        min: state.subtitleDelaySliderMinSeconds,
        max: state.subtitleDelaySliderMaxSeconds,
        step: VideoPlayerState.subtitleDelayStep,
      );
      addDouble(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.position',
        label: '字幕垂直位置',
        value: state.subtitlePosition,
        min: 0,
        max: 100,
        step: 1,
      );
      addEnum(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.alignX',
        label: '字幕水平对齐',
        value: state.subtitleAlignX.name,
        options: SubtitleAlignX.values
            .map((item) => {'value': item.name, 'label': item.name})
            .toList(growable: false),
      );
      addEnum(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.alignY',
        label: '字幕垂直对齐',
        value: state.subtitleAlignY.name,
        options: SubtitleAlignY.values
            .map((item) => {'value': item.name, 'label': item.name})
            .toList(growable: false),
      );
      addDouble(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.marginX',
        label: '字幕横向边距',
        value: state.subtitleMarginX,
        min: -500,
        max: 500,
        step: 1,
      );
      addDouble(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.marginY',
        label: '字幕纵向边距',
        value: state.subtitleMarginY,
        min: -500,
        max: 500,
        step: 1,
      );
      addDouble(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.opacity',
        label: '字幕透明度',
        value: state.subtitleOpacity,
        min: 0,
        max: 1,
        step: 0.01,
      );
      addDouble(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.borderSize',
        label: '字幕描边粗细',
        value: state.subtitleBorderSize,
        min: 0,
        max: 20,
        step: 0.1,
      );
      addDouble(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.shadowOffset',
        label: '字幕阴影偏移',
        value: state.subtitleShadowOffset,
        min: 0,
        max: 20,
        step: 0.1,
      );
      addBool(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.bold',
        label: '字幕加粗',
        value: state.subtitleBold,
      );
      addBool(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.italic',
        label: '字幕斜体',
        value: state.subtitleItalic,
      );
      addString(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.color',
        label: '字幕颜色',
        value: _toHexColor(state.subtitleColor),
      );
      addString(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.borderColor',
        label: '字幕描边颜色',
        value: _toHexColor(state.subtitleBorderColor),
      );
      addString(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.shadowColor',
        label: '字幕阴影颜色',
        value: _toHexColor(state.subtitleShadowColor),
      );
      addString(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.fontName',
        label: '字幕字体',
        value: state.subtitleFontName,
      );
      addReadOnly(
        paneId: PlayerMenuPaneId.subtitleSettings,
        key: 'subtitle.fontDir',
        label: '字幕字体目录',
        value: state.subtitleFontDir,
      );
    }

    if (paneVisible(PlayerMenuPaneId.subtitleTracks)) {
      final subtitleTracks = state.player.mediaInfo.subtitle ?? const [];
      final activeSubtitle = state.player.activeSubtitleTracks.isEmpty
          ? -1
          : state.player.activeSubtitleTracks.first;
      final options = <Map<String, dynamic>>[
        {'value': -1, 'label': '关闭字幕'},
      ];
      for (var i = 0; i < subtitleTracks.length; i++) {
        final item = subtitleTracks[i];
        options.add({
          'value': i,
          'label':
              _trackLabel(item.title, item.language, fallback: '字幕 ${i + 1}'),
        });
      }
      addSelect(
        paneId: PlayerMenuPaneId.subtitleTracks,
        key: 'subtitle.activeTrackIndex',
        label: '字幕轨道',
        value: activeSubtitle,
        options: options,
      );
      addReadOnly(
        paneId: PlayerMenuPaneId.subtitleTracks,
        key: 'subtitle.externalPath',
        label: '外挂字幕路径',
        value: state.getActiveExternalSubtitlePath(),
      );
      params.add({
        'paneId': PlayerMenuPaneId.subtitleTracks.name,
        'key': 'subtitle.trackInfo',
        'label': '字幕轨道信息',
        'type': 'json',
        'value': state.subtitleTrackInfo,
      });
    }

    if (paneVisible(PlayerMenuPaneId.subtitleList)) {
      addReadOnly(
        paneId: PlayerMenuPaneId.subtitleList,
        key: 'subtitle.currentLine',
        label: '当前字幕',
        value: state.getCurrentSubtitleText(),
      );
      addReadOnly(
        paneId: PlayerMenuPaneId.subtitleList,
        key: 'subtitle.currentPositionMs',
        label: '当前时间',
        value: state.position.inMilliseconds,
      );
      params.add({
        'paneId': PlayerMenuPaneId.subtitleList.name,
        'key': 'subtitle.trackInfo',
        'label': '字幕轨道信息',
        'type': 'json',
        'value': state.subtitleTrackInfo,
      });
    }

    if (paneVisible(PlayerMenuPaneId.audioTracks)) {
      final audioTracks = state.player.mediaInfo.audio ?? const [];
      final activeAudio = state.player.activeAudioTracks.isEmpty
          ? -1
          : state.player.activeAudioTracks.first;
      final options = <Map<String, dynamic>>[
        {'value': -1, 'label': '默认轨道'},
      ];
      for (var i = 0; i < audioTracks.length; i++) {
        final item = audioTracks[i];
        options.add({
          'value': i,
          'label':
              _trackLabel(item.title, item.language, fallback: '音轨 ${i + 1}'),
        });
      }
      addSelect(
        paneId: PlayerMenuPaneId.audioTracks,
        key: 'audio.activeTrackIndex',
        label: '音频轨道',
        value: activeAudio,
        options: options,
      );
    }

    if (paneVisible(PlayerMenuPaneId.danmakuSettings)) {
      addBool(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.visible',
        label: '显示弹幕',
        value: state.danmakuVisible,
      );
      addBool(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.showDensityChart',
        label: '显示弹幕密度图',
        value: state.showDanmakuDensityChart,
      );
      addBool(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.randomColor',
        label: '弹幕随机染色',
        value: state.danmakuRandomColorEnabled,
      );
      addDouble(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.opacity',
        label: '弹幕透明度',
        value: state.danmakuOpacity,
        min: 0,
        max: 1,
        step: 0.01,
      );
      addDouble(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.fontSize',
        label: '弹幕字体大小',
        value: state.danmakuFontSize <= 0
            ? state.actualDanmakuFontSize
            : state.danmakuFontSize,
        min: 8,
        max: 100,
        step: 1,
      );
      addEnum(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.outlineStyle',
        label: '弹幕描边样式',
        value: state.danmakuOutlineStyle.name,
        options: DanmakuOutlineStyle.values
            .map((item) => {'value': item.name, 'label': item.name})
            .toList(growable: false),
      );
      addEnum(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.shadowStyle',
        label: '弹幕阴影样式',
        value: state.danmakuShadowStyle.name,
        options: DanmakuShadowStyle.values
            .map((item) => {'value': item.name, 'label': item.name})
            .toList(growable: false),
      );
      addDouble(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.speedMultiplier',
        label: '弹幕速度倍率',
        value: state.danmakuSpeedMultiplier,
        min: 0.5,
        max: 3,
        step: 0.01,
      );
      addDouble(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.displayArea',
        label: '弹幕显示区域',
        value: state.danmakuDisplayArea,
        min: 0.1,
        max: 1,
        step: 0.1,
      );
      addBool(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.stacking',
        label: '启用弹幕堆叠',
        value: state.danmakuStacking,
      );
      addBool(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.merge',
        label: '合并弹幕',
        value: state.mergeDanmaku,
      );
      addBool(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.blockTop',
        label: '屏蔽顶部弹幕',
        value: state.blockTopDanmaku,
      );
      addBool(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.blockBottom',
        label: '屏蔽底部弹幕',
        value: state.blockBottomDanmaku,
      );
      addBool(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.blockScroll',
        label: '屏蔽滚动弹幕',
        value: state.blockScrollDanmaku,
      );
      addBool(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.timelineEnabled',
        label: '时间轴告知弹幕',
        value: state.isTimelineDanmakuEnabled,
      );
      params.add({
        'paneId': PlayerMenuPaneId.danmakuSettings.name,
        'key': 'danmaku.blockWords',
        'label': '弹幕屏蔽词',
        'type': 'string_list',
        'value': List<String>.from(state.danmakuBlockWords),
      });
      addReadOnly(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.fontFilePath',
        label: '弹幕字体文件',
        value: state.danmakuFontFilePath,
      );
      addReadOnly(
        paneId: PlayerMenuPaneId.danmakuSettings,
        key: 'danmaku.fontFamily',
        label: '弹幕字体名称',
        value: state.danmakuFontFamily,
      );
    }

    if (paneVisible(PlayerMenuPaneId.danmakuOffset)) {
      addDouble(
        paneId: PlayerMenuPaneId.danmakuOffset,
        key: 'danmaku.manualOffset',
        label: '弹幕手动偏移',
        value: state.manualDanmakuOffset,
        min: -30,
        max: 30,
        step: 0.1,
      );
      addReadOnly(
        paneId: PlayerMenuPaneId.danmakuOffset,
        key: 'danmaku.autoOffset',
        label: '弹幕自动偏移',
        value: state.autoDanmakuOffset,
      );
    }

    if (paneVisible(PlayerMenuPaneId.danmakuTracks)) {
      for (final entry in state.danmakuTracks.entries) {
        final trackId = entry.key;
        final trackData = entry.value;
        final enabled = state.danmakuTrackEnabled[trackId] ?? true;
        final count =
            trackData['count'] is int ? trackData['count'] as int : null;
        params.add({
          'paneId': PlayerMenuPaneId.danmakuTracks.name,
          'key': 'danmaku.track.enabled::$trackId',
          'label': '轨道 ${trackData['name'] ?? trackId}',
          'type': 'bool',
          'value': enabled,
          if (count != null) 'count': count,
        });
      }
    }

    if (paneVisible(PlayerMenuPaneId.danmakuList)) {
      addReadOnly(
        paneId: PlayerMenuPaneId.danmakuList,
        key: 'danmaku.totalCount',
        label: '当前弹幕总数',
        value: state.danmakuList.length,
      );
      params.add({
        'paneId': PlayerMenuPaneId.danmakuList.name,
        'key': 'danmaku.windowList',
        'label': '当前位置弹幕窗口',
        'type': 'json',
        'value': state.getActiveDanmakuList(
          state.position.inMilliseconds / 1000.0,
          window: 30,
        ),
      });
    }

    if (paneVisible(PlayerMenuPaneId.controlBarSettings)) {
      addBool(
        paneId: PlayerMenuPaneId.controlBarSettings,
        key: 'controlBar.minimalProgressBarEnabled',
        label: '极简进度条',
        value: state.minimalProgressBarEnabled,
      );
      addBool(
        paneId: PlayerMenuPaneId.controlBarSettings,
        key: 'controlBar.showDanmakuDensityChart',
        label: '显示弹幕密度图',
        value: state.showDanmakuDensityChart,
      );
      addString(
        paneId: PlayerMenuPaneId.controlBarSettings,
        key: 'controlBar.minimalProgressBarColor',
        label: '进度条颜色',
        value: _toHexColor(state.minimalProgressBarColor),
      );
    }

    if (paneVisible(PlayerMenuPaneId.playbackRate)) {
      addDouble(
        paneId: PlayerMenuPaneId.playbackRate,
        key: 'playback.rate',
        label: '播放速度',
        value: state.playbackRate,
        min: VideoPlayerState.minPlaybackRate,
        max: VideoPlayerState.maxPlaybackRate,
        step: 0.05,
      );
    }

    if (paneVisible(PlayerMenuPaneId.seekStep)) {
      addDouble(
        paneId: PlayerMenuPaneId.seekStep,
        key: 'seek.stepSeconds',
        label: '快进快退步长',
        value: state.seekStepSeconds,
        min: state.seekStepMinSeconds,
        max: state.seekStepMaxSeconds,
        step: 0.05,
      );
      addDouble(
        paneId: PlayerMenuPaneId.seekStep,
        key: 'seek.speedBoostRate',
        label: '长按倍速倍率',
        value: state.speedBoostRate,
        min: 1,
        max: 5,
        step: 0.25,
      );
      addInt(
        paneId: PlayerMenuPaneId.seekStep,
        key: 'seek.skipSeconds',
        label: '跳过时间（秒）',
        value: state.skipSeconds,
        min: 10,
        max: 600,
        step: 10,
      );
      addBool(
        paneId: PlayerMenuPaneId.seekStep,
        key: 'player.pauseOnBackground',
        label: '后台自动暂停',
        value: state.pauseOnBackground,
      );
      addBool(
        paneId: PlayerMenuPaneId.seekStep,
        key: 'player.desktopHoverSettingsMenuEnabled',
        label: '右侧悬浮设置菜单',
        value: state.desktopHoverSettingsMenuEnabled,
      );
      addBool(
        paneId: PlayerMenuPaneId.seekStep,
        key: 'player.instantHidePlayerUiEnabled',
        label: '立即隐藏播放器 UI',
        value: state.instantHidePlayerUiEnabled,
      );
      addBool(
        paneId: PlayerMenuPaneId.seekStep,
        key: 'player.useHardwareDecoder',
        label: '硬件解码',
        value: state.useHardwareDecoder,
      );
    }

    if (paneVisible(PlayerMenuPaneId.jellyfinQuality)) {
      final path = state.currentVideoPath ?? '';
      final isJellyfin = path.startsWith('jellyfin://');
      final isEmby = path.startsWith('emby://');
      JellyfinVideoQuality quality = JellyfinVideoQuality.bandwidth5m;
      bool transcodeEnabled = true;
      int? selectedSubtitleIndex;
      bool burnIn = false;
      List<Map<String, dynamic>> serverSubtitleOptions = [];

      if (isJellyfin) {
        final provider = JellyfinTranscodeProvider();
        await provider.initialize();
        quality = provider.currentVideoQuality;
        transcodeEnabled = provider.transcodeEnabled;
        final itemId = path.replaceFirst('jellyfin://', '');
        selectedSubtitleIndex =
            state.getJellyfinServerSubtitleSelection(itemId);
        burnIn = state.getJellyfinServerSubtitleBurnIn(itemId);
        final tracks = await JellyfinService.instance.getSubtitleTracks(itemId);
        serverSubtitleOptions = _subtitleTrackOptions(tracks);
      } else if (isEmby) {
        final provider = EmbyTranscodeProvider();
        await provider.initialize();
        quality = provider.currentVideoQuality;
        transcodeEnabled = provider.transcodeEnabled;
        final itemId = path.replaceFirst('emby://', '');
        selectedSubtitleIndex = state.getEmbyServerSubtitleSelection(itemId);
        burnIn = state.getEmbyServerSubtitleBurnIn(itemId);
        final tracks = await EmbyService.instance.getSubtitleTracks(itemId);
        serverSubtitleOptions = _subtitleTrackOptions(tracks);
      }

      addEnum(
        paneId: PlayerMenuPaneId.jellyfinQuality,
        key: 'stream.quality',
        label: '串流清晰度',
        value: quality.name,
        options: JellyfinVideoQuality.values
            .map((q) => {'value': q.name, 'label': q.name})
            .toList(growable: false),
      );
      addBool(
        paneId: PlayerMenuPaneId.jellyfinQuality,
        key: 'stream.transcodeEnabled',
        label: '启用转码',
        value: transcodeEnabled,
      );
      addSelect(
        paneId: PlayerMenuPaneId.jellyfinQuality,
        key: 'stream.subtitleIndex',
        label: '服务器字幕轨道',
        value: selectedSubtitleIndex,
        options: serverSubtitleOptions,
        nullable: true,
      );
      addBool(
        paneId: PlayerMenuPaneId.jellyfinQuality,
        key: 'stream.burnInSubtitle',
        label: '烧录字幕',
        value: burnIn,
      );
    }

    if (paneVisible(PlayerMenuPaneId.playbackInfo)) {
      final info = state.player.getDetailedMediaInfo();
      addReadOnly(
        paneId: PlayerMenuPaneId.playbackInfo,
        key: 'playbackInfo.detailed',
        label: '播放信息',
        value: info,
      );
    }

    if (paneVisible(PlayerMenuPaneId.playlist)) {
      addReadOnly(
        paneId: PlayerMenuPaneId.playlist,
        key: 'playlist.currentVideoPath',
        label: '当前播放路径',
        value: state.currentVideoPath,
      );
      addReadOnly(
        paneId: PlayerMenuPaneId.playlist,
        key: 'playlist.animeTitle',
        label: '当前番剧标题',
        value: state.animeTitle,
      );
    }

    return params;
  }

  Future<void> _setParameter(
    VideoPlayerState state,
    String key,
    dynamic value,
  ) async {
    if (key.isEmpty) {
      throw ArgumentError('参数 key 不能为空');
    }

    if (key.startsWith('danmaku.track.enabled::')) {
      final trackId = key.split('::').last;
      final enabled = _asBool(value, fallback: true);
      state.toggleDanmakuTrack(trackId, enabled);
      return;
    }

    switch (key) {
      case 'subtitle.overrideMode':
        final mode = SubtitleStyleOverrideMode.values.firstWhere(
          (item) => item.name == value?.toString(),
          orElse: () => state.subtitleOverrideMode,
        );
        await state.setSubtitleOverrideMode(mode);
        return;
      case 'subtitle.scale':
        await state
            .setSubtitleScale(_asDouble(value, fallback: state.subtitleScale));
        return;
      case 'subtitle.delaySeconds':
        await state.setSubtitleDelaySeconds(
          _asDouble(value, fallback: state.subtitleDelaySeconds),
        );
        return;
      case 'subtitle.position':
        await state.setSubtitlePosition(
            _asDouble(value, fallback: state.subtitlePosition));
        return;
      case 'subtitle.alignX':
        final align = SubtitleAlignX.values.firstWhere(
          (item) => item.name == value?.toString(),
          orElse: () => state.subtitleAlignX,
        );
        await state.setSubtitleAlignX(align);
        return;
      case 'subtitle.alignY':
        final align = SubtitleAlignY.values.firstWhere(
          (item) => item.name == value?.toString(),
          orElse: () => state.subtitleAlignY,
        );
        await state.setSubtitleAlignY(align);
        return;
      case 'subtitle.marginX':
        await state.setSubtitleMarginX(
            _asDouble(value, fallback: state.subtitleMarginX));
        return;
      case 'subtitle.marginY':
        await state.setSubtitleMarginY(
            _asDouble(value, fallback: state.subtitleMarginY));
        return;
      case 'subtitle.opacity':
        await state.setSubtitleOpacity(
            _asDouble(value, fallback: state.subtitleOpacity));
        return;
      case 'subtitle.borderSize':
        await state.setSubtitleBorderSize(
          _asDouble(value, fallback: state.subtitleBorderSize),
        );
        return;
      case 'subtitle.shadowOffset':
        await state.setSubtitleShadowOffset(
          _asDouble(value, fallback: state.subtitleShadowOffset),
        );
        return;
      case 'subtitle.bold':
        await state
            .setSubtitleBold(_asBool(value, fallback: state.subtitleBold));
        return;
      case 'subtitle.italic':
        await state
            .setSubtitleItalic(_asBool(value, fallback: state.subtitleItalic));
        return;
      case 'subtitle.color':
        final color = _parseColor(value);
        if (color != null) {
          await state.setSubtitleColor(color);
        }
        return;
      case 'subtitle.borderColor':
        final color = _parseColor(value);
        if (color != null) {
          await state.setSubtitleBorderColor(color);
        }
        return;
      case 'subtitle.shadowColor':
        final color = _parseColor(value);
        if (color != null) {
          await state.setSubtitleShadowColor(color);
        }
        return;
      case 'subtitle.fontName':
        await state.setSubtitleFontName(value?.toString() ?? '');
        return;
      case 'subtitle.activeTrackIndex':
        final index = _asInt(value, fallback: -1);
        if (index < 0) {
          state.player.activeSubtitleTracks = [];
          state.setExternalSubtitle('');
        } else {
          state.player.activeSubtitleTracks = [index];
        }
        return;
      case 'audio.activeTrackIndex':
        await _setAudioTrack(state, _asInt(value, fallback: -1));
        return;
      case 'danmaku.visible':
        state.setDanmakuVisible(_asBool(value, fallback: state.danmakuVisible));
        return;
      case 'danmaku.showDensityChart':
        await state.setShowDanmakuDensityChart(
          _asBool(value, fallback: state.showDanmakuDensityChart),
        );
        return;
      case 'danmaku.randomColor':
        await state.setDanmakuRandomColorEnabled(
          _asBool(value, fallback: state.danmakuRandomColorEnabled),
        );
        return;
      case 'danmaku.opacity':
        await state.setDanmakuOpacity(
            _asDouble(value, fallback: state.danmakuOpacity));
        return;
      case 'danmaku.fontSize':
        await state.setDanmakuFontSize(
          _asDouble(value, fallback: state.actualDanmakuFontSize),
        );
        return;
      case 'danmaku.outlineStyle':
        final style = DanmakuOutlineStyle.values.firstWhere(
          (item) => item.name == value?.toString(),
          orElse: () => state.danmakuOutlineStyle,
        );
        await state.setDanmakuOutlineStyle(style);
        return;
      case 'danmaku.shadowStyle':
        final style = DanmakuShadowStyle.values.firstWhere(
          (item) => item.name == value?.toString(),
          orElse: () => state.danmakuShadowStyle,
        );
        await state.setDanmakuShadowStyle(style);
        return;
      case 'danmaku.speedMultiplier':
        await state.setDanmakuSpeedMultiplier(
          _asDouble(value, fallback: state.danmakuSpeedMultiplier),
        );
        return;
      case 'danmaku.displayArea':
        await state.setDanmakuDisplayArea(
          _asDouble(value, fallback: state.danmakuDisplayArea),
        );
        return;
      case 'danmaku.stacking':
        await state.setDanmakuStacking(
            _asBool(value, fallback: state.danmakuStacking));
        return;
      case 'danmaku.merge':
        await state
            .setMergeDanmaku(_asBool(value, fallback: state.mergeDanmaku));
        return;
      case 'danmaku.blockTop':
        await state.setBlockTopDanmaku(
            _asBool(value, fallback: state.blockTopDanmaku));
        return;
      case 'danmaku.blockBottom':
        await state.setBlockBottomDanmaku(
          _asBool(value, fallback: state.blockBottomDanmaku),
        );
        return;
      case 'danmaku.blockScroll':
        await state.setBlockScrollDanmaku(
          _asBool(value, fallback: state.blockScrollDanmaku),
        );
        return;
      case 'danmaku.timelineEnabled':
        await state.toggleTimelineDanmaku(
          _asBool(value, fallback: state.isTimelineDanmakuEnabled),
        );
        return;
      case 'danmaku.blockWords':
        await _setDanmakuBlockWords(state, value);
        return;
      case 'danmaku.manualOffset':
        state.setManualDanmakuOffset(
            _asDouble(value, fallback: state.manualDanmakuOffset));
        return;
      case 'controlBar.minimalProgressBarEnabled':
        await state.setMinimalProgressBarEnabled(
          _asBool(value, fallback: state.minimalProgressBarEnabled),
        );
        return;
      case 'controlBar.showDanmakuDensityChart':
        await state.setShowDanmakuDensityChart(
          _asBool(value, fallback: state.showDanmakuDensityChart),
        );
        return;
      case 'controlBar.minimalProgressBarColor':
        final color = _parseColor(value);
        if (color != null) {
          await state.setMinimalProgressBarColor(color.toARGB32());
        }
        return;
      case 'playback.rate':
        await state
            .setPlaybackRate(_asDouble(value, fallback: state.playbackRate));
        return;
      case 'seek.stepSeconds':
        await state.setSeekStepSeconds(
            _asDouble(value, fallback: state.seekStepSeconds));
        return;
      case 'seek.speedBoostRate':
        await state.setSpeedBoostRate(
            _asDouble(value, fallback: state.speedBoostRate));
        return;
      case 'seek.skipSeconds':
        await state.setSkipSeconds(_asInt(value, fallback: state.skipSeconds));
        return;
      case 'player.pauseOnBackground':
        await state.setPauseOnBackground(
            _asBool(value, fallback: state.pauseOnBackground));
        return;
      case 'player.desktopHoverSettingsMenuEnabled':
        await state.setDesktopHoverSettingsMenuEnabled(
          _asBool(value, fallback: state.desktopHoverSettingsMenuEnabled),
        );
        return;
      case 'player.instantHidePlayerUiEnabled':
        await state.setInstantHidePlayerUiEnabled(
          _asBool(value, fallback: state.instantHidePlayerUiEnabled),
        );
        return;
      case 'player.useHardwareDecoder':
        await state.setHardwareDecoderEnabled(
            _asBool(value, fallback: state.useHardwareDecoder));
        return;
      case 'stream.quality':
      case 'stream.transcodeEnabled':
      case 'stream.subtitleIndex':
      case 'stream.burnInSubtitle':
        await _applyStreamingSettings(
          state,
          key: key,
          value: value,
        );
        return;
      default:
        throw UnsupportedError('不支持的参数: $key');
    }
  }

  Future<void> _setAudioTrack(VideoPlayerState state, int index) async {
    final path = state.currentVideoPath ?? '';
    final isJellyfin = path.startsWith('jellyfin://');
    final isEmby = path.startsWith('emby://');

    if (isJellyfin || isEmby) {
      final tracks = state.player.mediaInfo.audio ?? const [];
      if (index < 0 || index >= tracks.length) {
        state.player.activeAudioTracks = [];
        return;
      }
      final item = tracks[index];
      final rawIndex = item.metadata['index'];
      final serverIndex = int.tryParse(rawIndex ?? '');
      if (serverIndex == null) {
        state.player.activeAudioTracks = [index];
        return;
      }

      if (isJellyfin) {
        final itemId = path.replaceFirst('jellyfin://', '');
        final provider = JellyfinTranscodeProvider();
        await provider.initialize();
        state.setJellyfinServerAudioSelection(itemId, serverIndex);
        await state.reloadCurrentJellyfinStream(
          quality: provider.currentVideoQuality,
          serverSubtitleIndex: state.getJellyfinServerSubtitleSelection(itemId),
          burnInSubtitle: state.getJellyfinServerSubtitleBurnIn(itemId),
          audioStreamIndex: serverIndex,
        );
      } else {
        final itemId = path.replaceFirst('emby://', '');
        final provider = EmbyTranscodeProvider();
        await provider.initialize();
        state.setEmbyServerAudioSelection(itemId, serverIndex);
        await state.reloadCurrentEmbyStream(
          quality: provider.currentVideoQuality,
          serverSubtitleIndex: state.getEmbyServerSubtitleSelection(itemId),
          burnInSubtitle: state.getEmbyServerSubtitleBurnIn(itemId),
          audioStreamIndex: serverIndex,
        );
      }
      return;
    }

    if (index < 0) {
      state.player.activeAudioTracks = [];
    } else {
      state.player.activeAudioTracks = [index];
    }
  }

  Future<void> _applyStreamingSettings(
    VideoPlayerState state, {
    required String key,
    required dynamic value,
  }) async {
    final path = state.currentVideoPath ?? '';
    final isJellyfin = path.startsWith('jellyfin://');
    final isEmby = path.startsWith('emby://');
    if (!isJellyfin && !isEmby) {
      return;
    }

    final jellyfinProvider = JellyfinTranscodeProvider();
    final embyProvider = EmbyTranscodeProvider();
    if (isJellyfin) {
      await jellyfinProvider.initialize();
    } else {
      await embyProvider.initialize();
    }

    var quality = isJellyfin
        ? jellyfinProvider.currentVideoQuality
        : embyProvider.currentVideoQuality;
    var transcodeEnabled = isJellyfin
        ? jellyfinProvider.transcodeEnabled
        : embyProvider.transcodeEnabled;
    int? subtitleIndex;
    bool burnIn;
    String itemId;

    if (isJellyfin) {
      itemId = path.replaceFirst('jellyfin://', '');
      subtitleIndex = state.getJellyfinServerSubtitleSelection(itemId);
      burnIn = state.getJellyfinServerSubtitleBurnIn(itemId);
    } else {
      itemId = path.replaceFirst('emby://', '');
      subtitleIndex = state.getEmbyServerSubtitleSelection(itemId);
      burnIn = state.getEmbyServerSubtitleBurnIn(itemId);
    }

    switch (key) {
      case 'stream.quality':
        quality = JellyfinVideoQuality.values.firstWhere(
          (q) => q.name == value?.toString(),
          orElse: () => quality,
        );
        break;
      case 'stream.transcodeEnabled':
        transcodeEnabled = _asBool(value, fallback: transcodeEnabled);
        break;
      case 'stream.subtitleIndex':
        subtitleIndex = _asNullableInt(value);
        break;
      case 'stream.burnInSubtitle':
        burnIn = _asBool(value, fallback: burnIn);
        break;
    }

    if (isJellyfin) {
      await jellyfinProvider.setTranscodeEnabled(transcodeEnabled);
      await jellyfinProvider.setDefaultVideoQuality(quality);
      state.setJellyfinServerSubtitleSelection(
        itemId,
        subtitleIndex,
        burnIn: burnIn,
      );
      await state.reloadCurrentJellyfinStream(
        quality: quality,
        serverSubtitleIndex: subtitleIndex,
        burnInSubtitle: burnIn,
      );
    } else {
      await embyProvider.setTranscodeEnabled(transcodeEnabled);
      await embyProvider.setDefaultVideoQuality(quality);
      state.setEmbyServerSubtitleSelection(
        itemId,
        subtitleIndex,
        burnIn: burnIn,
      );
      await state.reloadCurrentEmbyStream(
        quality: quality,
        serverSubtitleIndex: subtitleIndex,
        burnInSubtitle: burnIn,
      );
    }
  }

  Future<void> _sendDanmaku(
    VideoPlayerState state,
    Map<String, dynamic> args,
  ) async {
    final episodeId = state.episodeId;
    if (episodeId == null || episodeId <= 0) {
      throw StateError('当前视频未匹配到弹幕剧集，无法发送弹幕');
    }

    final comment = (args['comment']?.toString() ?? '').trim();
    if (comment.isEmpty) {
      throw ArgumentError('弹幕内容不能为空');
    }

    final time = _asDouble(
      args['time'],
      fallback: state.position.inSeconds.toDouble(),
    );
    final mode = _asInt(args['mode'], fallback: 1);
    final color = _parseRgbColorInt(args['color']);

    final result = await DandanplayService.sendDanmaku(
      episodeId: episodeId,
      time: time,
      mode: mode,
      color: color,
      comment: comment,
    );

    if (result['success'] != true) {
      throw StateError(result['message']?.toString() ?? '发送弹幕失败');
    }

    final dynamic danmakuFromServer = result['danmaku'];
    if (danmakuFromServer is Map<String, dynamic>) {
      state.addDanmakuToNewTrack(
        Map<String, dynamic>.from(danmakuFromServer),
        trackName: '遥控器',
      );
      return;
    }

    final colorText = _rgbToText(color);
    state.addDanmakuToNewTrack(
      {
        'time': time,
        'mode': mode,
        'color': colorText,
        'content': comment,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'pool': 0,
        'user': 'remote-controller',
      },
      trackName: '遥控器',
    );
  }

  Future<void> _setDanmakuBlockWords(
      VideoPlayerState state, dynamic value) async {
    final incoming = <String>[];
    if (value is List) {
      for (final item in value) {
        final text = item.toString().trim();
        if (text.isNotEmpty && !incoming.contains(text)) {
          incoming.add(text);
        }
      }
    } else if (value is String) {
      final decoded = _tryDecodeStringList(value);
      if (decoded != null) {
        incoming.addAll(decoded);
      }
    }

    final existing = List<String>.from(state.danmakuBlockWords);
    for (final word in existing) {
      if (!incoming.contains(word)) {
        await state.removeDanmakuBlockWord(word);
      }
    }
    for (final word in incoming) {
      if (!existing.contains(word)) {
        await state.addDanmakuBlockWord(word);
      }
    }
  }

  List<String>? _tryDecodeStringList(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        return decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}

    final fallback = raw
        .split(RegExp(r'[\n,;，；]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return fallback;
  }

  static String _toHexColor(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static String _trackLabel(String? title, String? language,
      {required String fallback}) {
    final titleText = (title ?? '').trim();
    final languageText = (language ?? '').trim();
    if (titleText.isNotEmpty && languageText.isNotEmpty) {
      return '$titleText ($languageText)';
    }
    if (titleText.isNotEmpty) {
      return titleText;
    }
    if (languageText.isNotEmpty) {
      return '$fallback ($languageText)';
    }
    return fallback;
  }

  static List<Map<String, dynamic>> _subtitleTrackOptions(
    List<Map<String, dynamic>> tracks,
  ) {
    final options = <Map<String, dynamic>>[
      {'value': null, 'label': '不指定'},
    ];
    for (final item in tracks) {
      final idx = item['index'];
      if (idx is! int) continue;
      final label = (item['display'] ?? item['title'] ?? '字幕 $idx').toString();
      options.add({'value': idx, 'label': label});
    }
    return options;
  }

  static int _asInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int? _asNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is String && value.trim().isEmpty) return null;
    if (value is String && value.toLowerCase() == 'null') return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double _asDouble(dynamic value, {required double fallback}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool _asBool(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) return fallback;
    if (text == 'true' || text == '1' || text == 'yes' || text == 'on') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no' || text == 'off') {
      return false;
    }
    return fallback;
  }

  static Color? _parseColor(dynamic value) {
    if (value is int) {
      final raw = value & 0xFFFFFFFF;
      if ((raw & 0xFF000000) == 0) {
        return Color(0xFF000000 | raw);
      }
      return Color(raw);
    }

    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;

    String normalized = text;
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    }
    if (normalized.startsWith('0x') || normalized.startsWith('0X')) {
      normalized = normalized.substring(2);
    }

    if (normalized.length == 6) {
      final rgb = int.tryParse(normalized, radix: 16);
      if (rgb == null) return null;
      return Color(0xFF000000 | rgb);
    }
    if (normalized.length == 8) {
      final argb = int.tryParse(normalized, radix: 16);
      if (argb == null) return null;
      return Color(argb);
    }
    return null;
  }

  static int _parseRgbColorInt(dynamic value) {
    final color = _parseColor(value);
    if (color == null) {
      return 0xFFFFFF;
    }
    final r = _channelToByte(color.r);
    final g = _channelToByte(color.g);
    final b = _channelToByte(color.b);
    return ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
  }

  static String _rgbToText(int color) {
    final r = (color >> 16) & 0xFF;
    final g = (color >> 8) & 0xFF;
    final b = color & 0xFF;
    return 'rgb($r,$g,$b)';
  }

  static int _channelToByte(double channel) {
    return (channel * 255.0).round().clamp(0, 255);
  }
}
