import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/external_player_session/vlc_session.dart';

void main() {
  test('launches and terminates a Linux VLC session process', () async {
    if (!Platform.isLinux) return;
    const playerPath = '/usr/bin/vlc';
    const mediaPath = '/usr/share/sounds/gnome/default/alarms/sonar.oga';
    if (!File(playerPath).existsSync() || !File(mediaPath).existsSync()) return;

    final session = VlcSession(
      playerPath: playerPath,
      mediaPath: mediaPath,
      extraArgs: const [
        '--intf=dummy',
        '--aout=dummy',
        '--no-one-instance',
        '--loop',
      ],
    );

    await session.launch();
    try {
      expect(session.type, ExternalPlayerType.vlc);
      expect(session.processId, greaterThan(0));
      expect(session.isClosed, isFalse);

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (session.duration <= Duration.zero && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(session.duration, greaterThan(Duration.zero));

      session.togglePause();
      final pauseDeadline =
          DateTime.now().add(const Duration(seconds: 2));
      while (session.isPaused != true && DateTime.now().isBefore(pauseDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(session.isPaused, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(session.isPaused, isTrue);

      session.seekToFraction(0.5);
      expect(session.position, isNotNull);
    } finally {
      session.terminate();
      session.dispose();
    }
  });
}
