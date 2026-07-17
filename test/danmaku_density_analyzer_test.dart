import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/danmaku_density_analyzer.dart';
import 'package:nipaplay/widgets/danmaku_density_chart.dart';

void main() {
  group('DanmakuDensityAnalyzer', () {
    test('buckets supported time fields and ignores invalid values', () {
      final points = DanmakuDensityAnalyzer.analyzeDensity(
        danmakuList: const [
          {'time': 0.0},
          {'t': '1.0'},
          {'timestamp': 3.0},
          {'stime': 9.9},
          {'time': -1.0},
          {'time': 'invalid'},
        ],
        videoDurationSeconds: 10,
        segmentCount: 5,
      );

      expect(points.map((point) => point.count), [2, 1, 0, 0, 1]);
    });

    test('smooths points and reports peaks', () {
      const points = [
        DanmakuDensityPoint(timePosition: 0.1, count: 1),
        DanmakuDensityPoint(timePosition: 0.3, count: 5),
        DanmakuDensityPoint(timePosition: 0.5, count: 1),
        DanmakuDensityPoint(timePosition: 0.7, count: 4),
        DanmakuDensityPoint(timePosition: 0.9, count: 1),
      ];

      final stats = DanmakuDensityAnalyzer.getDensityStats(points);
      final smoothed = DanmakuDensityAnalyzer.smoothDensityData(
        densityPoints: points,
      );

      expect(stats.totalCount, 12);
      expect(stats.peakPositions, [0.3, 0.7]);
      expect(smoothed.map((point) => point.count), [3, 2, 3, 2, 3]);
    });
  });
}
