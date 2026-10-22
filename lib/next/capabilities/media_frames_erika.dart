import 'dart:async';
import 'dart:typed_data';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:nipa_harness/nipa_harness.dart';

import 'media_frames.dart';

/// Erika's single-frame export, as erika_flutter gives it.
typedef ErikaFrameExporter = Future<ErikaExportedFrame> Function(
  String uri, {
  required Duration position,
  int width,
  int height,
  ErikaFrameFormat format,
});

/// Frames from Erika's own headless export: each picture is decoded by an
/// independent demuxer and software decoder inside Erika (no player, nothing
/// shared with what is playing), scaled there, and handed back as RGBA, or
/// as a PNG Erika encoded itself when png is asked for. The work runs off
/// the UI thread.
final class ErikaFrameEngine implements FrameEngine {
  const ErikaFrameEngine({this.exporter = ErikaPlayer.exportFrame});

  final ErikaFrameExporter exporter;

  @override
  String get name => 'erika';

  @override
  Future<FrameSource> open(String source,
      {int? width,
      int? maxEdge,
      String format = 'jpeg',
      required Duration timeout}) async {
    // Opening takes the first picture at the smallest size: Erika reads the
    // media, and reports its duration and video size.
    final ErikaExportedFrame first;
    try {
      first = await exporter(source,
              position: Duration.zero,
              width: 16,
              height: 16,
              format: ErikaFrameFormat.rgba)
          .timeout(timeout);
    } on StateError catch (error) {
      throw Failure(FailureCode.unavailable, error.message);
    }
    return _ErikaFrameSource(
      exporter,
      source,
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
    this._exporter,
    this._source, {
    required int width,
    required int height,
    required bool png,
    required this.durationMs,
    required this.videoWidth,
    required this.videoHeight,
  })  : _width = width,
        _height = height,
        _png = png;

  final ErikaFrameExporter _exporter;
  final String _source;

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
      frame = await _exporter(_source,
          position: Duration(milliseconds: atMs),
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
  Future<void> close() async {}
}
