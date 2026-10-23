import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/player/core/arbiter.dart';
import 'package:nipaplay/next/player/kernel/adapter_driver.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/kernel/native.dart';

/// A kernel behind [AdapterDriver] that does what it is scripted to: the
/// order in which the base opens, seeks, changes tracks and lets go is what
/// is under test, not any kernel.
final class ScriptedDriver extends AdapterDriver {
  ScriptedDriver(super.config);

  final calls = <String>[];
  Duration position = Duration.zero;
  Duration landedOpen = Duration.zero;
  Duration length = const Duration(minutes: 20);
  Completer<void>? openGate;
  Completer<void>? switchGate;
  bool reportsAudio = true;
  bool reportsSubtitle = true;
  Duration? movesBy;
  Object? failOpen;
  var released = false;
  var disposed = false;

  @override
  KernelId get kernel => KernelId.erika;
  @override
  KernelNative get native => const PlainNative(null);
  @override
  KernelCapabilities get capabilities => const KernelCapabilities(
      transportEvents: true,
      seekConfirm: true,
      bufferingTelemetry: true,
      endEvent: false,
      openAtPosition: false,
      trackConfirm: true);

  /// What the kernel says.
  void say(void Function() event) => event();
  void saysPlaying() => transportChanged(KernelTransport.playing);
  void saysPaused() => transportChanged(KernelTransport.paused);
  void saysPosition(Duration at) {
    position = at;
    positionChanged(at);
  }

  void saysEnded() => ended(inferred: true);

  @override
  void applyVolume(double volume) => calls.add('volume $volume');
  @override
  void applyRate(double rate) => calls.add('rate $rate');
  @override
  Future<void> configure() async => calls.add('configure');
  @override
  Future<void> routeSource(ResolvedSource source) async =>
      calls.add('route ${source.direct ? 'direct' : 'default'}');
  @override
  Future<void> applyPlan(KernelTrackPlan plan) async =>
      calls.add('plan ${plan.audio} ${plan.subtitle}');

  @override
  Future<Duration> openMedia(ResolvedSource source, Duration start) async {
    calls.add('open ${start.inMilliseconds}');
    if (openGate case final gate?) await gate.future;
    queue.live();
    if (failOpen case final failure?) throw failure;
    position = landedOpen == Duration.zero ? start : landedOpen;
    return position;
  }

  @override
  Future<KernelTracks> planOpened(KernelTrackPlan plan, MediaFacts media) async {
    calls.add('planOpened');
    return KernelTracks(
        audio: plan.audio,
        subtitle: plan.subtitle,
        audioConfirmed: true,
        subtitleConfirmed: !plan.subtitle.drawn || reportsSubtitle,
        basis: 'opened');
  }

  @override
  Future<TrackReport> switchAudio(int index) async {
    calls.add('audio $index');
    if (switchGate case final gate?) await gate.future;
    queue.live();
    if (movesBy case final by?) saysPosition(position + by);
    return (confirmed: reportsAudio, basis: reportsAudio ? 'event' : 'not_reported');
  }

  @override
  Future<TrackReport> switchSubtitle(KernelSubtitle subtitle, Duration? probe) async {
    calls.add('subtitle $subtitle');
    if (switchGate case final gate?) await gate.future;
    queue.live();
    if (movesBy case final by?) saysPosition(position + by);
    return (confirmed: reportsSubtitle, basis: reportsSubtitle ? 'event' : 'not_reported');
  }

  @override
  Future<void> applySubtitleProperties(Map<String, String> properties) async =>
      calls.add('look ${properties.entries.map((e) => '${e.key}=${e.value}').join(',')}');

  @override
  Future<void> seekMedia(Duration target, {required bool exact}) async {
    calls.add('seek ${target.inMilliseconds}');
    // The kernel's own position arrives a moment after the command.
    scheduleMicrotask(() => saysPosition(target));
  }

  @override
  Future<void> pauseMedia(bool paused) async {
    calls.add(paused ? 'pause' : 'play');
    scheduleMicrotask(() => paused ? saysPaused() : saysPlaying());
  }

  @override
  Future<Duration?> readPosition() async => position;

  @override
  MediaFacts readMedia() => MediaFacts(
      duration: length,
      width: 1920,
      height: 1080,
      audio: const [TrackFacts(index: 0), TrackFacts(index: 1)]);

