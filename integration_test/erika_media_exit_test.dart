import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_enums.dart';

import '../test/support/native_audio_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exit a stalled HTTP open and play another media on a fresh ID',
      (tester) async {
    final directory = await Directory.systemTemp.createTemp('erika_exit_');
    final media = await writeNativeAudioFixture(directory);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requested = Completer<void>();
    final releaseServer = Completer<void>();
    server.listen((request) async {
      if (!requested.isCompleted) requested.complete();
      await releaseServer.future;
      try {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } on IOException {
        // A host which cancelled the open has already closed the connection.
      }
    });

    const timeout = Duration(seconds: 15);
    final old = ErikaPlayerAdapter()
      ..media = 'http://127.0.0.1:${server.port}/slow.wav';
    final oldOpen = old.prepare().then<void>((_) {}, onError: (Object _) {});
    var current = old;
    try {
      await requested.future.timeout(timeout);
      current = old.retireMediaAfterExit();
      expect(current, isNot(same(old)));
      expect(current.position, 0);
      current.media = media.path;
      await current.prepare().timeout(timeout);
      await current.seekAndWait(position: 250).timeout(timeout);
      expect(current.state, PlayerPlaybackState.paused);
      expect(current.position, 250);
    } finally {
      releaseServer.complete();
      await server.close(force: true);
      try {
        await Future.wait([oldOpen, old.disposeAsync(), current.disposeAsync()])
            .timeout(timeout);
      } finally {
        await directory.delete(recursive: true);
      }
    }
  }, skip: !Platform.isMacOS);
}
