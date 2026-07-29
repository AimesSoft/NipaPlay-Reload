import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';

class _ControlledSeekDelegate extends Fake
    implements AbstractPlayer, AsyncSeekPlayer {
  final Completer<void> seekCompleter = Completer<void>();
  int? requestedPosition;

  @override
  Future<void> seekAndWait({required int position}) {
    requestedPosition = position;
    return seekCompleter.future;
  }
}

class _SynchronousSeekDelegate extends Fake implements AbstractPlayer {
  int? requestedPosition;

  @override
  void seek({required int position}) {
    requestedPosition = position;
  }
}

void main() {
  test('Player forwards the asynchronous seek completion contract', () async {
    final delegate = _ControlledSeekDelegate();
    final player = Player.withDelegate(delegate);
    var completed = false;

    final seek = player.seekAndWait(position: 12345).then((_) {
      completed = true;
    });

    expect(delegate.requestedPosition, 12345);
    expect(completed, isFalse);

    delegate.seekCompleter.complete();
    await seek;
    expect(completed, isTrue);
  });

  test('Player keeps the legacy synchronous seek behavior as fallback',
      () async {
    final delegate = _SynchronousSeekDelegate();
    final player = Player.withDelegate(delegate);

    await player.seekAndWait(position: 6789);

    expect(delegate.requestedPosition, 6789);
  });
}
