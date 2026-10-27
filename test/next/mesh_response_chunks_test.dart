import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/mesh/response_chunks.dart';

void main() {
  test('large completed result is read without executing its Action again', () async {
    final cache = MeshResponseChunks();
    final result = <String, Object?>{'jsonrpc': '2.0', 'id': 'call-1',
      'result': {'metadata': '中文角色、声优与演员' * 100000}};
    final descriptor = cache.describe('peer-a', utf8.encode(jsonEncode(result)));
    var reads = 0;
    expect(await readMeshResponse(descriptor, (input) async {
      reads++;
      final page = cache.read('peer-a', input);
      expect(utf8.encode(jsonEncode(page)).length, lessThan(1024 * 1024));
      return page;
    }), result);
    expect(reads, greaterThan(1));
    expect(() => cache.read('peer-b', {'token': descriptor['token'], 'offset': 0}),
        throwsA(isA<Failure>()));
    await expectLater(readMeshResponse({...descriptor, 'sha256': 'wrong'},
        (input) async => cache.read('peer-a', input)), throwsFormatException);
  });

  test('expired continuations are rejected', () {
    var now = DateTime.utc(2026, 10, 27);
    final cache = MeshResponseChunks(clock: () => now);
    final descriptor = cache.describe('peer', utf8.encode('{}'));
    now = now.add(const Duration(minutes: 6));
    expect(() => cache.read('peer', {'token': descriptor['token'], 'offset': 0}),
        throwsA(isA<Failure>().having((e) => e.code, 'code', FailureCode.notFound)));
  });
}