  @override
  Future<void> showPicture(MediaFacts media) async {
    picture = const TextureSurface(3, width: 1920, height: 1080);
    calls.add('picture');
  }

  @override
  Future<JsonMap> kernelFacts() async => {};

  @override
  Future<void> aFramePasses() async => calls.add('frame');

  @override
  Future<void> unmount() async => calls.add('unmount');

  @override
  Future<void> disposeKernel() async {
    disposed = true;
    calls.add('dispose');
  }
}

Future<(ScriptedDriver, KernelLease)> made() async {
  final arbiter = KernelArbiter();
  final lease = await arbiter.acquire(KernelOwner.next, reason: 'test');
  return (ScriptedDriver(const KernelConfig(kernel: KernelId.erika)), lease);
}

const source = ResolvedSource(locator: '/a.mkv', uri: '/a.mkv', kind: 'local');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a kernel is made only under the lease', () async {
    final arbiter = KernelArbiter();
    final lease = await arbiter.acquire(KernelOwner.next, reason: 'test');
    requireLease(lease, 'Test');
    await lease.release();
    expect(() => requireLease(lease, 'Test'), throwsStateError);
  });

  test('it opens in order, paused, and says what it opened with', () async {
    final (driver, _) = await made();
    final events = <KernelEvent>[];
    driver.events.listen(events.add);
    final opened = await driver.open(source,
        start: const Duration(minutes: 5),
        volume: 0.4,
        rate: 1.5,
        tracks: const KernelTrackPlan(audio: 1));
    expect(driver.calls, [
      'configure',
      'plan 1 none',
      'volume 0.4',
      'rate 1.5',
      'open 300000',
      'planOpened',
      'pause',
      'picture',
    ]);
    expect(opened.landed, const Duration(minutes: 5));
    expect(opened.tracks.audio, 1);
    expect(opened.tracks.audioConfirmed, true);
    expect(driver.surface.value, isA<TextureSurface>());
    expect(events.whereType<KernelTransportChanged>().last.transport,
        KernelTransport.paused);
    expect(events.whereType<KernelTracksChanged>(), hasLength(1));
    // Each event names its instance and comes in order.
    expect(events.map((e) => e.instance).toSet(), {driver.instance});
    final seqs = events.map((e) => e.seq).toList();
    expect([...seqs]..sort(), seqs);
    await driver.release();
  });

  test('a source that maps its tracks opens with them, over the library\'s; '
      'one that goes direct says so before the media opens', () async {
    final (driver, _) = await made();
    await driver.open(
        const ResolvedSource(
            locator: 'x',
            uri: 'http://h/x',
            kind: 'server',
            direct: true,
            audioTrack: 1,
            subtitleTrack: 3),
        tracks: const KernelTrackPlan(
            audio: 0, subtitle: EmbeddedKernelSubtitle(0)));
    expect(driver.calls.where((c) => c.startsWith('plan') || c.startsWith('route')),
        ['route direct', 'plan 1 embedded 3']);
    expect(driver.tracks.audio, 1);
    await driver.release();

    final (file, _) = await made();
    await file.open(
        const ResolvedSource(
            locator: 'x',
            uri: 'http://h/x',
            kind: 'server',
            externalSubtitle: '/subs/a.ass'),
        tracks: const KernelTrackPlan(subtitle: EmbeddedKernelSubtitle(2)));
    expect(file.calls, contains('plan null file /subs/a.ass'));
    await file.release();

    final (none, _) = await made();
    await none.open(
        const ResolvedSource(
            locator: 'x', uri: 'http://h/x', kind: 'server', subtitleTrack: -1),
        tracks: const KernelTrackPlan(subtitle: EmbeddedKernelSubtitle(2)));
    expect(none.calls, contains('plan null none'));
    await none.release();
  });

  test('an instance opens once, and one released never again (I5)', () async {
    final (driver, _) = await made();
    await driver.open(source);
    await expectLater(driver.open(source), throwsStateError);
    await driver.release();
    await expectLater(driver.open(source), throwsA(isA<KernelFenced>()));
  });

  test('a media with no length, or one that did not open, is a failure',
      () async {
    final (driver, _) = await made();
    driver.length = Duration.zero;
    expect(driver.open(source),
        throwsA(isA<KernelOpenFailure>().having((f) => f.stage, 'stage', 'media_open')));
    final (broken, _) = await made();
    broken.failOpen = const KernelOpenFailure('media_open', 'no codec');
    expect(broken.open(source), throwsA(isA<KernelOpenFailure>()));
  });

  test('play and pause wait for the kernel to say it, and do not when it '
      'does not', () async {
    final (driver, _) = await made();
    await driver.open(source);
    expect(await driver.setPaused(false), KernelTransport.playing);
    expect(await driver.setPaused(false), KernelTransport.playing,
        reason: 'already there: nothing asked');
    expect(driver.calls.where((c) => c == 'play'), hasLength(1));
    expect(await driver.setPaused(true), KernelTransport.paused);
    await driver.release();
  });

  test('a seek answers where the kernel landed; a later one replaces one '
      'still waiting', () async {
    final (driver, _) = await made();
    await driver.open(source);
    final first = driver.seek(const Duration(minutes: 3));
    final second = driver.seek(const Duration(minutes: 8));
    final outcomes = await Future.wait([first, second]);
    expect(outcomes[0].result, SeekResult.superseded);
    expect(outcomes[1].result, SeekResult.done);
    expect(outcomes[1].landed, const Duration(minutes: 8));
    expect(driver.calls.where((c) => c.startsWith('seek')), ['seek 480000']);
    await driver.release();
  });

  test('positions are told when the kernel drifts, not each time', () async {
    final (driver, _) = await made();
    final samples = <KernelPositionSample>[];
    driver.events.listen((e) {
      if (e is KernelPositionSample) samples.add(e);
    });
    await driver.open(source);
    await driver.setPaused(false);
    samples.clear();
    // On course: nothing. A jump: a sample.
    final now = driver.tracks;
    expect(now.audio, isNull);
    driver.saysPosition(Duration.zero + const Duration(milliseconds: 5));
    expect(samples, isEmpty);
    driver.saysPosition(const Duration(minutes: 9));
    expect(samples.single.position, const Duration(minutes: 9));
    expect(samples.single.advancing, true);
    await driver.release();
  });

  group('tracks', () {
    test('a change waits for the kernel\'s report, and says when it did not '
        'come', () async {
      final (driver, _) = await made();
      await driver.open(source);
      final reports = <KernelTracks>[];
      driver.events.listen((e) {
        if (e is KernelTracksChanged) reports.add(e.tracks);
      });
      var tracks = await driver.selectAudio(1);
      expect(tracks.audio, 1);
      expect(tracks.audioConfirmed, true);
      expect(tracks.basis, 'event');
      driver.reportsAudio = false;
      tracks = await driver.selectAudio(0);
      expect(tracks.audio, 0);
      expect(tracks.audioConfirmed, false);
      expect(tracks.basis, 'not_reported');
      expect(reports, hasLength(2), reason: 'a report with each change');
      // The same again, confirmed already: nothing is asked.
      driver.reportsAudio = true;
      await driver.selectAudio(1);
      driver.calls.clear();
      await driver.selectAudio(1);
      expect(driver.calls, isEmpty);
      await driver.release();
    });

    test('a subtitle is put on and off, one at a time, in the queue', () async {
      final (driver, _) = await made();
      await driver.open(source);
      final order = <String>[];
      final a = driver.selectSubtitle(const EmbeddedKernelSubtitle(2))
          .then((_) => order.add('a'));
      final b = driver.selectSubtitle(KernelSubtitle.none).then((_) => order.add('b'));
      await Future.wait([a, b]);
      expect(order, ['a', 'b']);
      expect(driver.tracks.subtitle, KernelSubtitle.none);
      expect(driver.calls.where((c) => c.startsWith('subtitle')),
          ['subtitle embedded 2', 'subtitle none']);
      await driver.release();
    });

    test('a track change that moved the position puts it back', () async {
      final (driver, _) = await made();
      await driver.open(source, start: const Duration(minutes: 5));
      await driver.setPaused(false);
      driver.movesBy = const Duration(minutes: -5);
      await driver.selectAudio(1);
      expect(driver.calls.where((c) => c.startsWith('seek')).length, 1);
      expect(driver.position.inMinutes, closeTo(5, 1));
      await driver.release();
    });

    test('a track change before the media is open is refused', () async {
      final (driver, _) = await made();
      await expectLater(driver.selectAudio(1), throwsStateError);
      await driver.release();
    });

    test('the look reaches the kernel once per change', () async {
      final (driver, _) = await made();
      await driver.open(source,
          tracks: const KernelTrackPlan(subtitleProperties: {'subtitle.scale': '1.00'}));
      await driver.setSubtitleProperties({'subtitle.scale': '1.00'});
      await driver.setSubtitleProperties({'subtitle.scale': '1.50', 'subtitle.bold': '1'});
      expect(driver.calls.where((c) => c.startsWith('look')),
          ['look subtitle.scale=1.50,subtitle.bold=1']);
      await driver.release();
    });
  });

  group('release (I2, I4)', () {
    test('the fence is up before the first wait; every call after throws',
        () async {
      final (driver, _) = await made();
      await driver.open(source);
      final release = driver.release();
      expect(driver.fenced, true);
      expect(driver.setPaused(false), throwsA(isA<KernelFenced>()));
      expect(driver.seek(Duration.zero), throwsA(isA<KernelFenced>()));
      expect(driver.selectAudio(1), throwsA(isA<KernelFenced>()));
      expect(driver.readFacts(), throwsA(isA<KernelFenced>()));
      await release;
      expect(identical(driver.release(), driver.release()), true,
          reason: 'idempotent: the same future');
    });

    test('the order: stop, drain, picture off, a frame, the kernel destroyed',
        () async {
      final (driver, _) = await made();
      await driver.open(source);
      await driver.setPaused(false);
      driver.calls.clear();
      await driver.release();
      expect(driver.calls, ['pause', 'frame', 'unmount', 'dispose']);
      expect(driver.surface.value, isNull);
      expect(driver.lifecycle['fenced'], true);
      expect(driver.lifecycle['releaseTimeouts'], isEmpty);
    });

    test('what the kernel says after the fence is dropped and counted',
        () async {
      final (driver, _) = await made();
      final events = <KernelEvent>[];
      driver.events.listen(events.add);
      await driver.open(source);
      await driver.release();
      final before = events.length;
      driver.saysPlaying();
      driver.saysPosition(const Duration(minutes: 1));
      driver.saysEnded();
      expect(events.length, before);
    });

    test('an open still waiting when the instance is released ends fenced',
        () async {
      final (driver, _) = await made();
      driver.openGate = Completer<void>();
      final opening = driver.open(source);
      await pumpEventQueue();
      final release = driver.release();
      driver.openGate!.complete();
      await expectLater(opening, throwsA(isA<KernelFenced>()));
      await release;
      expect(driver.disposed, true);
    });

    test('a step that does not finish is named and the instance still goes',
        () async {
      final (driver, _) = await made();
      await driver.open(source);
      driver.switchGate = Completer<void>();
      // A track change that never answers holds the queue.
      unawaited(driver.selectAudio(1).then((_) {}, onError: (Object _) {}));
      await pumpEventQueue();
      final watch = Stopwatch()..start();
      await driver.release();
      expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
      expect(driver.lifecycle['releaseTimeouts'], contains('drain'));
      expect(driver.disposed, true);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  test('the end is told once, and again after a seek', () async {
    final (driver, _) = await made();
    final ends = <KernelEnded>[];
    driver.events.listen((e) {
      if (e is KernelEnded) ends.add(e);
    });
    await driver.open(source);
    driver.saysEnded();
    driver.saysEnded();
    expect(ends, hasLength(1));
    expect(ends.single.inferred, true);
    await driver.seek(const Duration(minutes: 1));
    driver.saysEnded();
    expect(ends, hasLength(2));
    await driver.release();
  });

  test('a kernel that is asked for a texture-less picture publishes none',
      () async {
    final (driver, _) = await made();
    final surfaces = <VideoSurface?>[];
    driver.surface.addListener(() => surfaces.add(driver.surface.value));
    await driver.open(source);
    await driver.release();
    expect(surfaces.first, isA<TextureSurface>());
    expect(surfaces.last, isNull);
  });
}
