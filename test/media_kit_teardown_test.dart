import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';

/// The mpv side of the player: records every read and write that reaches it.
class _Native extends Fake implements NativePlayer {
  final calls = <String>[];

  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    calls.add('get $property');
    return '0';
  }

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    calls.add('set $property');
  }
}

class _Streams extends Fake implements PlayerStream {
  final durations = StreamController<Duration>.broadcast(sync: true);
  final trackLists = StreamController<Tracks>.broadcast(sync: true);

  @override
  Stream<Duration> get duration => durations.stream;
  @override
  Stream<Tracks> get tracks => trackLists.stream;
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<VideoParams> get videoParams => const Stream.empty();
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Track> get track => const Stream.empty();
  @override
  Stream<String> get error => const Stream.empty();
  @override
  Stream<PlayerLog> get log => const Stream.empty();
}

class _Player extends Fake implements Player {
  _Player(this.platform);

  @override
  PlatformPlayer? platform;
  final _Streams events = _Streams();
  final teardown = Completer<void>();
  int opens = 0;

  @override
  PlayerState get state => const PlayerState();
  @override
  PlayerStream get stream => events;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opens++;
  }

  @override
  Future<void> dispose() => teardown.future;
}

void main() {
  test('a player being torn down stays torn down when its media is cleared',
      () async {
    final native = _Native();
    final player = _Player(native);
    final adapter = MediaKitPlayerAdapter.withPlayer(player);
    var disposed = false;
    final disposal = adapter.disposeAsync().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);

    // A Classic hot swap clears the media 50 ms after teardown began, while
    // mpv, stopped inside dispose, reports no duration and no tracks. A media
    // change schedules its own reads half a second and a second later.
    adapter.media = '';
    player.events.durations.add(Duration.zero);
    player.events.trackLists.add(const Tracks());
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(player.opens, 0);
    expect(native.calls, isEmpty);
    expect(disposed, isFalse);

    player.teardown.complete();
    await disposal;
  });
}
