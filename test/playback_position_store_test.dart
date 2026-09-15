import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/playback_position_store.dart';

void main() {
  test('overlapping saves retain other files and a later backward seek',
      () async {
    var disk = '{"existing":400}';
    final firstWrite = Completer<void>();
    final releaseWrite = Completer<void>();
    final written = <String>[];
    final store = PlaybackPositionStore(
        read: () async => disk,
        write: (value) async {
          written.add(value);
          if (written.length == 1) {
            firstWrite.complete();
            await releaseWrite.future;
          }
          disk = value;
        });
    final first = store.save('videoA', 2000);
    await firstWrite.future;
    final second = store.save('videoB', 3000);
    final rewind = store.save('videoA', 500);
    var flushed = false;
    final flush = store.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(flushed, isFalse);
    expect(written, hasLength(1));
    releaseWrite.complete();
    await Future.wait([first, second, rewind, flush]);
    expect(jsonDecode(disk), {'existing': 400, 'videoA': 500, 'videoB': 3000});
  });

  test('failed write does not discard existing entries or poison the queue',
      () async {
    var disk = '{"old":100}';
    var fail = true;
    final store = PlaybackPositionStore(
        read: () async => disk,
        write: (value) async {
          if (fail) {
            fail = false;
            throw StateError('disk unavailable');
          }
          disk = value;
        });
    await expectLater(store.save('new', 200), throwsStateError);
    await store.save('next', 300);
    await store.flush();
    expect(jsonDecode(disk), {'old': 100, 'next': 300});
  });
}
