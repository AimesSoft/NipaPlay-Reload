import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/downloads/progress_observations.dart';

/// #1120: the headless engine reported no time without progress, so
/// `download.stalled` never came. Desktop and headless now say it the same
/// way, from this.
void main() {
  final t0 = DateTime.utc(2026, 11, 17, 2);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  test('only bytes that grow are progress', () {
    final o = ProgressObservations();
    var h = o.observe('1', 'hash|/out', 100, now: at(0));
    expect(h['secondsWithoutProgress'], 0);
    expect(h['lastProgressAt'], isNull);
    expect(h['observingSince'], at(0).toIso8601String());
    // Reports and keepalives with the same count are not progress.
    h = o.observe('1', 'hash|/out', 100, now: at(200));
    expect(h['secondsWithoutProgress'], 200);
    expect(h['lastProgressAt'], isNull);
    h = o.observe('1', 'hash|/out', 150, now: at(310));
    expect(h['secondsWithoutProgress'], 0);
    expect(h['lastProgressAt'], at(310).toIso8601String());
    expect(h['checkedBytesChange'], 50);
    expect(h['sampleSeconds'], 110);
    // A recheck that counts fewer bytes is not progress either.
    h = o.observe('1', 'hash|/out', 120, now: at(400));
    expect(h['secondsWithoutProgress'], 90);
    expect(h['lastProgressAt'], at(310).toIso8601String());
  });

  test('a removed task is forgotten; a new session of it starts afresh', () {
    final o = ProgressObservations();
    o.observe('1', 'hash|/out', 100, now: at(0));
    o.observe('2', 'other|/out', 5, now: at(0));
    expect(o.length, 2);
    o.forget('1');
    expect(o.length, 1);
    final h = o.observe('3', 'hash|/out', 100, now: at(500));
    expect(h['observingSince'], at(500).toIso8601String());
    expect(h['secondsWithoutProgress'], 0);
  });

  test('a handle that names another task drops the old observation', () {
    final o = ProgressObservations();
    o.observe('1', 'hash|/a', 1, now: at(0));
    o.observe('1', 'hash|/b', 1, now: at(1));
    expect(o.length, 1);
  });

  test('peer counts come from the live snapshot when there is one', () {
    expect(
        peerHealth({
          'live': {
            'snapshot': {
              'peer_stats': {
                'live': 2,
                'seen': 9,
                'connecting': 1,
                'queued': 3,
                'dead': 4
              }
            }
          }
        }),
        {
          'connectedPeers': 2,
          'seenPeers': 9,
          'connectingPeers': 1,
          'queuedPeers': 3,
          'deadPeers': 4
        });
    expect(peerHealth(null)['connectedPeers'], isNull);
    expect(peerHealth({'live': null})['deadPeers'], isNull);
  });
}
