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
  mdk.MediaStatus mediaStatus = const mdk.MediaStatus(mdk.MediaStatus.loaded);
  bool Function(mdk.MediaStatus, mdk.MediaStatus)? statusCallback;

  @override
  void onMediaStatus(
    bool Function(mdk.MediaStatus, mdk.MediaStatus)? callback, {
    bool reply = false,
  }) {
    statusCallback = callback;
  }

  void emitStatus(int flags) {
    final oldStatus = mediaStatus;
    mediaStatus = mdk.MediaStatus(flags);
    statusCallback?.call(oldStatus, mediaStatus);
  }

  @override
  Future<void> dispose() {
    disposals++;
    return completion.future;
  }
}

void main() {
  test('OHOS MDK status streams forward changes and cancel on teardown',
      () async {
    final source = StreamController<
        ({mdk.MediaStatus oldValue, mdk.MediaStatus newValue})>(sync: true);
    final statuses = <mdk.MediaStatus>[];
    final subscription = listenMdkMediaStatus(source.stream, statuses.add);
    final buffering = const mdk.MediaStatus(mdk.MediaStatus.buffering);
    final buffered = const mdk.MediaStatus(mdk.MediaStatus.buffered);
    source.add((oldValue: buffered, newValue: buffering));
    source.add((oldValue: buffering, newValue: buffered));
    expect(statuses, [buffering, buffered]);
    await subscription!.cancel();
    source.add((oldValue: buffered, newValue: buffering));
    expect(statuses, [buffering, buffered]);
    await source.close();
  });

  test('MDK buffering follows native status and ignores post-dispose events',
      () async {
    final native = _NativePlayer();
    final adapter = MdkPlayerAdapter.withPlayer(native);
    final changes = <bool>[];
    adapter.buffering.addListener(() => changes.add(adapter.buffering.value));

    native.emitStatus(mdk.MediaStatus.loaded | mdk.MediaStatus.buffering);
    native.emitStatus(mdk.MediaStatus.loaded | mdk.MediaStatus.buffering);
    expect(adapter.buffering.value, isTrue);
    native.emitStatus(mdk.MediaStatus.loaded | mdk.MediaStatus.buffered);
    expect(changes, [true, false]);

    final disposal = adapter.disposeAsync();
    expect(() => native.emitStatus(mdk.MediaStatus.buffering), returnsNormally);
    native.completion.complete();
    await disposal;
  });

  test('MDK samples buffering already active when the adapter attaches',
      () async {
    final native = _NativePlayer()
      ..mediaStatus = const mdk.MediaStatus(mdk.MediaStatus.buffering);
    final adapter = MdkPlayerAdapter.withPlayer(native);
    expect(adapter.buffering.value, isTrue);
    adapter.media = 'new-episode.mkv';
    expect(adapter.buffering.value, isFalse);
    native.completion.complete();
    await adapter.disposeAsync();
  });

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
