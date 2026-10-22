import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/media_frames.dart';

/// Real-file smoke of the whole media.frames pipeline (validation, ordering,
/// size, encoding, files). Frames come from the ffmpeg command line, not from
/// the MDK engine the app uses, because MDK needs the Flutter engine's
/// texture registry and cannot run under `flutter test`. Skipped when the
/// sample file or ffmpeg is missing.
void main() {
  final home = Platform.environment['HOME'];
  final sample = '$home/Library/Application Support/NipaPlay/LabProfiles/'
      'e2e42b/data/downloads/sintel-4k-official/Sintel.2010.2160p.mkv';
  const ffmpeg = '/opt/homebrew/bin/ffmpeg';
  final available = File(sample).existsSync() && File(ffmpeg).existsSync();

  test('three real frames of Sintel at 10 s, 60 s and 120 s', () async {
    final out = Directory('/tmp/media-frames-smoke');
    if (out.existsSync()) out.deleteSync(recursive: true);
    final harness = Harness([
      MediaFramesCapability(
          engine: _FfmpegEngine(ffmpeg),
          outputRoot: () async => out,
          frameTimeout: const Duration(seconds: 60))
    ]);
    final outcome = await harness.invokeJson(
        'media.frames',
        {
          'path': sample,
          'atMs': [10000, 60000, 120000],
          'maxEdge': 640,
          'timeoutMs': 120000,
        },
        Invocation(origin: 'smoke'));
    expect(outcome, isA<Completed>());
    final result = (outcome as Completed).value.toJson();
    // ignore: avoid_print
    print(result);
    final frames = (result['frames'] as List).cast<Map>();
    expect(frames.map((f) => f['requestedMs']), [10000, 60000, 120000]);
    for (final frame in frames) {
      expect(frame['width'], 640);
      expect(frame['height'], 272);
      final file = File(frame['path'] as String);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(5000));
    }
  }, skip: available ? false : 'sample file or ffmpeg missing',
      timeout: const Timeout(Duration(minutes: 5)));
}

class _FfmpegEngine implements FrameEngine {
  _FfmpegEngine(this.ffmpeg);
  final String ffmpeg;
  @override
  String get name => 'ffmpeg-cli (test only)';

  @override
  Future<FrameSource> open(String source,
      {int? width, int? maxEdge, required Duration timeout}) async {
    final probe = await Process.run('/opt/homebrew/bin/ffprobe', [
      '-v', 'error', '-select_streams', 'v:0',
      '-show_entries', 'stream=width,height', '-show_entries', 'format=duration',
      '-of', 'default=nw=1:nk=0', source,
    ]);
    final text = probe.stdout as String;
    int field(String name) =>
        int.parse(RegExp('$name=(\\d+)').firstMatch(text)!.group(1)!);
    final w = field('width'), h = field('height');
    final seconds =
        double.parse(RegExp(r'duration=([\d.]+)').firstMatch(text)!.group(1)!);
    final outW = (width ?? maxEdge!) & ~1;
    final outH = (outW * h / w).round() & ~1;
    return _FfmpegSource(
        ffmpeg, source, outW, outH, (seconds * 1000).round(), w, h);
  }
}

class _FfmpegSource implements FrameSource {
  _FfmpegSource(this.ffmpeg, this.source, this.w, this.h, this.durationMs,
      this.videoWidth, this.videoHeight);
  final String ffmpeg, source;
  final int w, h;
  @override
  final int durationMs;
  @override
  final int videoWidth, videoHeight;

  @override
  Future<RawFrame> frameAt(int atMs) async {
    final run = await Process.run(
        ffmpeg,
        [
          '-v', 'error', '-ss', (atMs / 1000).toStringAsFixed(3), '-i', source,
          '-map', '0:v:0', '-frames:v', '1', '-vf', 'scale=$w:$h',
          '-f', 'rawvideo', '-pix_fmt', 'rgba', '-',
        ],
        stdoutEncoding: null);
    final bytes = Uint8List.fromList(run.stdout as List<int>);
    if (bytes.length != w * h * 4) {
      throw FrameFailure('decode_failed', 'ffmpeg gave ${bytes.length} bytes');
    }
    return RawFrame(width: w, height: h, rgba: bytes, timestampMs: atMs);
  }

  @override
  Future<void> close() async {}
}
