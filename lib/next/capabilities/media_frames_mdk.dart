import 'dart:async';
import 'dart:typed_data';

import 'package:fvp/mdk.dart' as mdk;
import 'package:nipa_harness/nipa_harness.dart';

import 'media_frames.dart';

/// Frames from a background MDK player of its own, the way Classic's timeline
/// preview takes them. The player is muted, paused, bound to a small texture of
/// the requested size, and sought with exact (non-keyframe) seeks; it shares
/// nothing with the player that is playing.
final class MdkFrameEngine implements FrameEngine {
  const MdkFrameEngine();

  @override
  String get name => 'mdk';

  @override
  Future<FrameSource> open(String source,
      {int? width,
      int? maxEdge,
      String format = 'jpeg',
      required Duration timeout}) async {
    final player = mdk.Player();
    try {
      player.mute = true;
      player.media = source;
      final result = await player.prepare().timeout(timeout);
      final info = player.mediaInfo;
      final video = info.video;
      if (result < 0 || video == null || video.isEmpty) {
        throw Failure(
            FailureCode.unavailable,
            result < 0
                ? 'MDK could not open this media (code $result).'
                : 'This media has no video stream.');
      }
      final codec = video.first.codec;
      final sourceWidth = codec.width;
      final sourceHeight = codec.height;
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        throw const Failure(
            FailureCode.unavailable, 'The video size is not known.');
      }
      var targetWidth = width ??
          (sourceWidth >= sourceHeight
              ? maxEdge!
              : (maxEdge! * sourceWidth / sourceHeight).round());
      if (targetWidth > sourceWidth) targetWidth = sourceWidth;
      final targetHeight = (targetWidth * sourceHeight / sourceWidth).round();
      final even = _Size(targetWidth.clamp(2, 1 << 14) & ~1,
          targetHeight.clamp(2, 1 << 14) & ~1);
      player.state = mdk.PlaybackState.paused;
      final texture = await player
          .updateTexture(width: even.width, height: even.height)
          .timeout(timeout);
      if (texture < 0) {
        throw const Failure(FailureCode.unavailable,
            'MDK could not create its offscreen surface for this video.');
      }
      return _MdkFrameSource(
          player,
          even,
          info.duration > 0 ? info.duration : null,
          sourceWidth,
          sourceHeight);
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }
}

final class _Size {
  const _Size(this.width, this.height);
  final int width;
  final int height;
}

final class _MdkFrameSource implements FrameSource {
  _MdkFrameSource(this._player, this._size, this.durationMs, this.videoWidth,
      this.videoHeight);
  final mdk.Player _player;
  final _Size _size;
  var _warmed = false;
  var _closed = false;

  @override
  String get engine => 'mdk';

  @override
  final int? durationMs;
  @override
  final int? videoWidth;
  @override
  final int? videoHeight;

  @override
  Future<RawFrame> frameAt(int atMs) async {
    // fromStart without keyFrame: an exact seek, so the picture is the one at
    // atMs and not the nearest keyframe before it.
    final landed = await _player.seek(
        position: atMs, flags: const mdk.SeekFlag(mdk.SeekFlag.fromStart));
    if (landed < 0) {
      throw FrameFailure(
          'decode_failed', 'MDK could not seek to $atMs ms (code $landed).');
    }
    // Let the renderer present the sought frame before it is read back.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!_warmed) {
      // The first read-back of a player can come back empty (Classic's
      // timeline preview does the same).
      _warmed = true;
      await _player.snapshot(width: _size.width, height: _size.height);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    Uint8List? bytes;
    for (var attempt = 0; attempt < 3; attempt++) {
      bytes = await _player.snapshot(width: _size.width, height: _size.height);
      if (bytes != null && bytes.length == _size.width * _size.height * 4) {
        return RawFrame(
            width: _size.width,
            height: _size.height,
            rgba: bytes,
            timestampMs: _player.position);
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    throw FrameFailure(
        'decode_failed',
        bytes == null
            ? 'MDK returned no picture at $atMs ms.'
            : 'MDK returned ${bytes.length} bytes, not ${_size.width}x${_size.height} RGBA.');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _player.dispose();
  }
}
