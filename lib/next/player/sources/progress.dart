import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/shared_remote_playback_sync_service.dart';
import 'package:nipaplay/utils/shared_remote_history_helper.dart';

import '../core/session.dart';
import '../kernel/driver.dart';
import 'resolver.dart';

/// Receives session pushes; the only periodic work is an actual remote
/// heartbeat while playing. One pending sample replaces older samples if
/// the network is slow, so a disconnected server cannot grow a queue.
final class SourceProgress {
  SourceProgress(this.session, this.plan) {
    _events = session.events.listen(_event);
    session.closeSource = close;
  }
  final PlaybackSession session;
  final SourcePlan plan;
  late final StreamSubscription<PlaybackEvent> _events;
  Timer? _heartbeat;
  bool _started = false, _closing = false;
  JsonMap? _pending;
  JsonMap? _startSample;
  Future<void>? _sending;
  JsonMap? lastReport;
  String? lastError;
  final _elapsed = Stopwatch()..start();
  int? _lastAt;

  JsonMap sample() => {
        'positionMs': session.position.inMilliseconds,
        'durationMs': session.duration.inMilliseconds,
        'paused': session.transport.value.observed != KernelTransport.playing,
        'muted': session.transport.value.volume == 0,
        'volume': (session.transport.value.volume * 100).round(),
        'rate': session.transport.value.rate,
        'at': DateTime.now().toUtc().toIso8601String(),
        'intervalMs':
            _lastAt == null ? null : _elapsed.elapsedMilliseconds - _lastAt!,
        'source': 'session_clock',
      };

  void _event(PlaybackEvent e) {
    if (_closing) return;
    if (e.kind == 'phase' && e.data['phase'] == 'active') {
      _startSample = {...sample(), 'kind': 'start'};
      _sending ??= _drain();
      _started = true;
      _syncHeartbeat();
    } else if (_started &&
        (e.kind == 'transport' ||
            e.kind == 'seek_settled' ||
            e.kind == 'ended')) {
      _enqueue('progress');
      _syncHeartbeat();
    } else if (e.kind == 'phase' && e.data['phase'] == 'closing') {
      _heartbeat?.cancel();
      _heartbeat = null;
    }
  }

  void _syncHeartbeat() {
    if (plan.progress == null && !SharedRemoteHistoryHelper.isSharedRemoteStreamPath(
        plan.source.locator)) return;
    final playing = !session.transport.value.ended &&
        session.transport.value.observed == KernelTransport.playing;
    if (playing == (_heartbeat != null)) return;
    _heartbeat?.cancel();
    _heartbeat = playing
        ? Timer.periodic(
            const Duration(seconds: 5), (_) => _enqueue('progress'))
        : null;
  }

  void _enqueue(String kind) {
    _pending = {...sample(), 'kind': kind};
    _sending ??= _drain();
  }

  Future<void> _drain() async {
    // Yield before draining so _sending is installed even for sync fakes.
    await Future<void>.value();
    try {
      if (_startSample case final start?) {
        _startSample = null;
        await _send('start', start);
      }
      while (_pending != null) {
        final data = _pending!;
        _pending = null;
        await _send(data['kind'] as String, data);
      }
    } finally {
      _sending = null;
    }
  }

  Future<void> _send(String kind, JsonMap data) async {
    try {
      await plan.progress?.send(kind, data);
      final length = data['durationMs'] as int;
      await SharedRemotePlaybackSyncService.instance.syncProgress(
          videoUrl: plan.source.locator,
          positionMs: data['positionMs'] as int,
          durationMs: length,
          progress: length > 0 ? (data['positionMs'] as int) / length : 0,
          force: true);
      lastReport = data;
      _lastAt = _elapsed.elapsedMilliseconds;
      lastError = null;
    } catch (error) {
      lastError = error.runtimeType.toString();
      debugPrint('[NextSource] remote progress: $lastError');
    }
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _heartbeat?.cancel();
    await _events.cancel();
    await _sending;
    if (_started) await _send('stop', sample());
    try {
      await plan.progress?.stopTranscoding();
    } catch (error) {
      lastError = error.runtimeType.toString();
    }
  }
}
