import 'dart:async';
import 'dart:io';
import 'support/native_audio_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:fvp/src/fvp_platform_interface.dart';

class _Textures extends FvpPlatform {
  int releases = 0;
  @override
  Future<void> releaseTexture(int playerHandle, int textureId) async {
    releases++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = Platform.environment['NIPAPLAY_TEST_NATIVE_MDK'] == '1';
  group('native MDK teardown', () {
    test('idle player releases texture without waiting for video size',
        () async {
      final textures = _Textures();
      FvpPlatform.instance = textures;
      final player = mdk.Player();
      player.textureId.value = 7;
      await player.updateTexture(width: -1).timeout(const Duration(seconds: 2));
      expect(textures.releases, 1);
      final pendingTexture = player.updateTexture();
      final first = player.dispose();
      expect(identical(first, player.dispose()), isTrue);
      await first.timeout(const Duration(seconds: 5));
      expect(await pendingTexture, -1);
    });

    test('loaded media and reply callbacks can be destroyed repeatedly',
        () async {
      final dir = await Directory.systemTemp.createTemp('mdk_native_');
      final file = await writeNativeAudioFixture(dir);
      try {
        for (var i = 0; i < 6; i++) {
          final player = mdk.Player();
          player.onStateChanged((_, __) {}, reply: true);
          player.onMediaStatus((_, __) => true, reply: true);
          player.media = file.path;
          await player.prepare().timeout(const Duration(seconds: 5));
          expect(player.mediaInfo.duration, greaterThan(0));
          await player.dispose().timeout(const Duration(seconds: 5));
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });
  },
      skip: !enabled
          ? 'Requires built MDK and patched fvp native libraries'
          : false);
}
