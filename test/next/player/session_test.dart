import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/player/core/arbiter.dart';
import 'package:nipaplay/next/player/core/clock.dart';
import 'package:nipaplay/next/player/core/host.dart';
import 'package:nipaplay/next/player/core/session.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/kernel/mdk_driver.dart';

import 'fake_driver.dart';

/// Next's playback session (player-core design §2, §3): the open plan,
/// intent and observation, the clock, progress, close and the lease.
void main() {
  late Directory temp;
  late String video;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('player-session-');
    video = '${temp.path}/第10集.mkv';
    await File(video).writeAsString('not a video');
  });
  tearDown(() => temp.delete(recursive: true));

  MediaRequest request({Duration? start, bool? paused}) => MediaRequest(
      locator: video, origin: 'test', start: start, paused: paused);

  test('opens where it was left, paused, then plays as asked', () async {
    final rig = FakeHost();
    rig.records.positions[video] = 600000;
    final session = await rig.host.open(request());
    final driver = rig.drivers.single;
    expect(session.phase.value, SessionPhase.active);
    expect(driver.log, ['open 600000', 'play']);
    expect(session.transport.value.observed, KernelTransport.playing);
    expect(session.position.inMilliseconds, closeTo(600000, 200));
    expect(rig.arbiter.owner, KernelOwner.next);
    // The watch record is published once the media is open.
    expect(rig.records.published.single.lastPosition, 600000);
    await rig.host.close(reason: 'test');
  });

  test('a first frame away from the start is moved there before it plays',
      () async {
    final rig = FakeHost(
        make: (lease) => FakeDriver(lease, landed: (_) => Duration.zero));
    final session =
        await rig.host.open(request(start: const Duration(minutes: 7)));
    expect(rig.drivers.single.log, ['open 420000', 'seek 420000', 'play']);
    expect(session.position.inMilliseconds, closeTo(420000, 200));
    await rig.host.close(reason: 'test');
  });

  test('a pause asked while opening holds: the plan reads the intent last',
      () async {
    final gate = Completer<void>();
    final rig = FakeHost(make: (lease) => FakeDriver(lease, gate: gate));
    final opening = rig.host.open(request());
    await pumpEventQueue();
    final session = rig.host.current.value!;
    final receipt = await session.setPaused(true, origin: 'agent');
    expect(receipt.outcome, 'pending');
    expect(session.transport.value.playIntent, isFalse);
    gate.complete();
    await opening;
    expect(rig.drivers.single.log, ['open 0']);
    expect(session.transport.value.observed, KernelTransport.paused);
    expect(session.phase.value, SessionPhase.active);
    final resumed = await session.setPaused(false, origin: 'agent');
    expect(resumed.outcome, 'applied');
    await rig.host.close(reason: 'test');
  });

  test('closing while opening fences the kernel and gives the lease back',
      () async {
    final gate = Completer<void>();
    final rig = FakeHost(make: (lease) => FakeDriver(lease, gate: gate));
    rig.records.positions[video] = 5000;
    final opening = rig.host.open(request());
    await pumpEventQueue();
    final session = rig.host.current.value!;
    final closing = rig.host.close(reason: 'test');
    gate.complete();
    await closing;
    await opening;
    final driver = rig.drivers.single;
    expect(driver.log, ['open 5000', 'fence', 'released']);
    expect(session.phase.value, SessionPhase.closed);
    expect(rig.arbiter.owner, isNull);
    // Nothing had opened: the saved position stays as it was.
    expect(rig.records.log, isEmpty);
    expect(rig.records.positions[video], 5000);
    expect(rig.host.current.value, isNull);
  });

  test('100 opens closed at random points leave one lease, no kernel alive',
      () async {
    final random = Random(7);
    final rig = FakeHost(make: (lease) {
      final gate = Completer<void>();
      Timer(Duration(milliseconds: random.nextInt(4)), gate.complete);
      return FakeDriver(lease, gate: gate);
    });
    final acquired = <int>[];
    rig.arbiter.events.listen((e) {
      if (e.kind == 'acquired') acquired.add(e.lease!);
    });
    final opens = <Future<void>>[];
    for (var i = 0; i < 100; i++) {
      opens.add(rig.host.open(request()).then((_) {}));
      await Future<void>.delayed(Duration(milliseconds: random.nextInt(3)));
      await rig.host.close(reason: 'test');
    }
    await Future.wait(opens);
    await rig.host.close(reason: 'test');
    expect(rig.arbiter.owner, isNull);
    expect(rig.drivers, everyElement(predicate<FakeDriver>((d) => d.released)));
    // One kernel at a time: each made under its own lease, released
    // before the next lease.
    final counts = rig.arbiter.facts()['counts'] as Map;
    expect(counts['acquired:next'], rig.drivers.length);
    expect(counts['released:next'], rig.drivers.length);
    expect(counts['acquired:classic'], isNull);
    expect(acquired.toSet().length, acquired.length);
  });

  test('a later seek supersedes one still under way; the clock waits',
      () async {
    final rig = FakeHost();
    final session = await rig.host.open(request());
    final driver = rig.drivers.single;
    driver.seekGate = Completer<void>();
    final first = session.seek(const Duration(minutes: 3), origin: 'gui');
    await pumpEventQueue();
    // Under way: the clock stays at the target, not advancing.
    expect(session.clock.advancing, isFalse);
    expect(session.position, const Duration(minutes: 3));
    final gate = driver.seekGate!;
    driver.seekGate = null;
    final second = session.seek(const Duration(minutes: 9), origin: 'gui');
    gate.complete();
    expect((await first).outcome, 'superseded');
    final settled = await second;
    expect(settled.outcome, 'applied');
    expect(settled.detail?['landedMs'], 540000);
    expect(session.clock.advancing, isTrue);
    expect(session.position.inMilliseconds, closeTo(540000, 200));
    expect(rig.records.positions[video], 540000);
    await rig.host.close(reason: 'test');
  });

  test('commands to a closed session say so and reach no kernel', () async {
    final rig = FakeHost();
    final session = await rig.host.open(request());
    await rig.host.close(reason: 'test');
    final driver = rig.drivers.single;
    final before = List.of(driver.log);
    expect((await session.setPaused(true, origin: 'agent')).outcome,
        'session_closed');
    expect((await session.seek(Duration.zero, origin: 'agent')).outcome,
        'session_closed');
    expect(driver.log, before);
  });

  test('pause and close save where it is; the end saves the beginning',
      () async {
    final rig = FakeHost();
    final session = await rig.host.open(request(start: const Duration(minutes: 2)));
    final driver = rig.drivers.single;
    await session.setPaused(true, origin: 'gui');
    await pumpEventQueue();
    expect(rig.records.positions[video], closeTo(120000, 200));
    driver.emit((seq, at) => KernelEnded(driver.instance, seq, at));
    await pumpEventQueue();
    expect(rig.records.positions[video], 0);
    await rig.host.close(reason: 'test');
    expect(rig.records.positions[video], 0);
    final record = rig.records.published.last;
    expect(record.watchProgress, 1.0);
  });

  test('a file that is not there fails at file_check with no kernel made',
      () async {
    final rig = FakeHost();
    final session = await rig.host.open(MediaRequest(
        locator: '${temp.path}/missing.mkv', origin: 'test'));
    expect(session.phase.value, SessionPhase.failed);
    expect(session.fault.value?.stage, 'file_check');
    expect(rig.drivers, isEmpty);
    expect(rig.arbiter.owner, isNull);
  });

  test('a kernel that cannot open fails the session and frees the lease',
      () async {
    final rig = FakeHost(
        make: (lease) => FakeDriver(lease,
            failOpen: const KernelOpenFailure('media_open', 'code -10')));
    final session = await rig.host.open(request());
    expect(session.phase.value, SessionPhase.failed);
    expect(session.fault.value?.stage, 'media_open');
    expect(rig.drivers.single.released, isTrue);
    expect(rig.arbiter.owner, isNull);
  });

  test('what the layer cannot play is refused before anything closes',
      () async {
    final rig = FakeHost();
    await rig.host.open(request());
    expect(
        () => rig.host.open(const MediaRequest(
            locator: 'unknown://abc', origin: 'agent')),
        throwsA(isA<OpenRefused>()
            .having((r) => r.reason, 'reason', 'source_not_supported')
            .having((r) => r.facts['source'], 'source', 'unknown')));
    expect(rig.host.current.value?.phase.value, SessionPhase.active);
    final other = FakeHost(kernel: 'media_kit');
    expect(
        () => other.host.open(request()),
        throwsA(isA<OpenRefused>()
            .having((r) => r.reason, 'reason', 'kernel_not_supported')
            .having((r) => r.facts['configured'], 'configured', 'media_kit')));
    final refusals = other.host.facts()['refusals'] as List;
    expect(refusals.single['reason'], 'kernel_not_supported');
    await rig.host.close(reason: 'test');
  });

  test('a shared volume or speed changed in settings applies to what plays',
      () async {
    final rig = FakeHost(levels: const PlayerLevels(volume: 0.5, boost: 2));
    final session = await rig.host.open(request());
    final driver = rig.drivers.single;
    expect(driver.volume, 1.0);
    rig.host.settingChanged('player.volume', 0);
    rig.host.settingChanged('playback.rate', 1.5);
    await pumpEventQueue();
    expect(driver.volume, 0);
    expect(driver.rate, 1.5);
    expect(session.transport.value.rate, 1.5);
    await rig.host.close(reason: 'test');
  });

  group('clock', () {
    test('extrapolates without the kernel and tells only discontinuities',
        () async {
      final clock = PlaybackClock();
      var told = 0;
      clock.addListener(() => told++);
      clock.anchor(const Duration(seconds: 10),
          advancing: true, source: 'kernel_sample');
      expect(told, 1);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(clock.now().inMilliseconds, inInclusiveRange(10100, 10400));
      // A sample on course: no listener told.
      clock.anchor(clock.now() + const Duration(milliseconds: 10),
          advancing: true, source: 'kernel_sample');
      expect(told, 1);
      // A jump is.
      clock.anchor(const Duration(seconds: 50),
          advancing: true, source: 'kernel_sample');
      expect(told, 2);
      clock.limit = const Duration(seconds: 50);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(clock.now(), const Duration(seconds: 50));
    });
  });

  test('a kernel is made only under Next\'s lease', () async {
    final arbiter = KernelArbiter();
    final lease = await arbiter.acquire(KernelOwner.next, reason: 'test');
    await lease.release();
    expect(() => MdkDriver(lease, const KernelConfig(kernel: KernelId.mdk)),
        throwsStateError);
  });
}
