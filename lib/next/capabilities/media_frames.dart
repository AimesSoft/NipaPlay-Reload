import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

import 'classic_action.dart';

/// One decoded picture: RGBA8, tightly packed (`width * height * 4` bytes),
/// or a PNG file the engine encoded itself ([png]).
final class RawFrame {
  const RawFrame(
      {required this.width,
      required this.height,
      required this.rgba,
      required this.timestampMs,
      this.png});
  final int width;
  final int height;
  final Uint8List rgba;

  /// Where in the media this picture actually is, as the engine reports it.
  final int timestampMs;

  /// The picture as a PNG file, when the engine encoded it; [rgba] is then
  /// empty.
  final Uint8List? png;
}

/// A single frame that could not be taken, with a stable reason code.
final class FrameFailure implements Exception {
  const FrameFailure(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

/// A media opened by an engine for picking frames. It is private to one
/// media.frames call and never shares state with what is being played.
abstract interface class FrameSource {
  /// The engine that opened this media.
  String get engine;
  int? get durationMs;
  int? get videoWidth;
  int? get videoHeight;

  /// The picture at [atMs]; throws [FrameFailure] when there is none.
  Future<RawFrame> frameAt(int atMs);
  Future<void> close();
}

abstract interface class FrameEngine {
  String get name;

  /// Opens [source] (an absolute path or URL). Exactly one of [width] and
  /// [maxEdge] is set; the engine decodes at that size and keeps the aspect
  /// ratio. [format] is the file format the pictures end up in (jpeg or png),
  /// for an engine that can encode it itself. Throws [Failure] when the media
  /// cannot be opened.
  Future<FrameSource> open(String source,
      {int? width,
      int? maxEdge,
      String format = 'jpeg',
      required Duration timeout});
}

/// The first of [engines] that opens the media; the others are fallbacks.
/// A session opened by a later engine reports why the earlier ones did not
/// open ([FallbackFrameSource]).
final class PreferredFrameEngine implements FrameEngine {
  PreferredFrameEngine(this.engines) : assert(engines.isNotEmpty);
  final List<FrameEngine> engines;

  @override
  String get name => engines.first.name;

  @override
  Future<FrameSource> open(String source,
      {int? width,
      int? maxEdge,
      String format = 'jpeg',
      required Duration timeout}) async {
    final skipped = <({String engine, String error})>[];
    Object? firstError;
    StackTrace? firstStack;
    for (final engine in engines) {
      try {
        final session = await engine.open(source,
            width: width, maxEdge: maxEdge, format: format, timeout: timeout);
        return skipped.isEmpty ? session : FallbackFrameSource(session, skipped);
      } catch (error, stack) {
        if (firstError == null) {
          firstError = error;
          firstStack = stack;
        }
        skipped.add((engine: engine.name, error: _reason(error)));
      }
    }
    Error.throwWithStackTrace(firstError!, firstStack!);
  }

  static String _reason(Object error) => switch (error) {
        Failure(:final message) => message,
        UnsupportedError(:final message) => message ?? '$error',
        StateError(:final message) => message,
        _ => '$error',
      };
}

/// A session of a fallback engine, with the engines tried before it.
final class FallbackFrameSource implements FrameSource {
  FallbackFrameSource(this._inner, this.skipped);
  final FrameSource _inner;
  final List<({String engine, String error})> skipped;

  @override
  String get engine => _inner.engine;
  @override
  int? get durationMs => _inner.durationMs;
  @override
  int? get videoWidth => _inner.videoWidth;
  @override
  int? get videoHeight => _inner.videoHeight;
  @override
  Future<RawFrame> frameAt(int atMs) => _inner.frameAt(atMs);
  @override
  Future<void> close() => _inner.close();
}

const mediaFramesMaxCount = 60;
const mediaFramesDefaultMaxEdge = 640;
const mediaFramesMaxEdge = 3840;
const mediaFramesMinEveryMs = 100;
const mediaFramesDefaultTimeoutMs = 60000;
const mediaFramesMaxTimeoutMs = 300000;
const mediaFramesFrameTimeout = Duration(seconds: 12);
const mediaFramesOpenTimeout = Duration(seconds: 20);

final class MediaFramesCapability implements Capability {
  MediaFramesCapability({
    required FrameEngine engine,
    required Future<Directory> Function() outputRoot,
    Future<String?> Function(int animeId, int episodeId)? episodePath,
    DateTime Function()? now,
    Duration frameTimeout = mediaFramesFrameTimeout,
    Duration openTimeout = mediaFramesOpenTimeout,
  }) : actions = [
          ClassicAction(
              spec,
              (input, invocation) => _MediaFrames(engine, outputRoot,
                      episodePath, now ?? DateTime.now, frameTimeout, openTimeout)
                  .run(input, invocation))
        ];

  @override
  final List<Action> actions;

  static const spec = ActionSpec(
    id: 'media.frames',
    title: 'Take pictures from a video file at given times',
    description:
        'Decode single pictures from a video at the times asked for and write each to a local JPEG or PNG file, '
        'so that you or the user can look at them. Examples: a few pictures of one episode, the same stretch of two '
        'episodes side by side, the picture at a time the user mentions. '
        'The media is given as path (absolute local path, file:// URL, or the http(s) address returned by '
        'media.library.readable / media.mesh_files.readable) or as animeId + episodeId of a recorded episode. '
        'The times are atMs, a list of milliseconds from the start of the media, or range {startMs,endMs,everyMs}, '
        'which takes startMs, startMs+everyMs, … up to and including endMs; everyMs is at least 100. '
        'Give exactly one of atMs and range; at most 60 pictures per call, more is refused without taking any. '
        'Size: width is the output width in pixels, or maxEdge is the longest side (default 640, at most 3840); '
        'the aspect ratio is kept and the picture is never enlarged beyond the video. format is jpeg (default) or png. '
        'timeoutMs bounds the whole call (default 60000, at most 300000). '
        'Each frame in the result carries requestedMs, timestampMs (where the picture really is, in milliseconds), '
        'path, width, height, bytes and mimeType; a frame that could not be taken carries requestedMs and error '
        '{code,message} instead, and the other frames are still returned. Error codes: beyond_duration, '
        'decode_failed, timeout, skipped_after_timeout. durationMs and the video size are facts of the file when known. '
        'Playback is not touched: the pictures come from a separate decoder, nothing is paused, sought or reopened, '
        'and the decoder is released before the call returns. engine names the decoder that took them: erika (Erika\'s '
        'own frame export) where Erika can open the media, else mdk; engineFallback lists the engines that could not '
        '(engine, error). The files are temporary, on the device that ran the call, '
        'and are removed after a day. The pictures say nothing about what is in them; deciding that is up to you.',
    effect: Effect.read,
    input: ObjectSchema({
      'path': StringSchema(minLength: 1),
      'animeId': IntegerSchema(minimum: 1),
      'episodeId': IntegerSchema(minimum: 1),
      'atMs': ArraySchema(IntegerSchema(minimum: 0),
          minItems: 1,
          maxItems: mediaFramesMaxCount,
          description: 'Milliseconds from the start; 1–60 entries.'),
      'range': ObjectSchema({
        'startMs': IntegerSchema(minimum: 0),
        'endMs': IntegerSchema(minimum: 0),
        'everyMs': IntegerSchema(minimum: mediaFramesMinEveryMs),
      }, required: [
        'startMs',
        'endMs',
        'everyMs'
      ]),
      'width': IntegerSchema(minimum: 16, maximum: mediaFramesMaxEdge),
      'maxEdge': IntegerSchema(minimum: 16, maximum: mediaFramesMaxEdge),
      'format': StringSchema(values: ['jpeg', 'png']),
      'timeoutMs':
          IntegerSchema(minimum: 1000, maximum: mediaFramesMaxTimeoutMs),
    }, oneOfRequired: [
      ['path'],
      ['animeId', 'episodeId'],
    ]),
    output: ObjectSchema({
      'source': StringSchema(),
      'durationMs': IntegerSchema(nullable: true),
      'videoWidth': IntegerSchema(nullable: true),
      'videoHeight': IntegerSchema(nullable: true),
      'engine': StringSchema(),
      'engineFallback': ArraySchema(ObjectSchema({
        'engine': StringSchema(),
        'error': StringSchema(),
      }, required: [
        'engine',
        'error'
      ])),
      'requested': IntegerSchema(),
      'taken': IntegerSchema(),
      'elapsedMs': IntegerSchema(),
      'frames': ArraySchema(ObjectSchema({
        'requestedMs': IntegerSchema(),
        'timestampMs': IntegerSchema(),
        'path': StringSchema(),
        'width': IntegerSchema(),
        'height': IntegerSchema(),
        'bytes': IntegerSchema(),
        'mimeType': StringSchema(),
        'error': ObjectSchema({
          'code': StringSchema(),
          'message': StringSchema(),
        }, required: [
          'code',
          'message'
        ]),
      }, required: [
        'requestedMs'
      ])),
    }, required: [
      'source',
      'engine',
      'requested',
      'taken',
      'frames'
    ]),
  );
}

/// Frame times implied by the input, validated; throws [Failure] otherwise.
List<int> mediaFrameTimes(JsonMap input) {
  final at = input['atMs'];
  final range = input['range'];
  if ((at == null) == (range == null)) {
    throw const Failure(FailureCode.invalidInput,
        'Give exactly one of atMs (a list of milliseconds) and range {startMs,endMs,everyMs}.');
  }
  if (at != null) {
    final times = [for (final value in at as List) (value as num).toInt()];
    if (times.isEmpty) {
      throw const Failure(FailureCode.invalidInput, 'atMs is empty.');
    }
    if (times.length > mediaFramesMaxCount) {
      throw Failure(FailureCode.invalidInput,
          'atMs has ${times.length} times; at most $mediaFramesMaxCount pictures per call. Nothing was taken; split the request.');
    }
    if (times.any((time) => time < 0)) {
      throw const Failure(
          FailureCode.invalidInput, 'atMs must not contain negative times.');
    }
    return times;
  }
  final map = range as Map;
  final start = (map['startMs'] as num).toInt();
  final end = (map['endMs'] as num).toInt();
  final every = (map['everyMs'] as num).toInt();
  if (start < 0 || end < start) {
    throw const Failure(FailureCode.invalidInput,
        'range needs 0 <= startMs <= endMs.');
  }
  if (every < mediaFramesMinEveryMs) {
    throw const Failure(
        FailureCode.invalidInput, 'range.everyMs must be at least 100.');
  }
  final count = (end - start) ~/ every + 1;
  if (count > mediaFramesMaxCount) {
    throw Failure(FailureCode.invalidInput,
        'range would take $count pictures; at most $mediaFramesMaxCount per call. Nothing was taken; widen everyMs or split the range.');
  }
  return [for (var i = 0; i < count; i++) start + i * every];
}

final class _MediaFrames {
  _MediaFrames(this.engine, this.outputRoot, this.episodePath, this.now,
      this.frameTimeout, this.openTimeout);
  final FrameEngine engine;
  final Future<Directory> Function() outputRoot;
  final Future<String?> Function(int, int)? episodePath;
  final DateTime Function() now;
  final Duration frameTimeout;
  final Duration openTimeout;

  /// One decoder at a time: a second call waits instead of running a second
  /// decode of a (possibly 4K) file beside the first.
  static Future<void> _tail = Future.value();

  Future<JsonMap> run(JsonMap input, Invocation invocation) async {
    final times = mediaFrameTimes(input);
    final width = (input['width'] as num?)?.toInt();
    final maxEdge = (input['maxEdge'] as num?)?.toInt();
    if (width != null && maxEdge != null) {
      throw const Failure(
          FailureCode.invalidInput, 'Give width or maxEdge, not both.');
    }
    final format = input['format'] as String? ?? 'jpeg';
    final timeout = Duration(
        milliseconds:
            (input['timeoutMs'] as num?)?.toInt() ?? mediaFramesDefaultTimeoutMs);
    final deadline = DateTime.now().add(timeout);
    final source = await _resolveSource(input);

    final previous = _tail;
    final turn = Completer<void>();
    _tail = turn.future;
    try {
      await previous;
      return await _take(source, times, width,
          width == null ? (maxEdge ?? mediaFramesDefaultMaxEdge) : null, format,
          deadline, timeout, invocation);
    } finally {
      turn.complete();
    }
  }

  Future<String> _resolveSource(JsonMap input) async {
    final path = input['path'] as String?;
    final animeId = (input['animeId'] as num?)?.toInt();
    final episodeId = (input['episodeId'] as num?)?.toInt();
    if (path != null && (animeId != null || episodeId != null)) {
      throw const Failure(FailureCode.invalidInput,
          'Give path or animeId + episodeId, not both.');
    }
    if (path == null) {
      if (animeId == null || episodeId == null) {
        throw const Failure(FailureCode.invalidInput,
            'Give path, or both animeId and episodeId.');
      }
      final found = await episodePath?.call(animeId, episodeId);
      if (found == null) {
        throw const Failure(FailureCode.notFound,
            'No recorded file for this episode; open it once or pass path.');
      }
      return _checkLocal(found);
    }
    return _checkLocal(path);
  }

  Future<String> _checkLocal(String raw) async {
    var path = raw;
    final uri = Uri.tryParse(path);
    if (uri != null && uri.scheme == 'file') {
      try {
        path = uri.toFilePath(windows: Platform.isWindows);
      } on UnsupportedError {
        throw const Failure(FailureCode.invalidInput, 'Invalid local file URL.');
      }
    } else if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (uri.host.isEmpty) {
        throw const Failure(
            FailureCode.invalidInput, 'A media URL must include a host.');
      }
      return path;
    } else if (uri != null &&
        uri.scheme.length > 1 &&
        !p.isAbsolute(path)) {
      throw const Failure(FailureCode.invalidInput,
          'Use an absolute local path, a file:// URL, or an http(s) address.');
    }
    if (!p.isAbsolute(path)) {
      throw const Failure(FailureCode.invalidInput, 'Use an absolute file path.');
    }
    if (!await File(path).exists()) {
      throw const Failure(
          FailureCode.notFound, 'The local file does not exist or is inaccessible.');
    }
    return path;
  }

  Future<JsonMap> _take(
      String source,
      List<int> times,
      int? width,
      int? maxEdge,
      String format,
      DateTime deadline,
      Duration timeout,
      Invocation invocation) async {
    final started = DateTime.now();
    Duration remaining() => deadline.difference(DateTime.now());
    final FrameSource session;
    try {
      final budget = remaining();
      session = await engine.open(source,
          width: width,
          maxEdge: maxEdge,
          format: format,
          timeout: budget < openTimeout ? budget : openTimeout);
    } on Failure {
      rethrow;
    } on TimeoutException {
      throw const Failure(FailureCode.unavailable,
          'The media did not open in time.',
          retryable: true);
    } catch (error) {
      throw Failure(FailureCode.unavailable, 'The media could not be opened: $error');
    }
    final directory = await _newDirectory(invocation);
    final results = List<JsonMap?>.filled(times.length, null);
    try {
      // Ascending time order is cheapest for a decoder; the result keeps the
      // order the times were given in.
      final order = [for (var i = 0; i < times.length; i++) i]
        ..sort((a, b) => times[a].compareTo(times[b]));
      var timedOut = false;
      for (final index in order) {
        final at = times[index];
        if (timedOut || remaining() <= Duration.zero) {
          results[index] = _error(at, timedOut ? 'skipped_after_timeout' : 'timeout',
              timedOut
                  ? 'An earlier picture timed out, so this one was not tried.'
                  : 'The call ran out of time (${timeout.inMilliseconds} ms).');
          timedOut = true;
          continue;
        }
        final duration = session.durationMs;
        if (duration != null && duration > 0 && at >= duration) {
          results[index] = _error(at, 'beyond_duration',
              'The media is $duration ms long; $at ms is past its end.');
          continue;
        }
        final budget = remaining();
        try {
          final frame = await session
              .frameAt(at)
              .timeout(budget < frameTimeout ? budget : frameTimeout);
          results[index] =
              await _write(directory, at, frame, format);
        } on TimeoutException {
          timedOut = true;
          results[index] = _error(at, 'timeout',
              'No picture within ${(budget < frameTimeout ? budget : frameTimeout).inMilliseconds} ms.');
        } on FrameFailure catch (failure) {
          results[index] = _error(at, failure.code, failure.message);
        } catch (error) {
          results[index] = _error(at, 'decode_failed', '$error');
        }
      }
    } finally {
      try {
        await session.close();
      } catch (_) {}
    }
    final frames = [for (final result in results) result!];
    return {
      'source': source,
      'durationMs': session.durationMs,
      'videoWidth': session.videoWidth,
      'videoHeight': session.videoHeight,
      'engine': session.engine,
      if (session is FallbackFrameSource)
        'engineFallback': [
          for (final skipped in session.skipped)
            {'engine': skipped.engine, 'error': skipped.error}
        ],
      'requested': times.length,
      'taken': frames.where((frame) => frame['error'] == null).length,
      'elapsedMs': DateTime.now().difference(started).inMilliseconds,
      'frames': frames,
    };
  }

  JsonMap _error(int at, String code, String message) => {
        'requestedMs': at,
        'error': {'code': code, 'message': message},
      };

  Future<Directory> _newDirectory(Invocation invocation) async {
    final root = await outputRoot();
    await root.create(recursive: true);
    await _prune(root);
    final stamp = now().microsecondsSinceEpoch;
    final safe = invocation.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return Directory(p.join(root.path, '$stamp-$safe')).create();
  }

  /// Best effort: frames older than a day are not kept.
  Future<void> _prune(Directory root) async {
    try {
      final cutoff = now().subtract(const Duration(days: 1));
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      }
    } catch (_) {}
  }

