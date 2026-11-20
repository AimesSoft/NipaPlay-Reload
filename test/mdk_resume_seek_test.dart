import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';

/// MDK answers each seek through its callback; the test answers by hand.
class _NativePlayer extends Fake implements mdk.Player {
  @override
  mdk.MediaStatus mediaStatus = const mdk.MediaStatus(mdk.MediaStatus.loaded);
  bool Function(mdk.MediaStatus, mdk.MediaStatus)? statusCallback;
  final seeks = <int>[];
  final answers = <Completer<int>>[];

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
  Future<int> seek({
    required int position,
    mdk.SeekFlag flags = const mdk.SeekFlag(mdk.SeekFlag.defaultFlags),
  }) {
    seeks.add(position);
    final answer = Completer<int>();
    answers.add(answer);
    return answer.future;
  }

  @override
  Future<void> dispose() async {}
}

const _prepared = mdk.MediaStatus.loaded | mdk.MediaStatus.prepared;

void main() {
  test('a resume seek MDK cancels for a seek of its own is asked again once '
      'that seek is done', () async {
    final native = _NativePlayer();
    final adapter = MdkPlayerAdapter.withPlayer(native);
    // An active-track change has MDK seeking to the current position.
    native.emitStatus(_prepared | mdk.MediaStatus.seeking);
    var done = false;
    final resume =
        adapter.seekAndWait(position: 453083).then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(native.seeks, [453083]);

    native.answers[0].complete(-2);
    await Future<void>.delayed(Duration.zero);
    expect(native.seeks, [453083], reason: 'MDK is still seeking');

    native.emitStatus(_prepared);
    await Future<void>.delayed(Duration.zero);
    expect(native.seeks, [453083, 453083]);
    expect(done, isFalse);

    native.answers[1].complete(453083);
    await resume;
    expect(done, isTrue);
  });

  test('a resume seek MDK takes is asked once', () async {
    final native = _NativePlayer();
    final adapter = MdkPlayerAdapter.withPlayer(native);
    final resume = adapter.seekAndWait(position: 120000);
    await Future<void>.delayed(Duration.zero);
    native.answers.single.complete(121500);
    await resume;
    expect(native.seeks, [120000]);
  });

  test('a resume seek is not asked again once another position was asked for',
      () async {
    final native = _NativePlayer();
    final adapter = MdkPlayerAdapter.withPlayer(native);
    final resume = adapter.seekAndWait(position: 300000);
    await Future<void>.delayed(Duration.zero);
    adapter.seek(position: 5000);
    native.answers[0].complete(-2);
    await resume;
    expect(native.seeks, [300000, 5000]);
  });
}
