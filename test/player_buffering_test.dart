import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';

class _BufferingDelegate extends Fake
    implements AbstractPlayer, BufferingAwarePlayer {
  @override
  final ValueNotifier<bool> buffering = ValueNotifier<bool>(false);
  @override
  PlayerPlaybackState state = PlayerPlaybackState.playing;
}

class _LegacyDelegate extends Fake implements AbstractPlayer {}

void main() {
  test('buffer events preserve play intent and are available synchronously',
      () {
    final delegate = _BufferingDelegate();
    final player = Player.withDelegate(delegate);
    final changes = <bool>[];
    player.buffering.addListener(() => changes.add(player.isBuffering));

    delegate.buffering.value = true;
    expect(player.isBuffering, isTrue);
    expect(player.state, PlaybackState.playing);
    delegate.buffering.value = false;
    expect(player.state, PlaybackState.playing);
    expect(changes, [true, false]);

    delegate.state = PlayerPlaybackState.paused;
    delegate.buffering.value = true;
    delegate.buffering.value = false;
    expect(player.state, PlaybackState.paused);
    delegate.buffering.dispose();
  });

  test('backends without the capability keep their previous behavior', () {
    final player = Player.withDelegate(_LegacyDelegate());
    expect(player.isBuffering, isFalse);
    expect(player.buffering, same(player.buffering));
  });
}
