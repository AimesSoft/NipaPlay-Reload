import 'dart:async';
import 'dart:io';
import 'probe_process.dart';

import 'package:fvp/mdk.dart' as mdk;
import 'package:nipa_harness/nipa_harness.dart';

Future<int?> probeMediaDuration(String path) async =>
    (await probeMediaInfo(path))['durationMs'] as int?;

Future<void>? _pendingProbeCleanup;

Future<JsonMap> probeMediaInfo(String path,
    {Future<void>? stopRequested}) async {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return mediaProbeProcess.run(path, stopRequested: stopRequested);
  }
  // A timed-out native teardown still owns its player. Do not accumulate more
  // players while it is stuck, or report missing technical data as success.
  if (_pendingProbeCleanup != null) {
    throw const Failure(FailureCode.unavailable,
        'Previous media probe is still releasing its native player.');
  }
  final player = mdk.Player();
  try {
    player.mute = true;
    player.media = path;
    final result = await Future.any<int>([
      player.prepare(),
      if (stopRequested != null) stopRequested.then((_) => -1),
    ]).timeout(const Duration(seconds: 15));
    final info = player.mediaInfo;
    final duration = info.duration;
    return {
      'durationMs': result < 0 || duration <= 0 ? null : duration,
      if (result >= 0)
        'technical': {
          'container': info.format,
          if (info.bitRate > 0) 'bitrate': info.bitRate,
          'video': [
            for (final stream in info.video ?? <mdk.VideoStreamInfo>[])
              {
                'codec': stream.codec.codec,
                'width': stream.codec.width,
                'height': stream.codec.height,
                'fps': stream.codec.frameRate,
                'pixelFormat': stream.codec.formatName,
                if (stream.codec.bitRate > 0) 'bitrate': stream.codec.bitRate,
                'colorSpace': stream.codec.colorSpace.name,
              }
          ],
          'audio': [
            for (final stream in info.audio ?? <mdk.AudioStreamInfo>[])
              {
                'codec': stream.codec.codec,
                'channels': stream.codec.channels,
                'sampleRate': stream.codec.sampleRate,
                'language': stream.metadata['language'],
                'title': stream.metadata['title'],
                if (stream.codec.bitRate > 0) 'bitrate': stream.codec.bitRate,
              }
          ],
        },
      if (result >= 0)
        'subtitles': [
          for (final entry in (player.mediaInfo.subtitle ?? []).asMap().entries)
            {
              'index': entry.key,
              'streamIndex': entry.value.index,
              'language': entry.value.metadata['language'] ?? 'und',
              'title': entry.value.metadata['title'],
              'format': entry.value.codec.codec,
            }
        ],
    };
  } on TimeoutException {
    throw Failure(FailureCode.unavailable,
        'Media probe timed out after 15 seconds: $path');
  } finally {
    final cleanup = player.dispose();
    _pendingProbeCleanup = cleanup;
    unawaited(cleanup.then<void>((_) {
      if (identical(_pendingProbeCleanup, cleanup)) _pendingProbeCleanup = null;
    }, onError: (Object _, StackTrace __) {
      // Failed cleanup retains ownership; another probe must not pile on.
    }));
    try {
      await cleanup.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw Failure(FailureCode.unavailable,
          'Media probe player release timed out after 5 seconds: $path');
    }
  }
}
