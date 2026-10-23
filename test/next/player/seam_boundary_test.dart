import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Next reaches Classic's player only through NextPlayback: the
/// Classic-backed implementation (lib/next/player/classic/) is the one
/// place that names VideoPlayerState, besides the settings registry, which
/// applies the setting keys Classic and Next share.
void main() {
  test('only the Classic-backed playback names VideoPlayerState', () {
    const allowed = {
      'lib/next/settings/application_settings.dart',
      'lib/next/settings/effective.dart',
    };
    final offenders = [
      for (final file in Directory('lib/next')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (!file.path.startsWith('lib/next/player/classic/') &&
            !allowed.contains(file.path) &&
            RegExp(r'video_player_state|VideoPlayerState\b')
                .hasMatch(file.readAsStringSync()
                    .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')))
          file.path
    ];
    expect(offenders, isEmpty);
  });
}
