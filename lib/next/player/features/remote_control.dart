import 'package:nipaplay/next/capabilities/playback_capability.dart';

import '../next_playback.dart';

/// The remote protocol reads the same Dart snapshot and sends the same
/// commands as Next's controls. It never reads Classic's player state.
final class NextRemoteControl {
  const NextRemoteControl(this.playback, {this.setParameter, this.sendDanmaku});
  final NextPlayback playback;
  final Future<void> Function(String key, Object? value)? setParameter;
  final Future<void> Function(Map<String, dynamic> input)? sendDanmaku;

  Future<Map<String, dynamic>> payload(
      {required bool enabled,
      bool includeParameters = false,
      String? paneId}) async {
    final state = playback.snapshot();
    final chapters = includeParameters && state.hasVideo
        ? await playback.inspection.inspect('playback.chapters', {})
        : const <String, Object?>{};
    final snapshot = <String, dynamic>{
      ...state.toJson(),
      'isPaused': state.paused,
      'currentVideoPath': state.path,
      'animeTitle': state.seriesTitle,
      'playbackRate': state.rate,
      'progress': state.durationMs == null || state.durationMs == 0
          ? 0
          : (state.positionMs ?? 0) / state.durationMs!,
      'canPlayPreviousEpisode': state.canPrevious,
      'canPlayNextEpisode': state.canNext,
    };
    return {
      'receiverEnabled': enabled,
      'available': true,
      'message': enabled ? 'ok' : '被遥控端已关闭',
      'snapshot': snapshot,
      'menus': [
        for (final pane in state.external == null
            ? ['volume', 'playbackRate', 'chapters']
            : <String>[])
          {
            'paneId': pane,
            'category': 'playback',
            'icon': 'play_arrow',
            'title': switch (pane) {
              'volume' => '音量',
              'chapters' => '章节',
              _ => '播放速度'
            }
          }
      ],
      'parameters': includeParameters && state.external == null
          ? [
              if (paneId == null || paneId == 'volume')
                {
                  'paneId': 'volume',
                  'key': 'player.volume',
                  'label': '音量',
                  'type': 'double',
                  'step': 0.05,
                  'value': state.volume,
                  'min': 0,
                  'max': 1
                },
              if (paneId == null || paneId == 'playbackRate')
                {
                  'paneId': 'playbackRate',
                  'key': 'playback.rate',
                  'label': '播放速度',
                  'type': 'double',
                  'step': 0.05,
                  'value': state.rate,
                  'min': 0.01,
                  'max': 5
                },
              if ((paneId == null || paneId == 'chapters') && state.hasVideo)
                {
                  'paneId': 'chapters',
                  'key': 'playback.chapter',
                  'label': '章节',
                  'type': 'select',
                  'value': chapters['index'],
                  'options': [
                    for (final (i, chapter)
                        in ((chapters['items'] as List?) ?? const []).indexed)
                      {'value': i, 'label': (chapter as Map)['title']}
                  ],
                },
            ]
          : const <Map<String, dynamic>>[],
    };
  }

  Future<void> execute(String command, Map<String, dynamic> args) async {
    final p = playback;
    final state = p.snapshot();
    if (state.external != null) {
      throw StateError('在外部播放器中播放，NipaPlay 无法控制播放。');
    }
    switch (command) {
      case 'toggle_play_pause':
        await p.port.setPaused(p.playIntent);
      case 'seek_by_seconds':
        final raw = args['seconds'];
        final seconds = raw is num ? raw.toDouble() : double.tryParse('$raw');
        if (seconds == null || !seconds.isFinite) {
          throw ArgumentError('seconds 必须是数字');
        }
        await p.port.seekTo(Duration(
            milliseconds: (state.positionMs ?? 0) + (seconds * 1000).round()));
      case 'toggle_playback_rate':
        await p.setRate(p.rate == 1 ? 2 : 1);
      case 'play_previous_episode':
        await p.port.switchEpisode(EpisodeDirection.previous);
      case 'play_next_episode':
        await p.port.switchEpisode(EpisodeDirection.next);
      case 'skip':
        await p.skip();
      case 'send_danmaku':
        final send = sendDanmaku;
        if (send == null) throw StateError('当前会话没有弹幕发送入口');
        await send(args);
      case 'set_parameter':
        final key = args['key']?.toString() ?? '';
        final value = args['value'];
        if (key == 'playback.chapter') {
          await p.inspection
              .inspect('playback.navigate', {'chapterIndex': value});
        } else if (key == 'playback.audioTrack' ||
            key == 'audio.activeTrackIndex') {
          await p.controls.selectTrack(
              {'kind': 'audio', 'origin': 'embedded', 'index': value});
        } else if (key == 'playback.subtitleTrack' ||
            key == 'subtitle.activeTrackIndex') {
          await p.controls.selectTrack(
              {'kind': 'subtitle', 'origin': 'embedded', 'index': value});
        } else if (setParameter case final set?) {
          await set(key, value);
          if (key == 'player.volume' && value is num) {
            await p.setVolume(value.toDouble());
          }
          if (key == 'playback.rate' && value is num) {
            await p.setRate(value.toDouble());
          }
        } else if (key == 'player.volume' && value is num) {
          await p.setVolume(value.toDouble());
        } else if (key == 'playback.rate' && value is num) {
          await p.setRate(value.toDouble());
        } else {
          throw ArgumentError('未知参数: $key');
        }
      default:
        throw ArgumentError('未知命令: $command');
    }
  }
}
