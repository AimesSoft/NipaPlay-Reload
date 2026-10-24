import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/utils/network_settings.dart';
import '../media/identity_store.dart';
import '../network/dandanplay_gateway.dart';
import 'capability.dart';
import 'executors.dart';
import 'host.dart';
import 'service.dart';
import 'source.dart';
import 'sources.dart';
import 'store.dart';
import 'local_source.dart';
import 'sidecar.dart';
import '../player/next_playback.dart';
import '../player/perf/counters.dart';

/// Forwards track operations to what plays while Next is open.
final class _HostPlayerPort implements PlaybackDanmakuPort {
  PlaybackDanmakuPort? _delegate;
  void attach(PlaybackDanmakuPort delegate) => _delegate = delegate;
  void detach() => _delegate = null;
  @override
  List<JsonMap> get registry => _delegate?.registry ?? const [];
  @override
  bool updateTrack(
          DanmakuPlaybackTarget target, String trackId, JsonMap properties) =>
      _delegate?.updateTrack(target, trackId, properties) ?? false;
  @override
  bool reuse(DanmakuPlaybackTarget target, JsonMap binding) =>
      _delegate?.reuse(target, binding) ?? false;
  @override
  Future<bool> restoreClassic(
          DanmakuPlaybackTarget target, JsonMap binding) async =>
      await _delegate?.restoreClassic(target, binding) ?? false;
  @override
  DanmakuPlaybackTarget? get target => _delegate?.target;
  @override
  Set<String> get managedTracks => _delegate?.managedTracks ?? const <String>{};
  @override
  JsonMap? loaded(String bindingId) => _delegate?.loaded(bindingId);
  @override
  bool install(DanmakuPlaybackTarget target, JsonMap binding,
          List<DanmakuEntry> entries, {int startMs = 0, int? endMs}) =>
      _delegate?.install(target, binding, entries,
          startMs: startMs, endMs: endMs) ??
      false;
  @override
  void remove(String bindingId) => _delegate?.remove(bindingId);
}

/// The source is restricted to the NipaPlay gateway hosts it may be routed to.
final List<String> _gatewayHosts = [
  for (final server in NetworkSettings.officialServers) Uri.parse(server).host
];

final class DanmakuRuntime {
  DanmakuRuntime._(this.service, this._port, this._clients)
      : executors = danmakuExecutors(service),
        capability = DanmakuCapability(service);
  final DanmakuService service;
  final List<JobExecutor> executors;
  final DanmakuCapability capability;
  final _HostPlayerPort _port;
  final List<http.Client> _clients;
  Future<void> _restoring = Future.value();
  bool _busy = false, _stopped = false, _dirty = false;
  Harness? _harness;
  NextPlayback? _playback;
  ({String? path, int generation, bool durationKnown})? _media;
  Future<bool> Function(String, String, Object?)? remoteControl;
  Future<void> _controls = Future.value();
  late final sidecars = SidecarIndexer(service.store, () async {
    _changed();
  });
  Future<void> startIndexing() => sidecars.start();
  Future<void> pauseIndexing() => sidecars.pause();
  Future<void> stopIndexing() => sidecars.close();
  static Future<DanmakuRuntime> create(IdentityStore identities,
      {Future<String> Function(String path)? authorizeLocalFile}) async {
    final ddp = DandanplayHttpClient();
    final host = HttpDanmakuHost(dandanplay: DandanplayGateway(client: ddp));
    final port = _HostPlayerPort();
    DanmakuSource scoped(DanmakuSource Function(DanmakuHost) build) =>
        build(ScopedDanmakuHost(host, build(host).describe));
    final service =
        DanmakuService(store: DanmakuStore(identities), player: port, sources: [
      scoped((h) => DandanplayDanmakuSource(h, allowedHosts: _gatewayHosts)),
      if (authorizeLocalFile != null) LocalDanmakuSource(authorizeLocalFile)
    ]);
    return DanmakuRuntime._(service, port, [ddp]);
  }

  void attach(TaskEngine engine) => service.engine = engine;

  Future<void> _control(String id, String operation, Object? value) async {
    if (await remoteControl?.call(id, operation, value) == true) return;
    final previous = _controls;
    final done = Completer<void>();
    _controls = done.future;
    await previous;
    try {
      final binding = await service.store.binding(id);
      final action = switch (operation) {
        'offset' => 'danmaku.offset',
        'enabled' => 'danmaku.set_enabled',
        'detach' => 'danmaku.detach',
        _ => throw StateError('Unknown track control')
      };
      final outcome = await _harness!.invokeJson(
          action,
          {
            'bindingId': id,
            'revision': binding['revision'],
            if (operation == 'offset')
              'offsetMs': ((value as double) * 1000).round(),
            if (operation == 'enabled') 'enabled': value
          },
          Invocation(origin: 'gui'));
      if (outcome is Failed) throw outcome.failure;
    } finally {
      done.complete();
    }
  }

  /// Binds what plays and follows it: another media (or the same one
  /// reopened, or its length becoming known) and the danmaku tracks
  /// changing restore the bound danmaku; nothing else does. Call after
  /// `engine.start()`.
  void startRestoring(Harness harness, NextPlayback playback) {
    _unbind();
    _stopped = false;
    _harness = harness;
    _playback = playback;
    playback.localDanmakuLoader = (path) async {
      if (path.contains('://')) return false;
      final id = await service.store.identities.ensureFile(path);
      final found = await sidecars.inspect(id, path);
      await service.refreshCurrent();
      return found;
    };
    _port.attach(playback.danmakuPort(
        requestChange: (id, operation, value) =>
            _control(id, operation, value)));
    playback.media.addListener(_mediaChanged);
    playback.danmakuVersion.addListener(_changed);
    _mediaChanged();
  }

  void _unbind() {
    _playback?.media.removeListener(_mediaChanged);
    _playback?.danmakuVersion.removeListener(_changed);
    _playback?.localDanmakuLoader = null;
    _media = null;
  }

  void _mediaChanged() {
    final media = _playback!.media.value;
    final now = (
      path: media.path,
      generation: media.generation,
      durationKnown: media.durationKnown
    );
    if (now == _media) return;
    _media = now;
    _changed();
  }

  void _changed() => PlayerPerf.span('danmaku.changed', _change);
  void _change() {
    if (_stopped) return;
    if (_busy) {
      _dirty = true;
      return;
    }
    _busy = true;
    _restoring = service.refreshCurrent().then((_) {
      _busy = false;
      if (_dirty) {
        _dirty = false;
        _change();
      }
    }, onError: (Object error, StackTrace stack) {
      _busy = false;
      FlutterError.reportError(FlutterErrorDetails(
          exception: error, stack: stack, library: 'Next danmaku restoration'));
    });
  }

  Future<void> stopRestoring() async {
    _stopped = true;
    _unbind();
    await _restoring;
    await _controls;
    _port.detach();
    _playback = null;
    _harness = null;
  }

  void close() {
    for (final client in _clients) {
      client.close();
    }
  }
}
