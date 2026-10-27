import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/mesh/library_transfer.dart';

void main() {
  test('a work larger than the native frame transfers full multibyte credits',
      () async {
    final original = <JsonMap>[
      {
        'kind': 'work',
        'id': 'w',
        'value': {
          'credits': List.generate(
              12000,
              (i) => {
                    'name': '演职员 $i',
                    'role': '角色与制作职位',
                    'biography': '作品资料、来源和简介。' * 5,
                  }),
        }
      },
      {
        'kind': 'episode',
        'id': 'e1',
        'value': {'title': '第一话'}
      },
    ];
    final source = EncodedLibrarySnapshot('revision-1', original);
    expect(source.bytes.length, greaterThan(1024 * 1024));
    var pages = 0;
    JsonMap page(int offset) {
      final result = source.page(offset);
      expect(utf8.encode(jsonEncode(result)).length, lessThan(1024 * 1024));
      pages++;
      return result;
    }

    final actual = await readLibrarySnapshot(page(0), (input) async {
      expect(input['version'], 'revision-1');
      expect(input['encoding'], librarySnapshotEncoding);
      return page(input['offset'] as int);
    });
    expect(pages, greaterThan(1));
    expect(actual, original);
  });

  test(
      'older peers remain readable and a changed revision never publishes partial data',
      () async {
    final first = <String, Object?>{
      'version': 'v1',
      'records': <JsonMap>[
        {'kind': 'work', 'id': 'w'}
      ],
      'next': 1
    };
    expect(
        await readLibrarySnapshot(
            first,
            (_) async => {
                  'version': 'v1',
                  'records': <JsonMap>[
                    {'kind': 'episode', 'id': 'e'}
                  ],
                  'next': null,
                }),
        hasLength(2));
    await expectLater(
        readLibrarySnapshot(
            first,
            (_) async => {
                  'version': 'v2',
                  'records': <JsonMap>[],
                  'next': null,
                }),
        throwsA(isA<Failure>()
            .having((e) => e.code, 'code', FailureCode.conflict)));
  });
  test(
      'catalogue budgets, exact offsets, cancellation and deadlines are enforced',
      () async {
    final source = EncodedLibrarySnapshot('v1', [
      {'data': 'x' * 400000}
    ]);
    Future<void> rejected(JsonMap first,
        {int? budget, bool cancel = false}) async {
      await expectLater(
          readLibrarySnapshot(first, (_) async => source.page(192 * 1024),
              maxBytes: budget ?? 64 * 1024 * 1024, cancelled: () => cancel),
          throwsA(isA<Failure>()));
    }

    await rejected(source.page(0), budget: 100);
    await rejected({...source.page(0), 'next': 1});
    await rejected(source.page(0), cancel: true);
    await expectLater(
        readLibrarySnapshot(source.page(0), (_) => Completer<JsonMap>().future,
            timeout: const Duration(milliseconds: 10)),
        throwsA(isA<Failure>().having(
            (e) => e.details['reason'], 'reason', 'deadline_exceeded')));
    await expectLater(
        readLibrarySnapshot(
            {'version': 'v1', 'records': <JsonMap>[], 'next': 1},
            (input) async => {
                  'version': 'v1',
                  'records': <JsonMap>[],
                  'next': (input['offset'] as int) + 1
                },
            maxPages: 3),
        throwsA(isA<Failure>()));
  });
  test(
      'active publication leases survive pressure and expire with bounded bytes',
      () {
    var now = DateTime.utc(2026, 10, 28);
    final saved = LibraryPublications(maxEntries: 1, clock: () => now);
    final records = <JsonMap>[
      {'text': 'x' * 300000}
    ];
    final first = saved.publish('v1', records, 0, 'a');
    expect(() => saved.publish('v2', records, 0, 'b'), throwsA(isA<Failure>()));
    expect(saved.read('v1', first['next'] as int, 'a')!['next'], isNull);
    expect(saved.publish('v2', records, 0, 'b')['version'], 'v2');
    now = now.add(const Duration(minutes: 6));
    expect(saved.read('v2', 0, 'b'), isNull);
    expect(
        () => LibraryPublications(maxBytes: 100).publish('v', records, 0, 'a'),
        throwsA(isA<Failure>()));
  });
}
