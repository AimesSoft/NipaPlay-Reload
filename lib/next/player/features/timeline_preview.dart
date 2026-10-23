import 'dart:async';
import 'dart:typed_data';

import '../../capabilities/media_frames.dart';
import '../../capabilities/media_frames_erika.dart';
import 'capture.dart';
import 'kernel_features.dart';

/// Demand driven, one decode in flight and one latest request. The headless
/// frame decoder never takes the playback lease or creates a playback core.
final class TimelinePreview {
  TimelinePreview({FrameEngine? engine})
      : engine = engine ?? const ErikaFrameEngine();
  final FrameEngine engine;
  FrameSource? _source;
  String? _uri;
  int _generation = 0;
  _PreviewRequest? _pending;
  int? _cachedAt;
  Uint8List? _cached;
  Future<void>? _running;
  Future<void>? _resetting;
  bool enabled = false;
  bool _disposed = false;

  Future<Uint8List?> at(String uri, Duration position) {
    if (!enabled || _disposed || _resetting != null) return Future.value();
    final at = (position.inMilliseconds ~/ 1000) * 1000;
    if (_uri == uri && _cachedAt == at) return Future.value(_cached);
    _pending?.done.complete(null);
    final request = _pending = _PreviewRequest(uri, at, _generation);
    _running ??= _drain().whenComplete(() => _running = null);
    return request.done.future;
  }

  Future<void> _drain() async {
    while (_pending != null) {
      final request = _pending!;
      _pending = null;
      final _PreviewRequest(:uri, :at, :generation, :done) = request;
      try {
        if (!enabled || _disposed || generation != _generation) {
          done.complete(null);
          continue;
        }
        if (_uri != uri) {
          await _source?.close();
          _source = null;
          _uri = uri;
          _cached = null;
          _cachedAt = null;
          final source = await engine.open(uri,
              width: 320, timeout: const Duration(seconds: 10));
          if (generation != _generation || _disposed) {
            await source.close();
            done.complete(null);
            continue;
          }
          _source = source;
        }
        if (_pending != null || generation != _generation) {
          done.complete(null);
          continue;
        }
        final frame = await _source!.frameAt(at);
        final bytes = frame.png ??
            await PlaybackCapture.encodePicture(
                KernelPicture(frame.width, frame.height, frame.rgba),
                jpeg: true,
                quality: 65);
        if (generation != _generation || _pending != null || !enabled) {
          done.complete(null);
          continue;
        }
        _cachedAt = at;
        _cached = bytes;
        done.complete(bytes);
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    }
  }

  Future<void> reset() {
    _generation++;
    _pending?.done.complete(null);
    _pending = null;
    _cachedAt = null;
    _cached = null;
    return _resetting ??= () async {
      await _running;
      final source = _source;
      _source = null;
      _uri = null;
      await source?.close();
    }()
        .whenComplete(() => _resetting = null);
  }

  Future<void> dispose() async {
    _disposed = true;
    await reset();
  }
}

final class _PreviewRequest {
  _PreviewRequest(this.uri, this.at, this.generation);
  final String uri;
  final int at;
  final int generation;
  final done = Completer<Uint8List?>();
}
