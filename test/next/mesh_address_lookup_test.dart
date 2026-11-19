import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/mesh/address_lookup.dart';

void main() {
  late DateTime now;
  late Map<String, List<JsonMap>> cache;
  late MeshAddressLookup lookup;
  late Future<JsonMap> Function(String) answer;
  var calls = 0;
  var changes = 0;
  JsonMap address(int port) => {
        'candidates': [
          {'host': '127.0.0.1', 'port': port}
        ]
      };

  setUp(() {
    now = DateTime.utc(2026);
    cache = {};
    calls = 0;
    changes = 0;
    answer = (_) async => address(1000);
    lookup = MeshAddressLookup(
        cache: cache,
        baseDelay: const Duration(seconds: 30),
        maxDelay: const Duration(minutes: 10),
        now: () => now,
        onChanged: () => changes++,
        request: (peer) {
          calls++;
          return answer(peer);
        });
  });

  test(
      'concurrent requests share one query; stopped replies do not repopulate cache',
      () async {
    final reply = Completer<JsonMap>();
    answer = (_) => reply.future;
    final first = lookup.resolve('peer');
    final second = lookup.resolve('peer');
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    lookup.reset();
    reply.complete(address(1000));
    expect(await first, isEmpty);
    expect(cache, isEmpty);
    expect(changes, 0);
  });

  test('unavailable service cools all peers, then an old address can recover',
      () async {
    cache['peer'] = (address(1000)['candidates'] as List).cast<JsonMap>();
    answer = (_) async => throw const Failure(
        FailureCode.unavailable, 'offline',
        retryable: true);
    expect((await lookup.resolve('peer')).single['port'], 1000);
    expect(await lookup.resolve('uncached-peer'), isEmpty);
    expect(calls, 1);
    lookup.refresh(['peer']);
    await lookup.resolve('peer');
    expect(calls, 1, reason: 'refresh respects the failure cooldown');
    now = now.add(const Duration(seconds: 31));
    answer = (_) async => address(2000);
    expect((await lookup.resolve('peer')).single['port'], 2000);
    expect(calls, 2);
    expect(lookup.failure, isNull);
  });

  test('manual refresh and a concurrent success cannot bypass shared 429',
      () async {
    final success = Completer<JsonMap>();
    answer = (peer) async {
      if (peer == 'other') return success.future;
      throw const Failure(FailureCode.unavailable, 'rate_limited',
          retryable: true,
          details: {'httpStatus': 429, 'retryAfterSeconds': 120});
    };
    final other = lookup.resolve('other');
    await lookup.resolve('peer');
    success.complete(address(1000));
    await other;
    lookup.coordinatorReached();
    lookup.refresh(['peer', 'other']);
    now = now.add(const Duration(seconds: 119));
    await lookup.resolve('peer');
    await lookup.resolve('third');
    expect(calls, 2);
    now = now.add(const Duration(seconds: 2));
    answer = (_) async => address(2000);
    expect((await lookup.resolve('peer')).single['port'], 2000);
    expect(calls, 3);
  });

  test(
      'ordinary offline peers keep ten-minute backoff; explicit refresh can requery',
      () async {
    await lookup.resolve('peer');
    for (var i = 0; i < 6; i++) {
      now = now.add(const Duration(minutes: 10));
      await lookup.resolve('peer');
    }
    final previous = calls;
    now = now.add(const Duration(minutes: 2));
    answer = (_) async => address(2000);
    expect((await lookup.resolve('peer')).single['port'], 1000);
    expect(calls, previous);
    lookup.refresh(['peer']);
    expect((await lookup.resolve('peer')).single['port'], 2000);
    expect(calls, previous + 1);
  });

  test('confirmed control-plane recovery releases only transient query cooldown', () async {
    answer = (_) async => throw const Failure(
        FailureCode.unavailable, 'unreachable', retryable: true);
    await lookup.resolve('peer');
    lookup.coordinatorReached();
    answer = (_) async => address(2000);
    expect((await lookup.resolve('peer')).single['port'], 2000);
    expect(calls, 2);
  });

  test('a peer-specific refusal does not suppress other peers', () async {
    answer = (peer) async {
      if (peer == 'missing')
        throw const Failure(FailureCode.unavailable, 'missing',
            details: {'httpStatus': 404});
      return address(1000);
    };
    await lookup.resolve('missing');
    await lookup.resolve('missing');
    expect((await lookup.resolve('present')).single['port'], 1000);
    expect(calls, 2);
  });

  group('when a shared cooldown runs out (#1101)', () {
    late List<(Duration, void Function())> timers;
    late int ended;
    setUp(() {
      timers = [];
      ended = 0;
      lookup = MeshAddressLookup(
          cache: cache,
          baseDelay: const Duration(seconds: 30),
          maxDelay: const Duration(minutes: 10),
          now: () => now,
          onChanged: () => changes++,
          onCooldownEnded: () => ended++,
          schedule: (delay, callback) {
            timers.add((delay, callback));
            return Timer(const Duration(days: 1), () {});
          },
          request: (peer) {
            calls++;
            return answer(peer);
          });
    });
    Failure limited(int seconds) => Failure(
        FailureCode.unavailable, 'rate_limited',
        retryable: true,
        details: {'httpStatus': 429, 'retryAfterSeconds': seconds});

    test('it is told once, and the next ask finds the new address', () async {
      cache['peer'] = (address(1000)['candidates'] as List).cast<JsonMap>();
      answer = (_) async => throw limited(120);
      await lookup.resolve('peer');
      expect(timers.single.$1, const Duration(seconds: 120));
      expect(ended, 0);
      now = now.add(const Duration(seconds: 121));
      timers.single.$2();
      expect(ended, 1);
      answer = (_) async => address(2000);
      expect((await lookup.resolve('peer')).single['port'], 2000);
    });

    test('a longer cooldown meanwhile is waited for instead', () async {
      answer = (_) async => throw limited(60);
      await lookup.resolve('peer');
      // Another read, refused for longer before the first ran out.
      now = now.add(const Duration(seconds: 61));
      answer = (_) async => throw limited(300);
      await lookup.resolve('other');
      final last = timers.last;
      expect(last.$1, const Duration(seconds: 300));
      now = now.add(const Duration(seconds: 100));
      last.$2();
      expect(ended, 0, reason: 'still cooling down');
      expect(timers.last.$1, const Duration(seconds: 200));
      now = now.add(const Duration(seconds: 201));
      timers.last.$2();
      expect(ended, 1);
    });

    test('a peer refused on its own schedules nothing; stopping clears the cooldown', () async {
      answer = (_) async => throw const Failure(FailureCode.notFound, 'gone');
      await lookup.resolve('peer');
      expect(timers, isEmpty);
      answer = (_) async => throw limited(60);
      await lookup.resolve('other');
      expect(timers, hasLength(1));
      lookup.reset();
      expect(lookup.peerFacts('other')['retryAt'], isNull);
    });
  });

  test('what is known of an address, for an offline device', () async {
    expect(lookup.peerFacts('peer'), {'cachedRoutes': 0, 'cachedAt': null});
    await lookup.resolve('peer');
    expect(lookup.peerFacts('peer'),
        {'cachedRoutes': 1, 'cachedAt': now.toIso8601String()});
    answer = (_) async => throw const Failure(FailureCode.notFound, 'gone');
    now = now.add(const Duration(minutes: 11));
    lookup.refresh(['peer']);
    await lookup.resolve('peer');
    final refused = lookup.peerFacts('peer');
    expect(refused['retryAt'], isNotNull);
    expect((refused['error'] as Map)['message'], 'gone');
    expect(lookup.peerFacts('other').containsKey('error'), isFalse);
    answer = (_) async => throw const Failure(FailureCode.unavailable, 'busy',
        retryable: true, details: {'httpStatus': 429, 'retryAfterSeconds': 600});
    await lookup.resolve('other');
    expect((lookup.peerFacts('other')['error'] as Map)['message'], 'busy');
    // Its own refusal is still the reason for this one.
    expect((lookup.peerFacts('peer')['error'] as Map)['message'], 'gone');
  });
}
