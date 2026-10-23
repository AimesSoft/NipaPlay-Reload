import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/family_descriptions.dart';
import 'package:nipaplay/next/capabilities/media_frames.dart';
import 'package:nipaplay/next/capabilities/media_frames_erika.dart';

void main() {
  late Directory root;
  late Directory media;
  late String file;
  late _FakeEngine engine;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('media-frames-test');
    media = await Directory.systemTemp.createTemp('media-frames-media');
    file = '${media.path}/ep.mkv';
    await File(file).writeAsBytes([0]);
    engine = _FakeEngine();
  });
  tearDown(() async {
    await root.delete(recursive: true);
    await media.delete(recursive: true);
  });

  Harness harness({
    Duration frameTimeout = const Duration(seconds: 5),
    Future<String?> Function(int, int)? episode,
  }) =>
      Harness([
        MediaFramesCapability(
            engine: engine,
            outputRoot: () async => Directory('${root.path}/media-frames'),
            episodePath: episode,
            frameTimeout: frameTimeout)
      ]);

  Future<Outcome> call(Harness h, JsonMap input) =>
      h.invokeJson('media.frames', input, Invocation(origin: 'test'));

  JsonMap result(Outcome outcome) {
    expect(outcome, isA<Completed>());
    return (outcome as Completed).value.toJson();
  }

  test('takes frames at the asked times and reports where they really are',
      () async {
    final out = result(await call(harness(), {
      'path': file,
      'atMs': [60000, 10000, 120000],
      'maxEdge': 64,
    }));
    final frames = (out['frames'] as List).cast<Map>();
    // The result keeps the order asked for even though the engine goes in
    // ascending order.
    expect(frames.map((f) => f['requestedMs']), [60000, 10000, 120000]);
    expect(engine.source.requested, [10000, 60000, 120000]);
    expect(frames.map((f) => f['timestampMs']), [60040, 10040, 120040]);
    expect(out['taken'], 3);
    expect(out['durationMs'], 900000);
    expect(out['engine'], 'fake');
    expect(engine.openedWith, (width: null, maxEdge: 64));
    for (final frame in frames) {
      expect(frame['mimeType'], 'image/jpeg');
      expect(frame['width'], 64);
      expect(frame['height'], 36);
      final bytes = await File(frame['path'] as String).readAsBytes();
      expect(bytes.sublist(0, 2), [0xFF, 0xD8]);
      expect(bytes.length, frame['bytes']);
    }
  });

  test('pixels handed over as a view into a larger buffer encode as they are',
      () {
    // A 2x1 picture, red then blue, three bytes into a larger message.
    final message = Uint8List(3 + 8 + 5)
      ..setAll(3, [255, 0, 0, 255, 0, 0, 255, 255]);
    final frame = RawFrame(
        width: 2,
        height: 1,
        rgba: Uint8List.view(message.buffer, 3, 8),
        timestampMs: 0);
    final decoded = img.decodePng(encodeFrame(frame, 'png'))!;
    expect(decoded.getPixel(0, 0).r, 255);
    expect(decoded.getPixel(0, 0).b, 0);
    expect(decoded.getPixel(1, 0).b, 255);
    expect(decoded.getPixel(1, 0).r, 0);
  });

  group('Erika first, MDK behind it', () {
    Harness preferred(FrameEngine first) => Harness([
          MediaFramesCapability(
              engine: PreferredFrameEngine([first, engine]),
              outputRoot: () async => Directory('${root.path}/media-frames'))
        ]);

    test('the Erika engine writes the PNG Erika encoded and names itself',
        () async {
      final fake = _FakeErikaSession();
      final out = result(await call(
          preferred(ErikaFrameEngine(opener: (_) async => fake)), {
        'path': file,
        'atMs': [60000, 10000, 30000],
        'maxEdge': 640,
        'format': 'png',
      }));
      expect(out['engine'], 'erika');
      expect(out.containsKey('engineFallback'), isFalse);
      expect(engine.opens, 0, reason: 'MDK was not needed');
      expect((out['durationMs'], out['videoWidth'], out['videoHeight']),
          (888032, 4096, 1744));
      expect(fake.asked.first, (Duration.zero, 16, 16, ErikaFrameFormat.rgba));
      expect(fake.asked.skip(1).map((a) => (a.$2, a.$3, a.$4)),
          everyElement((640, 640, ErikaFrameFormat.png)));
      expect(fake.asked.skip(1).map((a) => a.$1.inMilliseconds),
          [10000, 30000, 60000],
          reason: 'one open media, asked in ascending order');
      expect(fake.opened, 1);
      expect(fake.closed, 1, reason: 'the media is released afterwards');
      final frames = (out['frames'] as List).cast<Map>();
      expect(frames.first, allOf(containsPair('width', 640),
          containsPair('height', 273), containsPair('mimeType', 'image/png'),
          containsPair('timestampMs', 60000)));
      expect(await File(frames.first['path'] as String).readAsBytes(),
          _FakeErikaSession.png);
      expect(frames.last['error'], containsPair('code', 'beyond_duration'));
    });

    test('MDK takes the frames when Erika cannot, and the result says why',
        () async {
      final erika = ErikaFrameEngine(
          opener: (_) async => throw UnsupportedError(
              'no erika_export_frame in this library'));
      final out = result(await call(preferred(erika), {
        'path': file,
        'atMs': [1000],
      }));
      expect(out['engine'], 'fake');
      expect(out['engineFallback'], [
        {'engine': 'erika', 'error': 'no erika_export_frame in this library'}
      ]);
      expect(out['taken'], 1);
    });

    test('a media Erika cannot read is released and falls back', () async {
      final fake = _FakeErikaSession(failFirst: true);
      final out = result(await call(
          preferred(ErikaFrameEngine(opener: (_) async => fake)), {
        'path': file,
        'atMs': [1000],
      }));
      expect(out['engine'], 'fake');
      expect(fake.closed, 1);
    });
  });

  test('png, width and the default size', () async {
    final out = result(await call(harness(), {
      'path': file,
      'atMs': [1000],
      'format': 'png',
      'width': 32,
    }));
    final frame = (out['frames'] as List).single as Map;
    expect(frame['mimeType'], 'image/png');
    expect((frame['path'] as String).endsWith('.png'), true);
    expect(engine.openedWith, (width: 32, maxEdge: null));
    result(await call(harness(), {
      'path': file,
      'atMs': [1000]
    }));
    expect(engine.openedWith, (width: null, maxEdge: 640));
  });

  test('range expands inclusively; the limit refuses before opening anything',
      () async {
    final out = result(await call(harness(), {
      'path': file,
      'range': {'startMs': 1000, 'endMs': 3000, 'everyMs': 1000},
    }));
    expect((out['frames'] as List).map((f) => (f as Map)['requestedMs']),
        [1000, 2000, 3000]);

    final h = harness();
    final opens = engine.opens;
    for (final input in [
      {
        'path': file,
        'range': {'startMs': 0, 'endMs': 60000, 'everyMs': 1000}
      }, // 61 frames
      {
        'path': file,
        'atMs': List.generate(61, (i) => i * 1000)
      },
      {
        'path': file,
        'range': {'startMs': 0, 'endMs': 100, 'everyMs': 50}
      },
      {
        'path': file,
        'range': {'startMs': 5, 'endMs': 1, 'everyMs': 100}
      },
      {'path': file, 'atMs': <int>[]},
      {
        'path': file,
        'atMs': [-1]
      },
      {'path': file}, // no times
      {
        'path': file,
        'atMs': [1],
        'range': {'startMs': 0, 'endMs': 1, 'everyMs': 100}
      },
      {
        'path': file,
        'atMs': [1],
        'width': 100,
        'maxEdge': 100
      },
      {
        'atMs': [1]
      }, // no media
      {
        'path': file,
        'animeId': 1,
        'episodeId': 2,
        'atMs': [1]
      },
    ]) {
      expect(await call(h, input), isA<Failed>(), reason: '$input');
    }
    expect(engine.opens, opens);
    final sixty = result(await call(h, {
      'path': file,
      'atMs': List.generate(60, (i) => i * 1000)
    }));
    expect(sixty['taken'], 60);
  });

  test('a limit refusal says how many and that nothing was taken', () async {
    final outcome = await call(harness(), {
      'path': file,
      'range': {'startMs': 0, 'endMs': 120000, 'everyMs': 1000},
    });
    expect(outcome, isA<Failed>());
    final text = outcome.toEnvelope().toString();
    expect(text, contains('121'));
    expect(text, contains('Nothing was taken'));
  });

  test('a file that is not there, a relative path and a bad scheme fail',
      () async {
    final h = harness();
    for (final path in ['${media.path}/missing.mkv', 'ep.mkv', 'smb://x/y.mkv']) {
      expect(
          await call(h, {
            'path': path,
            'atMs': [1]
          }),
          isA<Failed>(),
          reason: path);
    }
    expect(engine.opens, 0);
    // file:// and http(s) are accepted.
    result(await call(h, {
      'path': Uri.file(file).toString(),
      'atMs': [1]
    }));
    expect(engine.source.source, file);
    result(await call(h, {
      'path': 'http://127.0.0.1:1234/x.mkv',
      'atMs': [1]
    }));
  });

  test('an episode is found through its recorded file', () async {
    final h = harness(episode: (anime, episode) async =>
        anime == 7 && episode == 8 ? file : null);
    result(await call(h, {'animeId': 7, 'episodeId': 8, 'atMs': [5]}));
    expect(engine.source.source, file);
    expect(
        await call(h, {'animeId': 7, 'episodeId': 9, 'atMs': [5]}), isA<Failed>());
  });

  test('frames that cannot be taken say why and do not spoil the others',
      () async {
    engine.durationMs = 20000;
    engine.failAt = {5000: const FrameFailure('decode_failed', 'broken block')};
    final out = result(await call(harness(), {
      'path': file,
      'atMs': [1000, 5000, 25000],
    }));
    final frames = (out['frames'] as List).cast<Map>();
    expect(frames[0]['path'], isNotNull);
    expect(frames[1]['error'], {'code': 'decode_failed', 'message': 'broken block'});
    expect(frames[2]['error']['code'], 'beyond_duration');
    expect(frames[2].containsKey('path'), false);
    expect(out['taken'], 1);
    expect(out['requested'], 3);
    expect(engine.source.requested, [1000, 5000]);
  });

  test('a wrong-sized picture is a failure for that frame only', () async {
    engine.wrongSizeAt = {2000};
    final out = result(await call(harness(), {
      'path': file,
      'atMs': [1000, 2000],
    }));
    final frames = (out['frames'] as List).cast<Map>();
    expect(frames[0]['path'], isNotNull);
    expect(frames[1]['error']['code'], 'decode_failed');
  });

  test('a stuck frame times out, later frames are skipped, the decoder is closed',
      () async {
    engine.stuckAt = 2000;
    final out = result(await call(
        harness(frameTimeout: const Duration(milliseconds: 100)), {
      'path': file,
      'atMs': [1000, 2000, 3000],
    }));
    final frames = (out['frames'] as List).cast<Map>();
    expect(frames[0]['path'], isNotNull);
    expect(frames[1]['error']['code'], 'timeout');
    expect(frames[2]['error']['code'], 'skipped_after_timeout');
    expect(engine.source.closed, true);
  });

  test('the whole call is bounded by timeoutMs', () async {
    engine.delay = const Duration(milliseconds: 700);
    final out = result(await call(harness(), {
      'path': file,
      'atMs': [1000, 2000, 3000, 4000],
      'timeoutMs': 1000,
    }));
    final codes = [
      for (final f in (out['frames'] as List).cast<Map>())
        (f['error'] as Map?)?['code']
    ];
    expect(codes.first, isNull);
    expect(codes.skip(1).every((c) => c == 'timeout' || c == 'skipped_after_timeout'),
        true,
        reason: '$codes');
    expect(engine.source.closed, true);
  });

  test('the decoder is closed when the call ends, and open failures surface',
      () async {
    result(await call(harness(), {
      'path': file,
      'atMs': [1]
    }));
    expect(engine.source.closed, true);
    expect(engine.opens, 1);

    engine.openError = const Failure(
        FailureCode.unavailable, 'This media has no video stream.');
    final failed = await call(harness(), {
      'path': file,
      'atMs': [1]
    });
    expect(failed, isA<Failed>());
    expect(failed.toEnvelope().toString(), contains('no video stream'));
  });

  test('every call decodes with a decoder of its own and releases it', () async {
    final h = harness();
    result(await call(h, {'path': file, 'atMs': [1000]}));
    final first = engine.source;
    result(await call(h, {'path': file, 'atMs': [1000]}));
    expect(identical(first, engine.source), false);
    expect(first.closed, true);
    expect(engine.source.closed, true);
    expect(engine.openSources, 0);
  });

  test('two calls at once decode one after the other', () async {
    engine.delay = const Duration(milliseconds: 50);
    final h = harness();
    await Future.wait([
      call(h, {'path': file, 'atMs': [1000, 2000]}),
      call(h, {'path': file, 'atMs': [3000, 4000]}),
    ]);
    expect(engine.maxConcurrentSources, 1);
  });

  test('it is a read with the limits and units written in its description',
      () {
    final spec = MediaFramesCapability.spec;
    expect(spec.effect, Effect.read);
    expect(spec.description, contains('at most 60'));
    expect(spec.description, contains('milliseconds'));
    expect(familyFacts['media'], contains('media.frames'));
    expect(familyFacts['media'], contains('最多 60 张'));
    expect(familyFacts['media'], contains('毫秒'));
    expect(describeFamily('media', [spec])['description'],
        familyFacts['media']);
  });

  test('files older than a day are pruned, newer ones stay', () async {
    final frames = Directory('${root.path}/media-frames');
    final old = await Directory('${frames.path}/old').create(recursive: true);
    final recent = await Directory('${frames.path}/recent').create();
    await File('${old.path}/a.jpg').writeAsBytes([1]);
    final clock = DateTime.now().add(const Duration(days: 2));
    final h = Harness([
      MediaFramesCapability(
          engine: engine,
          outputRoot: () async => frames,
          now: () => clock)
    ]);
    // With the clock two days ahead both are old; with the real clock only
    // directories untouched for a day would go.
    result(await call(h, {'path': file, 'atMs': [1]}));
    expect(await old.exists(), false);
    expect(await recent.exists(), false);
    final again = Harness([
      MediaFramesCapability(engine: engine, outputRoot: () async => frames)
    ]);
    final kept = await Directory('${frames.path}/kept').create();
    result(await call(again, {'path': file, 'atMs': [1]}));
    expect(await kept.exists(), true);
  });
}

