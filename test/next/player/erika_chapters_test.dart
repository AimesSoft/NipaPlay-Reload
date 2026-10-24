import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/player/features/kernel_features.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/kernel/erika_driver.dart';
import 'package:nipaplay/next/player/kernel/native.dart';

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

  test('an early empty answer is replaced after the tracks report arrives',
      () async {
    var tracksReported = false;
    final calls = <String>[];
    final mediaReports = <MediaFacts>[];
    Future<NativeInvokeReply> invoke(String method, JsonMap arguments) async {
      calls.add('${method}:${tracksReported ? 'reported' : 'early'}');
      return (
        result: {
          'chapters': tracksReported
              ? [
                  for (final (index, title) in [
                    'Avant',
                    'Opening',
                    'A Part',
                    'Eye-catch',
                    'B Part',
                    'Ending',
                    'Post-Credit',
                  ].indexed)
                    {
                      'index': index,
                      'title': title,
                      'startMs': index * 60000,
                      'endMs': index == 6 ? null : (index + 1) * 60000,
                    },
                ]
              : <Object>[],
          'mediaOpen': true,
        },
        error: null,
        supported: true,
      );
    }

    final reader = ErikaChapterReader(invoke, onResolved: (chapters) {
      mediaReports.add(MediaFacts(
        duration: const Duration(minutes: 24),
        chapters: chapters,
      ));
    });

    // DurationChanged arrives before the complete media report.
    reader.durationReported();
    await pumpEventQueue();
    expect(calls, ['chapters:early']);
    expect(reader.chapters, isNull, reason: 'an early empty is not a fact');
    expect(mediaReports, isEmpty);

    // TracksChanged brackets the complete opened-media report.
    tracksReported = true;
    reader.tracksReported();
    await reader.known;
    reader.close();

    expect(calls, ['chapters:early', 'chapters:reported']);
    expect(mediaReports, hasLength(1));
    expect(mediaReports.single.chapters, hasLength(7));
    expect(mediaReports.single.chapters!.map((chapter) => chapter.title), [
      'Avant',
      'Opening',
      'A Part',
      'Eye-catch',
      'B Part',
      'Ending',
      'Post-Credit',
    ]);
  });
}
