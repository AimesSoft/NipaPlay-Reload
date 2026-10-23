import 'dart:async';
import 'dart:typed_data';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:nipa_harness/nipa_harness.dart';

import 'media_frames.dart';

/// A media Erika keeps open for pictures: the shape of
/// [ErikaFrameExportSession], so a test can stand in for it.
abstract interface class ErikaFrameSession {
  Future<ErikaExportedFrame> frameAt(
    Duration position, {
    int width,
    int height,
    ErikaFrameFormat format,
  });

  Future<void> close();
}

/// Opens [uri] in Erika's frame export.
typedef ErikaFrameSessionOpener = Future<ErikaFrameSession> Function(
    String uri);

Future<ErikaFrameSession> _openErikaSession(String uri) async =>
    _ErikaFrameSessionHandle(await ErikaFrameExportSession.open(uri));

final class _ErikaFrameSessionHandle implements ErikaFrameSession {
  _ErikaFrameSessionHandle(this._session);
  final ErikaFrameExportSession _session;

  @override
  Future<ErikaExportedFrame> frameAt(
    Duration position, {
    int width = 0,
    int height = 0,
    ErikaFrameFormat format = ErikaFrameFormat.png,
  }) =>
      _session.frameAt(position, width: width, height: height, format: format);

  @override
  Future<void> close() => _session.close();
}

/// Frames from Erika's own headless export: the media is opened once by an
/// independent demuxer and software decoder inside Erika (no player, nothing
/// shared with what is playing), every picture is taken from that one open
/// media, scaled there, and handed back as RGBA, or as a PNG Erika encoded
/// itself when png is asked for. Pictures asked for in ascending time order
/// are decoded on from one to the next without seeking again. The work runs
/// off the UI thread.
final class ErikaFrameEngine implements FrameEngine {
  const ErikaFrameEngine({this.opener = _openErikaSession});

  final ErikaFrameSessionOpener opener;

  @override
  String get name => 'erika';

  @override
  Future<FrameSource> open(String source,
      {int? width,
      int? maxEdge,
      String format = 'jpeg',
      required Duration timeout}) async {
    final ErikaFrameSession session;
    try {
      session = await opener(source).timeout(timeout);
    } on StateError catch (error) {
      throw Failure(FailureCode.unavailable, error.message);
    }
    // Opening takes the first picture at the smallest size: Erika reports the
    // media's duration and video size with it.
    final ErikaExportedFrame first;
    try {
      first = await session
          .frameAt(Duration.zero,
              width: 16, height: 16, format: ErikaFrameFormat.rgba)
          .timeout(timeout);
    } on StateError catch (error) {
      await session.close();
      throw Failure(FailureCode.unavailable, error.message);
    } catch (_) {
      await session.close();
      rethrow;
    }
    return _ErikaFrameSource(
      session,
      width: width ?? maxEdge!,
      height: width == null ? maxEdge! : 0,
      png: format == 'png',
      durationMs: first.duration?.inMilliseconds,
      videoWidth: first.sourceWidth > 0 ? first.sourceWidth : null,
      videoHeight: first.sourceHeight > 0 ? first.sourceHeight : null,
    );
  }
}

final class _ErikaFrameSource implements FrameSource {
  _ErikaFrameSource(
    this._session, {
    required int width,
    required int height,
    required bool png,
    required this.durationMs,
    required this.videoWidth,
    required this.videoHeight,
  })  : _width = width,
        _height = height,
        _png = png;

  final ErikaFrameSession _session;

  /// Bounds handed to Erika: a width, or a box for the longest edge. Erika
  /// keeps the aspect ratio and never enlarges past the video.
  final int _width;
  final int _height;
  final bool _png;

  @override
  String get engine => 'erika';
  @override
  final int? durationMs;
  @override
  final int? videoWidth;
  @override
  final int? videoHeight;

  @override
  Future<RawFrame> frameAt(int atMs) async {
    final ErikaExportedFrame frame;
    try {
      frame = await _session.frameAt(Duration(milliseconds: atMs),
          width: _width,
          height: _height,
          format: _png ? ErikaFrameFormat.png : ErikaFrameFormat.rgba);
    } on StateError catch (error) {
      throw FrameFailure(
          error.message.contains('not before the end')
              ? 'beyond_duration'
              : 'decode_failed',
          error.message);
    }
    return RawFrame(
      width: frame.width,
      height: frame.height,
      rgba: _png ? Uint8List(0) : frame.bytes,
      png: _png ? frame.bytes : null,
      timestampMs: frame.timestamp.inMilliseconds,
    );
  }

  @override
  Future<void> close() => _session.close();
}
