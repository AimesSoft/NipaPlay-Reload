import 'dart:async';

import 'package:fvp/mdk.dart' as mdk;
import 'package:nipa_harness/nipa_harness.dart';

Future<int?> probeMediaDuration(String path) async =>
    (await probeMediaInfo(path))['durationMs'] as int?;

Future<JsonMap> probeMediaInfo(String path) async {
  final player = mdk.Player();
  try {
    player.mute = true;
    player.media = path;
    final result = await player.prepare().timeout(const Duration(seconds: 15));
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
    return {'durationMs': null};
  } finally {
    await player.dispose();
  }
}
