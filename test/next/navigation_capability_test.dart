import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/next/capabilities/navigation_capability.dart';

import 'test_support.dart';

void main() {
  late List<String> changedPages;
  late Harness harness;

  setUp(() {
    changedPages = [];
    harness = Harness([NavigationCapability(changePage: changedPages.add)]);
  });

  for (final page in AppPageIds.primaryOrder) {
    test('navigates to $page and returns the page ID', () async {
      expect(await invokeCompleted(harness, 'ui.navigate', {'page': page}),
          {'page': page});
      expect(changedPages, [page]);
    });
  }

  for (final input in <JsonMap>[
    {'page': 'unknown'},
    {'page': AppPageIds.settings},
    {},
    {'page': 1}
  ]) {
    test('rejects invalid navigation input $input before dispatch', () async {
      await invokeFailed(
          harness, 'ui.navigate', input, FailureCode.invalidInput);
      expect(changedPages, isEmpty);
    });
  }

  test('lets unexpected callback exceptions reach the harness boundary',
      () async {
    final throwingHarness = Harness([
      NavigationCapability(
        changePage: (_) => throw StateError('Navigation failed.'),
      )
    ]);
    final failure = await invokeFailed(
        throwingHarness, 'ui.navigate', {'page': 'home'}, FailureCode.internal);
    expect(failure.message, contains('Navigation failed.'));
  });
}
