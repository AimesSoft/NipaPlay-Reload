import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/mesh/library_transfer.dart';

void main() {
  test('a work larger than the native frame transfers full multibyte credits', () async {
    final original = <JsonMap>[
      {'kind': 'work', 'id': 'w', 'value': {
        'credits': List.generate(12000, (i) => {
          'name': '演职员 $i', 'role': '角色与制作职位',
          'biography': '作品资料、来源和简介。' * 5,
        }),
      }},
      {'kind': 'episode', 'id': 'e1', 'value': {'title': '第一话'}},
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

  test('older peers remain readable and a changed revision never publishes partial data', () async {
    final first = <String, Object?>{'version': 'v1', 'records': <JsonMap>[
      {'kind': 'work', 'id': 'w'}
    ], 'next': 1};
    expect(await readLibrarySnapshot(first, (_) async => {
      'version': 'v1', 'records': <JsonMap>[{'kind': 'episode', 'id': 'e'}], 'next': null,
    }), hasLength(2));
    await expectLater(readLibrarySnapshot(first, (_) async => {
      'version': 'v2', 'records': <JsonMap>[], 'next': null,
    }), throwsA(isA<Failure>().having((e) => e.code, 'code', FailureCode.conflict)));
  });
}
