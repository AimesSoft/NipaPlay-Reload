import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/frame_rate_sampler.dart';

void main() {
  List<int> frames(int hz, int seconds) => List.generate(
        hz * seconds + 1,
        (i) => 10000000 + (i * 1000000 / hz).round(),
      );

  test('180 Hz reports stay 180 FPS across arbitrary delivery batches', () {
    final timestamps = frames(180, 4);
    for (final batchSize in [1, 70, 180, 360, 721]) {
      final sampler = FrameRateSampler();
      for (var start = 0; start < timestamps.length; start += batchSize) {
        for (final timestamp in timestamps.skip(start).take(batchSize)) {
          sampler.addTimestamp(timestamp);
        }
        if (sampler.fps > 0) expect(sampler.fps, closeTo(180, 0.01));
      }
      expect(sampler.fps, closeTo(180, 0.01));
      expect(sampler.maxFrameGapMs, closeTo(5.556, 0.001));
    }
  });

  test('a real 150 Hz cadence is reported without display-rate clamping', () {
    final sampler = FrameRateSampler();
    frames(150, 2).forEach(sampler.addTimestamp);
    expect(sampler.fps, closeTo(150, 0.01));
  });

  test('a 50 ms stall lowers FPS and remains visible in the maximum gap', () {
    final sampler = FrameRateSampler();
    for (var i = 0; i <= 180; i++) {
      if (i > 90 && i < 99) continue;
      sampler.addTimestamp((i * 1000000 / 180).round());
    }
    expect(sampler.fps, 172);
    expect(sampler.maxFrameGapMs, 50);
  });

  test('duplicate and out-of-order reports do not inflate FPS', () {
    final sampler = FrameRateSampler();
    for (final timestamp in frames(180, 1)) {
      sampler.addTimestamp(timestamp);
      sampler.addTimestamp(timestamp);
      sampler.addTimestamp(timestamp - 1);
    }
    expect(sampler.fps, 180);
  });

  test('reset starts a fresh window without including idle time', () {
    final sampler = FrameRateSampler();
    frames(180, 1).forEach(sampler.addTimestamp);
    sampler.reset();
    expect(sampler.fps, 0);
    expect(sampler.maxFrameGapMs, 0);
    frames(60, 1).map((t) => t + 90000000).forEach(sampler.addTimestamp);
    expect(sampler.fps, 60);
  });
}