class _FakeEngine implements FrameEngine {
  int opens = 0;
  int openSources = 0;
  int maxConcurrentSources = 0;
  Object? openError;
  ({int? width, int? maxEdge})? openedWith;
  int durationMs = 900000;
  Duration delay = Duration.zero;
  Map<int, FrameFailure> failAt = {};
  Set<int> wrongSizeAt = {};
  int? stuckAt;
  late _FakeSource source;

  @override
  String get name => 'fake';

  @override
  Future<FrameSource> open(String path,
      {int? width,
      int? maxEdge,
      String format = 'jpeg',
      required Duration timeout}) async {
    if (openError != null) throw openError!;
    opens++;
    openedWith = (width: width, maxEdge: maxEdge);
    final w = width ?? maxEdge!;
    source = _FakeSource(this, path, w, (w * 9 / 16).round());
    openSources++;
    if (openSources > maxConcurrentSources) maxConcurrentSources = openSources;
    return source;
  }
}

class _FakeSource implements FrameSource {
  _FakeSource(this.fake, this.source, this.w, this.h);
  final _FakeEngine fake;
  final String source;
  final int w, h;
  final requested = <int>[];
  var closed = false;

  @override
  String get engine => fake.name;
  @override
  int? get durationMs => fake.durationMs;
  @override
  int? get videoWidth => 3840;
  @override
  int? get videoHeight => 2160;

