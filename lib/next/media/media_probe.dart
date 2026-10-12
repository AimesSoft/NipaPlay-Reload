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
    final duration = player.mediaInfo.duration;
    return {
      'durationMs': result < 0 || duration <= 0 ? null : duration,
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