  Future<JsonMap> _write(
      Directory directory, int at, RawFrame frame, String format) async {
    final png = format == 'png' ? frame.png : null;
    if (frame.width <= 0 ||
        frame.height <= 0 ||
        (png == null && frame.rgba.length != frame.width * frame.height * 4)) {
      throw const FrameFailure(
          'decode_failed', 'The decoder returned a picture of the wrong size.');
    }
    final Uint8List encoded =
        png ?? await Isolate.run<Uint8List>(() => encodeFrame(frame, format));
    final extension = format == 'png' ? 'png' : 'jpg';
    final file = File(p.join(directory.path, 'frame_${at}ms.$extension'));
    // Two requests for the same time must not overwrite each other.
    final target = await file.exists()
        ? File(p.join(directory.path,
            'frame_${at}ms_${DateTime.now().microsecondsSinceEpoch}.$extension'))
        : file;
    await target.writeAsBytes(encoded, flush: true);
    return {
      'requestedMs': at,
      'timestampMs': frame.timestampMs,
      'path': target.path,
      'width': frame.width,
      'height': frame.height,
      'bytes': encoded.length,
      'mimeType': format == 'png' ? 'image/png' : 'image/jpeg',
    };
  }
}

Uint8List encodeFrame(RawFrame frame, String format) {
  // The pixels may be a view into a larger buffer (a platform channel
  // message): read from where the view starts.
  final image = img.Image.fromBytes(
      width: frame.width,
      height: frame.height,
      bytes: frame.rgba.buffer,
      bytesOffset: frame.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba);
  return format == 'png'
      ? Uint8List.fromList(img.encodePng(image))
      : Uint8List.fromList(img.encodeJpg(image, quality: 85));
}
