import 'dart:async';

import 'package:fvp/mdk.dart' as mdk;

Future<int?> probeMediaDuration(String path) async {
  final player = mdk.Player();
  try {
    player.mute = true;
    player.media = path;
    final result = await player.prepare().timeout(const Duration(seconds: 15));
    final duration = player.mediaInfo.duration;
    return result < 0 || duration <= 0 ? null : duration;
  } on TimeoutException {
    return null;
  } finally {
    await player.dispose();
  }
}
