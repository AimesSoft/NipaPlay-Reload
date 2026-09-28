import 'dart:io';
import 'dart:ffi';
import 'package:media_kit/generated/libmpv/bindings.dart' as native;
import 'package:media_kit/src/player/native/core/initializer_isolate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'support/native_audio_fixture.dart';

void main() {
  final library = Platform.environment['NIPAPLAY_TEST_NATIVE_MPV'];
  test('native libmpv repeatedly waits for complete disposal', () async {
    MediaKit.ensureInitialized(libmpv: library);
    final dir = await Directory.systemTemp.createTemp('mpv_native_');
    final file = await writeNativeAudioFixture(dir);
    addTearDown(() => dir.delete(recursive: true));
    for (var i = 0; i < 6; i++) {
      final player = Player(
          configuration: const PlayerConfiguration(vo: 'null', osc: false));
      await player.open(Media(file.path), play: false);
      await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5));
      await player.dispose().timeout(const Duration(seconds: 10));
    }
  }, skip: library == null ? 'Requires the platform libmpv binary' : false);
  test('libmpv event isolate acknowledges shutdown before handle deletion', () async {
    MediaKit.ensureInitialized(libmpv: library);
    final bindings = native.MPV(DynamicLibrary.open(library!));
    for (var i = 0; i < 3; i++) {
      final initializer = InitializerIsolate();
      final handle = await initializer.create((_) async {}, options: {'vo': 'null', 'ao': 'null'});
      await initializer.dispose(bindings, handle).timeout(const Duration(seconds: 5));
      bindings.mpv_terminate_destroy(handle);
    }
  }, skip: library == null ? 'Requires the platform libmpv binary' : false);

}
