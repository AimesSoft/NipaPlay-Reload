// 由 flutter_test 提供。
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/system/foreground.dart';
import 'package:nipaplay/next/system/network_watch.dart';
import 'package:nipaplay/next/ui/dev/idle_measurement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('网络兼容检查实际产生周期计数，后台停止计数', () {
    fakeAsync((clock) {
      NextForeground.setActive(true);
      final before = NextRefreshMetrics.snapshot();
      final watch = ForegroundNetworkWatch(() {}, events: null)..start();
      clock.elapse(const Duration(seconds: 15));
      final after = NextRefreshMetrics.snapshot();
      expect(after['mesh.network.periodic']! - (before['mesh.network.periodic'] ?? 0), 3);
      NextForeground.setActive(false);
      clock.elapse(const Duration(seconds: 60));
      expect(NextRefreshMetrics.snapshot()['mesh.network.periodic'], after['mesh.network.periodic']);
      watch.close();
      clock.flushMicrotasks();
      NextForeground.setActive(true);
    });
  });

  test('idle 汇总所有周期来源，午夜截止点单独计入数据刷新', () async {
    final pending = measureNextIdle(const Duration(milliseconds: 50));
    NextRefreshMetrics.record('mesh.legacy.periodic');
    NextRefreshMetrics.record('mesh.network.periodic');
    NextRefreshMetrics.record('downloads.observation.periodic');
    NextRefreshMetrics.record('calendar.midnight');
    NextRefreshMetrics.record('ui.data');
    final measured = await pending.timeout(const Duration(seconds: 5));
    expect(measured['periodicRefreshes'], 3);
    expect(measured['dataRefreshes'], 2);
    expect(measured['refreshes'], {
      'mesh.legacy.periodic': 1, 'mesh.network.periodic': 1,
      'downloads.observation.periodic': 1, 'calendar.midnight': 1, 'ui.data': 1,
    });
  });
}
