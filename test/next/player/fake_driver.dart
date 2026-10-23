import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/next/player/core/arbiter.dart';
import 'package:nipaplay/next/player/core/clock.dart';
import 'package:nipaplay/next/player/core/host.dart';
import 'package:nipaplay/next/player/core/session.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/progress/records.dart';

/// A kernel that answers as MDK does, at once or when [gate] opens, and
/// writes down what it is told.
final class FakeDriver implements KernelDriver {
  FakeDriver(this.lease,
      {this.landed,
      this.duration = const Duration(minutes: 24),
      this.failOpen,
      this.gate,
      this.seekGate})
      : instance = ++_count {
    if (!lease.held) throw StateError('made without the lease');
  }

  static int _count = 0;
  final KernelLease lease;
  final Duration Function(Duration start)? landed;
  final Duration duration;
  final KernelOpenFailure? failOpen;

  /// Holds open until completed.
  final Completer<void>? gate;

  /// Holds each seek until completed (then replaced).
  Completer<void>? seekGate;

  final log = <String>[];
  @override
  final int instance;
  @override
  KernelId get kernel => KernelId.mdk;
  @override
  KernelConfig get config => const KernelConfig(kernel: KernelId.mdk);
  @override
  KernelCapabilities get capabilities => const KernelCapabilities(
      transportEvents: true,
      seekConfirm: true,
      bufferingTelemetry: true,
      endEvent: true,
      openAtPosition: true);

  final _events = StreamController<KernelEvent>.broadcast(sync: true);
  final _surface = ValueNotifier<VideoSurface?>(null);
  bool _fenced = false;
  bool released = false;
  int _seq = 0;
  int _ticket = 0;
  KernelTransport observed = KernelTransport.stopped;
  Duration _at = Duration.zero;
  double volume = 1;
  double rate = 1;

  @override
  Stream<KernelEvent> get events => _events.stream;
  @override
  ValueListenable<VideoSurface?> get surface => _surface;
  @override
  bool get fenced => _fenced;

  void emit(KernelEvent Function(int seq, Duration at) make) {
    if (_fenced) return;
    _events.add(make(++_seq, PlayerTime.now()));
  }

  void sample(Duration position, {bool? advancing}) {
    _at = position;
    emit((seq, at) => KernelPositionSample(instance, seq, at,
        position: position,
        rate: rate,
        advancing: advancing ?? observed == KernelTransport.playing));
  }

  void transport(KernelTransport t) {
    observed = t;
    emit((seq, at) => KernelTransportChanged(instance, seq, at, t));
    sample(_at);
  }

  @override
  Future<KernelOpened> open(ResolvedSource source,
      {Duration start = Duration.zero, double volume = 1, double rate = 1}) async {
    if (_fenced) throw const KernelFenced();
    log.add('open ${start.inMilliseconds}');
    this.volume = volume;
    this.rate = rate;
    if (gate case final gate?) await gate.future;
    if (_fenced) throw const KernelFenced();
    if (failOpen case final failure?) throw failure;
    _surface.value = const TextureSurface(7, width: 1920, height: 1080);
    final at = landed?.call(start) ?? start;
    transport(KernelTransport.paused);
    sample(at, advancing: false);
    return KernelOpened(MediaFacts(duration: duration, width: 1920, height: 1080), at);
  }

  @override
  Future<KernelTransport> setPaused(bool paused) async {
    if (_fenced) throw const KernelFenced();
    log.add(paused ? 'pause' : 'play');
    transport(paused ? KernelTransport.paused : KernelTransport.playing);
    return observed;
  }

  @override
  Future<SeekOutcome> seek(Duration target, {bool exact = true}) async {
    if (_fenced) throw const KernelFenced();
    final ticket = ++_ticket;
    log.add('seek ${target.inMilliseconds}');
    if (seekGate case final gate?) await gate.future;
    if (_fenced) throw const KernelFenced();
    if (ticket != _ticket) return const SeekOutcome(SeekResult.superseded, null);
    sample(target);
    return SeekOutcome(SeekResult.done, target);
  }

  @override
  Future<void> setRate(double rate) async {
    if (_fenced) throw const KernelFenced();
    this.rate = rate;
    sample(_at);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_fenced) throw const KernelFenced();
    this.volume = volume;
  }

  @override
  Future<JsonMap> readFacts() async => {'instance': instance};

  @override
  JsonMap get lifecycle => {'instance': instance, 'fenced': _fenced};

  Future<void>? _release;
  @override
  Future<void> release() {
    if (_release case final r?) return r;
    _fenced = true;
    log.add('fence');
    return _release = () async {
      _surface.value = null;
      await Future<void>.delayed(Duration.zero);
      released = true;
      log.add('released');
      await _events.close();
    }();
  }
}

/// Positions and watch records in memory.
final class MemoryRecords implements PlaybackRecords {
  final positions = <String, int>{};
  final records = <String, WatchHistoryItem>{};
  final published = <WatchHistoryItem>[];
  final log = <String>[];

  @override
  Future<WatchHistoryItem?> record(String path) async => records[path];
  @override
  Future<int> resumeAt(String path) async => positions[path] ?? 0;
  @override
  Future<void> savePosition(String path, int ms) async {
    log.add('position $ms');
    positions[path] = ms;
  }

  @override
  Future<void> saveRecord(WatchHistoryItem item, {bool publish = false}) async {
    log.add('record ${item.lastPosition}${publish ? ' published' : ''}');
    records[item.filePath] = item;
    if (publish) published.add(item);
  }
}

/// A host over [FakeDriver]s; [drivers] keeps every one made.
final class FakeHost {
  FakeHost({
    String kernel = 'mdk',
    FakeDriver Function(KernelLease lease)? make,
    PlayerLevels levels = const PlayerLevels(),
  }) {
    host = NextPlayerHost(
      createDriver: (_, lease) async {
        final driver = (make ?? FakeDriver.new)(lease);
        drivers.add(driver);
        return driver;
      },
      configuredKernel: () => kernel,
      levels: () async => levels,
      records: records,
      arbiter: arbiter,
    );
  }

  final arbiter = KernelArbiter();
  final records = MemoryRecords();
  final drivers = <FakeDriver>[];
  late final NextPlayerHost host;
}
