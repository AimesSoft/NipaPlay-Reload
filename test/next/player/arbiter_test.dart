import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/player/core/arbiter.dart';

void main() {
  test('one lease: taking it from the other side runs its evictor first',
      () async {
    final arbiter = KernelArbiter();
    final log = <String>[];
    arbiter.registerEvictor(KernelOwner.classic, (reason) async {
      log.add('classic closes ($reason)');
    });
    final events = <String>[];
    arbiter.events.listen((e) => events.add('${e.kind}:${e.owner.name}'));
    final classic =
        await arbiter.acquire(KernelOwner.classic, reason: 'classic open');
    expect(arbiter.owner, KernelOwner.classic);
    final next = await arbiter.acquire(KernelOwner.next, reason: 'next open');
    expect(log, ['classic closes (next open)']);
    expect(classic.held, isFalse);
    expect(next.held, isTrue);
    expect(arbiter.owner, KernelOwner.next);
    expect(events, ['acquired:classic', 'evicted:classic', 'acquired:next']);
    await next.release();
    expect(arbiter.owner, isNull);
    expect(events.last, 'released:next');
  });

  test('asked again by the holder, the same lease; a stale release is ignored',
      () async {
    final arbiter = KernelArbiter();
    final first = await arbiter.acquire(KernelOwner.next, reason: 'a');
    expect(await arbiter.acquire(KernelOwner.next, reason: 'b'), same(first));
    final classic = await arbiter.acquire(KernelOwner.classic, reason: 'c');
    await first.release();
    expect(arbiter.lease, same(classic));
  });

  test('an open by the side without the lease is a violation', () async {
    final arbiter = KernelArbiter();
    arbiter.noteOpen(KernelOwner.classic, 'classic.initializePlayer');
    expect(arbiter.violations, isEmpty);
    await arbiter.acquire(KernelOwner.next, reason: 'next open');
    arbiter.noteOpen(KernelOwner.next, 'next');
    arbiter.noteOpen(KernelOwner.classic, 'classic.initializePlayer');
    expect(arbiter.violations.single.reason, 'classic.initializePlayer');
    expect(arbiter.facts()['owner'], 'next');
  });

  test('acquisitions are served one at a time, in order', () async {
    final arbiter = KernelArbiter();
    final order = <String>[];
    arbiter.registerEvictor(KernelOwner.classic, (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      order.add('classic evicted');
    });
    arbiter.registerEvictor(KernelOwner.next, (_) async {
      order.add('next evicted');
    });
    await arbiter.acquire(KernelOwner.classic, reason: '1');
    final a = arbiter.acquire(KernelOwner.next, reason: '2');
    final b = arbiter.acquire(KernelOwner.classic, reason: '3');
    await Future.wait([a, b]);
    expect(order, ['classic evicted', 'next evicted']);
    expect(arbiter.owner, KernelOwner.classic);
  });

  test('a side playing without the lease is closed when the other takes it',
      () async {
    final arbiter = KernelArbiter();
    var classicPlays = true;
    final log = <String>[];
    arbiter.registerEvictor(KernelOwner.classic, (reason) async {
      log.add('classic closes ($reason)');
      classicPlays = false;
    }, busy: () => classicPlays);
    final events = <String>[];
    arbiter.events.listen((e) => events.add('${e.kind}:${e.owner.name}'));
    await arbiter.acquire(KernelOwner.next, reason: 'next open');
    expect(log, ['classic closes (next open)']);
    expect(events, ['evicted:classic', 'acquired:next']);
    await arbiter.acquire(KernelOwner.next, reason: 'again');
    expect(log, hasLength(1));
    final counts = arbiter.facts()['counts'] as Map;
    expect(counts['acquired:next'], 1);
    expect(counts['acquired:classic'], isNull);
  });
}
