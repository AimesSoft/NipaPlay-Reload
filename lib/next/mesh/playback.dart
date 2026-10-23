import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import '../../player_abstraction/player_factory.dart';
import '../next_core.dart';
import '../player/next_playback.dart';

/// Attaches Mesh observations to what plays only while Next is open.
final class MeshPlayback {
  MeshPlayback(this.core, this.player);
  final NextCore core;
  final NextPlayback player;
  final _loading = <String, Future<JsonMap>>{};
  final _bindings = <String, JsonMap>{};
  Timer? _timer;
  String? _last;
  Future<void> _writing = Future.value();
  bool _closed = false;
  void attach() {
    core.danmaku.service.remoteTracks = tracks;
    core.danmaku.remoteControl = control;
    core.subtitles.remoteLoader = subtitles;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _writing = _writing.then((_) => _observe());
      unawaited(_writing.then<void>((_) {},
          onError: (Object e, StackTrace s) => FlutterError.reportError(
              FlutterErrorDetails(
                  exception: e, stack: s, library: 'Mesh progress'))));
    });
  }

  Future<void> _observe() async {
    if (_closed) return;
    final path = player.path;
    if (path == null || player.duration.inMilliseconds <= 0) return;
    final library = core.uiData.meshLibrary!;
    final remote = library.playback[path];
    if (remote == null) return;
    final position = player.position.inMilliseconds,
        duration = player.duration.inMilliseconds;
    final sample = '$path:$position:$duration';
    if (_last == sample) return;
    _last = sample;
    final start = remote['startMs'] as int? ?? 0,
        end = remote['endMs'] as int? ?? duration;
    final elapsed = (position - start).clamp(0, end - start);
    await library.recordProgress(remote['episodeId'] as String,
        end == start ? 0 : elapsed / (end - start),
        positionMs: elapsed, durationMs: end - start);
  }

  Future<JsonMap?> _bundle(String path) async {
    final library = core.uiData.meshLibrary!;
    final context = library.playback[path];
    if (context == null || context['bundle'] == null) return null;
    return _loading.putIfAbsent(path, () async {
      final peer = context['deviceId'] as String;
      final bundle = jsonDecode(jsonEncode(context['bundle'])) as JsonMap;
      for (final track in (bundle['tracks'] as List).cast<JsonMap>()) {
        final binding = track['binding'] as JsonMap;
        final original = binding['id'] as String;
        binding['id'] = 'mesh-binding:$peer:$original';
        _bindings[binding['id'] as String] = {
          'deviceId': peer,
          'bindingId': original,
          'binding': binding,
          'path': path
        };
        final file = await library.cacheAsset(peer, track['assetId'] as String,
            name: 'entries.json');
        track['entries'] = jsonDecode(await File(file).readAsString());
      }
      for (final track in (bundle['subtitles'] as List).cast<JsonMap>()) {
        if (track['assetId'] == null) continue;
        final file = await library.cacheAsset(peer, track['assetId'] as String,
            name: track['path'] as String);
        track['playbackPath'] = file;
        if (track['pairAssetId'] case final String pair) {
          final downloaded =
              await library.cacheAsset(peer, pair, name: 'pair.sub');
          final companion = File(p.setExtension(file, '.sub'));
          if (!await companion.exists())
            await File(downloaded).copy(companion.path);
        }
      }
      return bundle;
    });
  }

  Future<List<JsonMap>?> tracks(String path) async =>
      (await _bundle(path))?['tracks'] == null
          ? null
          : ((await _bundle(path))!['tracks'] as List).cast<JsonMap>();
  Future<bool> subtitles(SubtitleTarget current, String path) async {
    final bundle = await _bundle(path);
    if (bundle == null) return false;
    for (final t in (bundle['subtitles'] as List).cast<JsonMap>()) {
      if (current.path != path) return true;
      if (t['origin'] != 'embedded' && t['available'] == true) {
        await current.offer(t['playbackPath'] as String, t['title'] as String);
        if (t['selected'] == true)
          await current.applyExternal(
              t['playbackPath'] as String, t['title'] as String);
      } else if (t['origin'] == 'embedded' && t['selected'] == true) {
        await current.applyEmbedded(t['index'] as int);
      }
      if (t['selectionBasis'] == 'explicit' &&
          !(bundle['subtitles'] as List)
              .cast<Map>()
              .any((s) => s['selected'] == true))
        await current.clear();
    }
    return true;
  }

  Future<bool> control(String id, String operation, Object? value) async {
    final target = _bindings[id];
    if (target == null) return false;
    final binding = target['binding'] as JsonMap;
    final action = switch (operation) {
      'offset' => 'danmaku.offset',
      'enabled' => 'danmaku.set_enabled',
      'detach' => 'danmaku.detach',
      _ => throw StateError(operation)
    };
    final result = await core.mesh.invoke(
        target['deviceId'] as String,
        action,
        {
          'bindingId': target['bindingId'],
          'revision': binding['revision'],
          if (operation == 'offset')
            'offsetMs': ((value as double) * 1000).round(),
          if (operation == 'enabled') 'enabled': value
        },
        destructive: false);
    if (result is Failed) throw result.failure;
    if (operation == 'detach') {
      final bundle = await _bundle(target['path'] as String);
      (bundle!['tracks'] as List)
          .removeWhere((t) => (t as Map)['binding']['id'] == id);
    } else {
      binding['revision'] = (binding['revision'] as int) + 1;
      binding[operation == 'offset' ? 'offset_ms' : 'enabled'] =
          operation == 'offset'
              ? ((value as double) * 1000).round()
              : value == true
                  ? 1
                  : 0;
    }
    await core.danmaku.service.refreshCurrent();
    return true;
  }

  /// Per-open player properties, never a persistent settings change.
  static void directLoopback(KernelHost host, bool remote) {
    final proxy = remote ? '' : PlayerFactory.getHttpProxy();
    host.player.setProperty('avformat.http_proxy', proxy);
    host.player.setProperty('avio.http_proxy', proxy);
    host.player.setProperty('http-proxy', proxy);
  }

  Future<void> close() async {
    await _observe();
    _closed = true;
    _timer?.cancel();
    await _writing;
    core.danmaku.service.remoteTracks = null;
    core.danmaku.remoteControl = null;
    core.subtitles.remoteLoader = null;
    if (core.uiData.meshLibrary!.playback.containsKey(player.path))
      directLoopback(player.kernelHost, false);
  }
}
