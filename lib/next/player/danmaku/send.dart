import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/danmaku_matching_service.dart';

import '../ports/session_playback.dart';

/// `danmaku.send` for Next's session: publishes one comment to the episode
/// the session plays, through the same Dandanplay service Classic uses, then
/// echoes it on a local track of this session. [text], [mode] and [color]
/// are validated by the caller.
Future<JsonMap> sendSessionDanmaku(SessionPlayback playback,
    {required String text, required String mode, required String color}) async {
  final session = playback.session;
  final snapshot = playback.port.snapshot();
  final episodeId = snapshot.episodeId;
  if (session == null || session.phase.value.done || !playback.hasVideo ||
      episodeId == null) {
    throw const Failure(FailureCode.unavailable,
        'An identified internal video is required.');
  }
  if (!DandanplayService.isLoggedIn) {
    throw const Failure(FailureCode.unavailable,
        'Complete Dandanplay login through accounts.login first.');
  }
  final id = session.id;
  final time = playback.position.inSeconds.toDouble();
  final result = await DanmakuMatchingService.instance.sendDanmaku(
      episodeId: episodeId,
      time: time,
      mode: switch (mode) { 'top' => 5, 'bottom' => 4, _ => 1 },
      color: int.parse(color.substring(1), radix: 16),
      comment: text);
  if (result['success'] != true || result['danmaku'] is! Map) {
    throw const Failure(
        FailureCode.unavailable, 'Dandanplay did not acknowledge the comment.');
  }
  // The answer may come after the video was closed or replaced.
  final echo = playback.session?.id == id &&
      !(playback.session?.phase.value.done ?? true);
  if (echo) {
    playback.danmaku.echo(Map<String, dynamic>.from(result['danmaku'] as Map));
  }
  return {
    'sent': true,
    'localEcho': echo,
    'episodeId': episodeId,
    'timeSeconds': time,
    'mode': mode,
    'color': color
  };
}
