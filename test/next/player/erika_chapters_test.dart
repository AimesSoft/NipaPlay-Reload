import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/player/kernel/erika_driver.dart';

void main() {
  test('Erika chapters come from its JSON method in container order', () async {
    final calls = <(String, JsonMap)>[];
    final chapters = await readErikaChapters((method, arguments) async {
      calls.add((method, arguments));
      return (
        result: {
          'chapters': [
            {'index': 0, 'title': 'Opening', 'startMs': 0, 'endMs': 90000},
            {'index': 1, 'title': 'Part A', 'startMs': 90000, 'endMs': null},
          ],
          'mediaOpen': true,
        },
        error: null,
        supported: true,
      );
    });

    expect(calls, hasLength(1));
    expect(calls.single.$1, 'chapters');
    expect(calls.single.$2, isEmpty);
    expect(chapters, isNotNull);
    expect(chapters!.map((chapter) => chapter.toJson()).toList(), [
      {'title': 'Opening', 'startMs': 0, 'endMs': 90000},
      {'title': 'Part A', 'startMs': 90000},
    ]);
  });

  test('an older Erika without chapters reports unavailable, not empty',
      () async {
    final chapters = await readErikaChapters((method, arguments) async => (
          result: null,
          error: 'unsupported Erika presenter method: chapters',
          supported: false,
        ));

    expect(chapters, isNull);
  });
}
