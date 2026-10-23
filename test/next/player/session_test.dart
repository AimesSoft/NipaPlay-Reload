import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/player/core/arbiter.dart';
import 'package:nipaplay/next/player/core/clock.dart';
import 'package:nipaplay/next/player/core/host.dart';
import 'package:nipaplay/next/player/core/session.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/kernel/erika_driver.dart';
import 'package:nipaplay/next/player/kernel/mdk_driver.dart';
import 'package:nipaplay/next/player/kernel/media_kit_driver.dart';
import 'package:nipaplay/next/player/kernel/track_match.dart';
import 'package:nipaplay/next/player/subtitles/controller.dart';
import 'package:nipaplay/next/player/kernel/video_player_driver.dart';

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
    // Paused, the frame it opened at is put up (not a transport change).
    expect(rig.drivers.single.log, ['open 0', 'present']);
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
            locator: 'jellyfin://abc', origin: 'agent')),
        throwsA(isA<OpenRefused>()
            .having((r) => r.reason, 'reason', 'source_not_supported')
            .having((r) => r.facts['source'], 'source', 'jellyfin')));
    expect(rig.host.current.value?.phase.value, SessionPhase.active);
    final other = FakeHost(kernel: 'unknown');
    expect(
        () => other.host.open(request()),
        throwsA(isA<OpenRefused>()
            .having((r) => r.reason, 'reason', 'kernel_not_supported')
            .having((r) => r.facts['configured'], 'configured', 'unknown')));
    final refusals = other.host.facts()['refusals'] as List;
    expect(refusals.single['reason'], 'kernel_not_supported');
    await rig.host.close(reason: 'test');
  });

  test('each configured kernel gets a new instance and resumes shared progress', () async {
    for (final kernel in KernelId.values) {
      final rig = FakeHost(kernel: kernel.id);
      rig.records.positions[video] = 450000;
      final first = await rig.host.open(request());
      expect(first.driver!.kernel, kernel);
      expect(first.position.inMilliseconds, closeTo(450000, 100));
      await rig.host.close(reason: 'test');
      final second = await rig.host.open(request());
      expect(identical(first.driver, second.driver), false);
      expect(second.position.inMilliseconds, closeTo(450000, 100));
      await rig.host.close(reason: 'test');
    }
  });

  test('50 kernel swaps retain the session, pause intent, position and levels', () async {
    final rig = FakeHost();
    final session = await rig.host.open(request(start: const Duration(minutes: 9), paused: true));
    await session.setRate(1.5, origin: 'test');
    await session.setVolume(0.2, origin: 'test');
    final id = session.id;
    for (var i = 0; i < 50; i++) {
      final previous = session.driver!;
      final target = Duration(seconds: 500 + i);
      await session.seek(target, origin: 'test');
      final kernel = KernelId.values[i % KernelId.values.length];
      final result = await session.swapKernel(kernel, origin: 'test');
      expect(result['opened'], true);
      expect(session.id, id);
      expect(previous.fenced, true);
      expect(session.driver!.kernel, kernel);
      expect(session.position.inMilliseconds, closeTo(target.inMilliseconds, 20));
      expect(session.transport.value.playIntent, false);
      expect(session.transport.value.observed, KernelTransport.paused);
      expect((session.driver as FakeDriver).rate, 1.5);
      expect((session.driver as FakeDriver).volume, 0.2);
      expect(rig.arbiter.owner, KernelOwner.next);
    }
    expect(session.kernelGeneration, 51);
    await rig.host.close(reason: 'test');
    expect(rig.arbiter.owner, isNull);
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
    // The other three refuse before anything native is made.
    expect(() => ErikaDriver(lease, const KernelConfig(kernel: KernelId.erika)),
        throwsStateError);
    expect(
        () => MediaKitDriver(lease, const KernelConfig(kernel: KernelId.mediaKit)),
        throwsStateError);
    expect(
        () => VideoPlayerDriver(
            lease, const KernelConfig(kernel: KernelId.videoPlayer)),
        throwsStateError);
  });

  group('swapping the kernel', () {
    test('the tracks and the subtitle that were on carry over, by what they are',
        () async {
      final rig = FakeHost();
      final session = await rig.host.open(request());
      await session.selectAudio(1, origin: 'test');
      await session.chooseSubtitle(const SubtitleWant.embedded(1), origin: 'test');
      final old = rig.drivers.single;
      expect(old.tracks.subtitle, const EmbeddedKernelSubtitle(1));
      final reply = await session.swapKernel(KernelId.erika, origin: 'test');
      expect(reply['opened'], true);
      final fresh = rig.drivers.last;
      expect(fresh, isNot(same(old)));
      expect(fresh.log, containsAllInOrder([startsWith('open'), 'audio 1', 'subtitle embedded 1']));
      expect(fresh.tracks.audio, 1);
      expect(fresh.tracks.subtitle, const EmbeddedKernelSubtitle(1));
      expect(session.audio.value.want, 1);
      expect(session.subtitles.want, const SubtitleWant.embedded(1));
      final preserved = reply['preserved'] as Map;
      expect(preserved['audioTrack'], containsPair('reapplied', true));
      expect((preserved['subtitleTrack'] as Map)['before'],
          {'kind': 'embedded', 'index': 1});
      expect((preserved['subtitleTrack'] as Map)['after'],
          {'kind': 'embedded', 'index': 1});
      await rig.host.close(reason: 'test');
    });

    test('a track the new kernel names differently is found by identity; one '
        'it does not have leaves the subtitle off and says why', () async {
      final rig = FakeHost(
          driver: (kernel, lease) => FakeDriver(lease, kernel: kernel)
            ..subtitleTracks = kernel == KernelId.erika
                // Reordered: Chinese first.
                ? const [
                    TrackFacts(index: 0, codec: 'ass', language: 'chi', title: 'JPSC'),
                    TrackFacts(index: 1, codec: 'subrip', language: 'ger'),
                    TrackFacts(index: 2, codec: 'subrip', language: 'eng'),
                  ]
                : kernel == KernelId.videoPlayer
                    ? const []
                    : const [
                        TrackFacts(index: 0, codec: 'subrip', language: 'ger'),
                        TrackFacts(index: 1, codec: 'subrip', language: 'eng'),
                        TrackFacts(index: 2, codec: 'ass', language: 'chi', title: 'JPSC'),
                      ]);
      final session = await rig.host.open(request());
      await session.chooseSubtitle(const SubtitleWant.embedded(2), origin: 'test');
      await session.swapKernel(KernelId.erika, origin: 'test');
      expect(session.subtitles.want, const SubtitleWant.embedded(0),
          reason: 'the JPSC track, now first');
      expect(rig.drivers.last.tracks.subtitle, const EmbeddedKernelSubtitle(0));
      final gone = await session.swapKernel(KernelId.videoPlayer, origin: 'test');
      expect(session.subtitles.want.off, isTrue);
      expect((gone['preserved'] as Map)['subtitleTrack'],
          containsPair('reason', 'no_matching_track'));
      expect(session.subtitles.state.value.failure, 'no_matching_track');
      await rig.host.close(reason: 'test');
    });

    test('a subtitle file the old kernel drew itself goes on on the new one, '
        'after it is open', () async {
      final ass = '${temp.path}/第10集.ass';
      await File(ass).writeAsString('[Script Info]\n');
      final rig = FakeHost();
      final session = await rig.host.open(request());
      await session.chooseSubtitle(SubtitleWant.file(ass), origin: 'test');
      await session.swapKernel(KernelId.mediaKit, origin: 'test');
      final fresh = rig.drivers.last;
      expect(fresh.plan!.subtitle, KernelSubtitle.none,
          reason: 'opened drawing nothing, the file put on after');
      expect(fresh.log, contains('subtitle file $ass'));
      expect(fresh.tracks.subtitle, FileKernelSubtitle(ass));
      expect(session.subtitles.state.value.presented.single.renderer,
          SubtitleRenderer.kernel);
      await rig.host.close(reason: 'test');
    });

    test('a pause or a seek asked while the new kernel opens is the one that '
        'holds', () async {
      final gate = Completer<void>();
      var made = 0;
      final rig = FakeHost(
          driver: (kernel, lease) => FakeDriver(lease,
              kernel: kernel, gate: ++made == 2 ? gate : null));
      final session = await rig.host.open(request(start: const Duration(minutes: 5)));
      final swapping = session.swapKernel(KernelId.mediaKit, origin: 'test');
      await pumpEventQueue();
      expect(session.phase.value, SessionPhase.swapping);
      expect((await session.setPaused(true, origin: 'agent')).outcome, 'pending');
      expect(
          (await session.seek(const Duration(minutes: 9), origin: 'agent')).outcome,
          'pending');
      gate.complete();
      final reply = await swapping;
      expect(reply['opened'], true);
      expect(session.transport.value.observed, KernelTransport.paused);
      expect(session.transport.value.playIntent, isFalse);
      expect(session.position.inMilliseconds, closeTo(540000, 100));
      expect(rig.drivers.last.log, containsAllInOrder(['open 300000', 'seek 540000']));
      await rig.host.close(reason: 'test');
    });

    test('the old instance is gone before the new one is made', () async {
      final seen = <String>[];
      late FakeHost rig;
      rig = FakeHost(
          driver: (kernel, lease) {
            if (rig.drivers.isNotEmpty) {
              seen.add('old fenced: ${rig.drivers.last.fenced}, '
                  'released: ${rig.drivers.last.released}');
            }
            return FakeDriver(lease, kernel: kernel);
          });
      final session = await rig.host.open(request());
      await session.swapKernel(KernelId.erika, origin: 'test');
      expect(seen, ['old fenced: true, released: true']);
      expect(rig.arbiter.owner, KernelOwner.next);
      await rig.host.close(reason: 'test');
    });

    test('closing during a swap frees the new instance and the lease',
        () async {
      final gate = Completer<void>();
      var made = 0;
      final rig = FakeHost(
          driver: (kernel, lease) => FakeDriver(lease,
              kernel: kernel, gate: ++made == 2 ? gate : null));
      final session = await rig.host.open(request());
      final swapping = session.swapKernel(KernelId.mediaKit, origin: 'test');
      await pumpEventQueue();
      final closing = session.close(reason: 'test');
      gate.complete();
      final reply = await swapping;
      await closing;
      expect(reply['opened'], false);
      expect(reply['reason'], 'session_closed');
      expect(rig.drivers.every((d) => d.fenced && d.released), isTrue);
      expect(rig.arbiter.owner, isNull);
    });

    test('a kernel that fails to open fails the session and frees the lease; '
        'another swap brings it back with its position', () async {
      var made = 0;
      final rig = FakeHost(
          driver: (kernel, lease) => FakeDriver(lease,
              kernel: kernel,
              failOpen: ++made == 2
                  ? const KernelOpenFailure('media_open', 'no such codec')
                  : null));
      final session = await rig.host.open(request(start: const Duration(minutes: 7)));
      final failed = await session.swapKernel(KernelId.mediaKit, origin: 'test');
      expect(failed['opened'], false);
      expect(failed['failure'], 'no such codec');
      expect(session.phase.value, SessionPhase.failed);
      expect(session.fault.value!.stage, 'swap:media_open');
      expect(rig.arbiter.owner, isNull);
      final back = await session.swapKernel(KernelId.mdk, origin: 'test');
      expect(back['opened'], true);
      expect(session.phase.value, SessionPhase.active);
      expect(session.fault.value, isNull);
      expect(rig.arbiter.owner, KernelOwner.next);
      expect(session.position.inMilliseconds, closeTo(420000, 100));
      await rig.host.close(reason: 'test');
    });

    test('every instance the session had is kept for measurement', () async {
      final rig = FakeHost();
      final session = await rig.host.open(request());
      await session.swapKernel(KernelId.erika, origin: 'test');
      await session.swapKernel(KernelId.mdk, origin: 'test');
      await rig.host.close(reason: 'test');
      expect(session.retiredKernels, hasLength(3));
      expect(rig.host.lifecycles, hasLength(3));
    });

    test('a track is matched by language, title and codec, else by index', () {
      const before = [
        TrackFacts(index: 0, codec: 'flac', language: 'jpn'),
        TrackFacts(index: 1, codec: 'aac', title: 'commentary', language: 'jpn'),
      ];
      expect(
          matchTrack(before, 1, const [
            TrackFacts(index: 0, codec: 'aac', title: 'commentary', language: 'jpn'),
            TrackFacts(index: 1, codec: 'flac', language: 'jpn'),
          ]).index,
          0);
      // Named differently on the new kernel, as many tracks: the same index.
      expect(
          matchTrack(before, 1, const [
            TrackFacts(index: 0, title: 'Audio 1'),
            TrackFacts(index: 1, title: 'Audio 2'),
          ]).index,
          1);
      final none = matchTrack(before, 1, const [TrackFacts(index: 0, title: 'x')]);
      expect(none.index, isNull);
      expect(none.reason, 'no_matching_track');
      expect(matchTrack(before, null, before).reason, isNull);
    });
  });
}
