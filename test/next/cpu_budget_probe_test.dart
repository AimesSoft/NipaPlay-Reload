import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'support/cpu_budget_probe.dart';

void main() {
  test(
      'counts callback CPU once, across asynchronous turns, and catches a block',
      () async {
    final probe = CpuBudgetProbe();
    await probe.run(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      probe.mark('idle');
      await Future<void>.value().then((_) {
        probe.injectBlock(const Duration(milliseconds: 25));
      });
      await Future<void>.delayed(Duration.zero);
      probe.mark('regression');
    });
    probe.stop();
    expect(probe.phases.first.$2, lessThan(20));
    expect(probe.phases.last.$2, greaterThanOrEqualTo(25));
    expect(probe.phases.last.$2, lessThan(80));
  });
}
