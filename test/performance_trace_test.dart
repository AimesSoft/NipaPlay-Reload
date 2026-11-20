import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/performance_trace.dart';

void main() {
  test('listing classification does not include URL parameters or identities',
      () {
    expect(
        PerformanceTrace.isItemListing('/Items?token=secret&SearchTerm=test'),
        isTrue);
    expect(PerformanceTrace.isItemListing('/Users/private-id/Items/Latest'),
        isTrue);
    expect(PerformanceTrace.isItemListing('/Users/private-id/Items/anime-id'),
        isFalse);
  });
  test('synchronous instrumentation preserves plugin results and failures', () {
    expect(PerformanceTrace.measureSync('metadata', () => 7), 7);
    final error = StateError('expected');
    expect(() => PerformanceTrace.measureSync('metadata', () => throw error),
        throwsA(same(error)));
  });
  test('frame budget follows refresh rate and counts either stage only once',
      () {
    final stats = PerformanceWindow();
    stats.addFrame(buildUs: 9000, rasterUs: 10000, refreshRate: 120);
    stats.addFrame(buildUs: 9000, rasterUs: 10000, refreshRate: 60);
    expect(stats.frames, 2);
    expect(stats.overBuildBudget, 1);
    expect(stats.overRasterBudget, 1);
    expect(stats.overEitherBudget, 1);
  });
  test('histogram has bounded buckets and preserves slow outliers', () {
    final stats = PerformanceWindow();
    for (var i = 0; i < 100000; i++) {
      stats.addFrame(buildUs: 1201, rasterUs: 2251, refreshRate: 60);
    }
    stats.addFrame(buildUs: 300000, rasterUs: 400000, refreshRate: 60);
    final json = stats.toJson();
    expect((json['ui'] as Map)['p95_upper_us'], 1500);
    expect((json['raster'] as Map)['p99_upper_us'], 2500);
    expect((json['raster'] as Map)['max_us'], 400000);
  });
  test('operation aggregation separates attempts, failures, bytes and items',
      () {
    final stats = PerformanceWindow(maxOperations: 2);
    stats.addOperation('http', elapsedUs: 30, bytes: 1000);
    stats.addOperation('http', elapsedUs: 50, bytes: 10, failed: true);
    stats.addOperation('decode', elapsedUs: 15, items: 20);
    stats.addOperation('extra');
    final json = stats.toJson();
    final http = (json['operations'] as Map)['http'] as Map;
    expect(http['count'], 2);
    expect(http['failed'], 1);
    expect(http['response_bytes'], 1010);
    expect(http['max_response_bytes'], 1000);
    expect(json['discarded_operations'], 1);
  });
  test('measurement preserves returned values and failures', () async {
    expect(await PerformanceTrace.measure('test.ok', () async => 42), 42);
    final error = StateError('expected');
    await expectLater(
        PerformanceTrace.measure('test.fail', () async => throw error),
        throwsA(same(error)));
  });
}