  @override
  Future<RawFrame> frameAt(int atMs) async {
    requested.add(atMs);
    if (fake.delay > Duration.zero) await Future.delayed(fake.delay);
    if (fake.stuckAt == atMs) await Completer<void>().future;
    final failure = fake.failAt[atMs];
    if (failure != null) throw failure;
    final size = fake.wrongSizeAt.contains(atMs) ? w * h * 4 - 4 : w * h * 4;
    final pixels = Uint8List(size);
    for (var i = 0; i < size; i += 4) {
      pixels[i] = atMs % 256;
      pixels[i + 3] = 255;
    }
    return RawFrame(width: w, height: h, rgba: pixels, timestampMs: atMs + 40);
  }

  @override
  Future<void> close() async {
    closed = true;
    fake.openSources--;
  }
}


final class _FakeErikaSession implements ErikaFrameSession {
  _FakeErikaSession({this.failFirst = false});

  static final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

  final bool failFirst;
  final asked = <(Duration, int, int, ErikaFrameFormat)>[];
  int opened = 1;
  int closed = 0;

  @override
  Future<ErikaExportedFrame> frameAt(
    Duration position, {
    int width = 0,
    int height = 0,
    ErikaFrameFormat format = ErikaFrameFormat.png,
  }) async {
    asked.add((position, width, height, format));
    if (failFirst) {
      throw StateError('Frame export failed: cannot read the media');
    }
    if (position == const Duration(seconds: 30)) {
      throw StateError('Frame export failed: position 30s is not '
          'before the end of the media (20s)');
    }
    final pictureOnly = format == ErikaFrameFormat.png;
    return ErikaExportedFrame(
      width: position == Duration.zero ? 16 : 640,
      height: position == Duration.zero ? 7 : 273,
      format: format,
      bytes: pictureOnly ? png : Uint8List(16 * 7 * 4),
      timestamp: position,
      sourceWidth: 4096,
      sourceHeight: 1744,
      duration: const Duration(milliseconds: 888032),
    );
  }

  @override
  Future<void> close() async => closed += 1;
}
