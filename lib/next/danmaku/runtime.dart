import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import '../media/identity_store.dart';
import 'host.dart';
import 'source.dart';
import 'sources.dart';
import 'store.dart';
import 'service.dart';
import 'player_port.dart';

final class DanmakuRuntime {
  DanmakuRuntime._(this.service, this._player, this._clients);
  final DanmakuService service;
  final VideoPlayerState _player;
  final List<http.Client> _clients;
  Future<void> _restoring = Future.value();
  bool _busy = false, _stopped = false, _dirty = false;
  late Harness _harness;
  Future<void> _controls = Future.value();
  static Future<DanmakuRuntime> create(
      IdentityStore identities, VideoPlayerState player,
      {YoukuSessionBridge? youkuSession}) async {
    final public = http.Client(), ddp = DandanplayHttpClient();
    final base = Uri.parse(await DandanplayService.getApiBaseUrl());
    final host = HttpDanmakuHost(
        publicClient: public,
        dandanplayClient: ddp,
        dandanplayBase: base,
        youkuSession: youkuSession,
        dandanplayHeaders: (path) async {
          if (!await DandanplayService.canAccessCurrentServer()) {
            throw const SourceFailure(SourceStatus.authenticationRequired);
          }
          final timestamp =
              DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
          return {
            'X-AppId': DandanplayService.appId,
            'X-Timestamp': '$timestamp',
            'X-Signature': DandanplayService.generateSignature(
                DandanplayService.appId,
                timestamp,
                path,
                await DandanplayService.getAppSecret())
          };
        });
    late DanmakuRuntime runtime;
    DanmakuSource scoped(DanmakuSource Function(DanmakuHost) build) =>
        build(ScopedDanmakuHost(host, build(host).describe));
    final service = DanmakuService(
        store: DanmakuStore(identities),
        host: host,
        player: VideoDanmakuPort(player,
            requestChange: (id, operation, value) =>
                runtime._control(id, operation, value)),
        sources: [
          scoped((h) => DandanplayDanmakuSource(h, allowedHosts: [base.host])),
          scoped(BilibiliDanmakuSource.new),
          scoped(YoukuDanmakuSource.new)
        ]);
    runtime = DanmakuRuntime._(service, player, [public, ddp]);
    return runtime;
  }

  Future<void> _control(String id, String operation, Object? value) async {
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
      final outcome = await _harness.invokeJson(
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

  void startRestoring(Harness harness) {
    _harness = harness;
    _player.addListener(_changed);
    _changed();
  }

  void _changed() {
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
        _changed();
      }
    }, onError: (Object error, StackTrace stack) {
      _busy = false;
      FlutterError.reportError(FlutterErrorDetails(
          exception: error, stack: stack, library: 'Next danmaku restoration'));
    });
  }

  Future<void> stopRestoring() async {
    _stopped = true;
    _player.removeListener(_changed);
    await _restoring;
    await _controls;
  }

  void close() {
    for (final client in _clients) {
      client.close();
    }
  }
}
