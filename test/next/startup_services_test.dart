import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/system/startup_services.dart';

void main() {
  test('slow and failed media services do not hold other services or retry',
      () async {
    final services = StartupServices();
    final slow = Completer<void>();
    var broken = true, historyStarted = false;
    services.register('library', '目录', () => slow.future);
    services.register('indexers', '索引', () async {
      if (broken) throw StateError('permission denied');
    });
    services.register('history', '历史', () async {
      historyStarted = true;
    });
    services.start();
    await Future<void>.delayed(Duration.zero);
    expect(historyStarted, isTrue);
    expect(services.status['state'], 'degraded');
    final components = services.status['components'] as List;
    expect(components[0]['state'], 'starting');
    expect(components[1]['error']['message'], contains('permission denied'));
    broken = false;
    services.retry('indexers');
    await services.run('indexers');
    expect((services.status['components'] as List)[1]['attempts'], 2);
    slow.complete();
    await services.run('library');
    expect(services.status['state'], 'ready');
    await services.pause();
    expect(services.status['state'], 'stopped');
    expect(() => services.retry('indexers'), throwsA(anything));
  });

  test('stop drains a pending initializer and coalesces concurrent retries',
      () async {
    final services = StartupServices();
    final slow = Completer<void>();
    var calls = 0, completedStop = false;
    services.register('library', '目录', () {
      calls++;
      return slow.future;
    });
    services.start();
    services.retry('library');
    final stopping = services.pause().then((_) => completedStop = true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(completedStop, false);
    slow.complete();
    await stopping;
    expect((services.status['components'] as List).single['state'], 'stopped');
  });
}
