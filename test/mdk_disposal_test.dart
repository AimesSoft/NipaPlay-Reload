import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';

class _NativePlayer extends Fake implements mdk.Player {
  final completion = Completer<void>();
  int disposals = 0;
  @override
  String media = '';
  @override
  Future<void> dispose() {
    disposals++;
    return completion.future;
  }
}

void main() {
  test('media changes reuse MDK and teardown waits for the native future once',
      () async {
    final native = _NativePlayer();
    final adapter = MdkPlayerAdapter.withPlayer(native);
    adapter.media = 'episode1.mkv';
    adapter.media = 'episode2.mkv';
    expect(native.media, 'episode2.mkv');
    expect(native.disposals, 0);
    final disposal = adapter.disposeAsync();
    adapter.dispose();
    expect(identical(disposal, adapter.disposeAsync()), isTrue);
    var completed = false;
    disposal.then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    native.completion.complete();
    await disposal;
    expect(native.disposals, 1);
    expect(() => adapter.media = 'episode3.mkv', throwsStateError);
  });

  test('native errors remain errors on repeated disposal', () async {
    final native = _NativePlayer();
    final adapter = MdkPlayerAdapter.withPlayer(native);
    final result = expectLater(adapter.disposeAsync(), throwsStateError);
    native.completion.completeError(StateError('native release failed'));
    await result;
    await expectLater(adapter.disposeAsync(), throwsStateError);
    expect(native.disposals, 1);
  });
}
