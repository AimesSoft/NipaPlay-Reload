import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/media_server_pagination.dart';

void main() {
  Future<MediaServerPage<String>> decode(String body) async =>
      decodeMediaServerPage(body, (item) => item['Id'] as String);

  for (final total in [1000, 10000]) {
    test('$total entries use bounded pages without omissions', () async {
      final offsets = <int>[];
      final result = await loadMediaServerItems(
        endpoint:
            '/Items?ParentId=library&SortBy=SortName&SortOrder=Ascending&Limit=99999',
        isCurrent: () => true,
        decode: decode,
        request: (path) async {
          final query = Uri.parse(path).queryParameters;
          final start = int.parse(query['StartIndex']!);
          final limit = int.parse(query['Limit']!);
          offsets.add(start);
          expect(limit, lessThanOrEqualTo(200));
          expect(query['ParentId'], 'library');
          expect(query['SortBy'], 'SortName');
          return http.Response(
              jsonEncode({
                'TotalRecordCount': total,
                'Items': List.generate((total - start).clamp(0, limit),
                    (i) => {'Id': '${start + i}'}),
              }),
              200);
        },
      );
      expect(result, List.generate(total, (i) => '$i'));
      expect(offsets.length, total ~/ 200);
    });
  }

  test('server cap and missing total do not truncate a library', () async {
    var calls = 0;
    final result = await loadMediaServerItems(
      endpoint: '/Items?Limit=20',
      isCurrent: () => true,
      decode: decode,
      request: (path) async {
        calls++;
        final start = int.parse(Uri.parse(path).queryParameters['StartIndex']!);
        return http.Response(
            jsonEncode({
              'Items': List.generate(
                  (7 - start).clamp(0, 3), (i) => {'Id': '${start + i}'}),
            }),
            200);
      },
    );
    expect(result, List.generate(7, (i) => '$i'));
    expect(calls, 4);
  });

  test('overlapping pages deduplicate IDs and advance by raw page size',
      () async {
    final offsets = <int>[];
    final result = await loadMediaServerItems(
      endpoint: '/Items?Limit=10',
      pageSize: 3,
      isCurrent: () => true,
      decode: decode,
      request: (path) async {
        final start = int.parse(Uri.parse(path).queryParameters['StartIndex']!);
        offsets.add(start);
        final ids = start == 0 ? ['a', 'b', 'c'] : ['c', 'd'];
        return http.Response(
            jsonEncode({
              'TotalRecordCount': 5,
              'Items': ids.map((id) => {'Id': id}).toList(),
            }),
            200);
      },
    );
    expect(result, ['a', 'b', 'c', 'd']);
    expect(offsets, [0, 3]);
  });

  test('superseded response is discarded before decode or next request',
      () async {
    var current = true;
    var decoded = false;
    await expectLater(
        loadMediaServerItems<String>(
          endpoint: '/Items?Limit=99999',
          isCurrent: () => current,
          decode: (body) async {
            decoded = true;
            return decode(body);
          },
          request: (_) async {
            current = false;
            return http.Response('{"Items":[{"Id":"old"}]}', 200);
          },
        ),
        throwsStateError);
    expect(decoded, false);
  });

  test('later HTTP failure and repeated pages never return a partial success',
      () async {
    for (final repeat in [false, true]) {
      var calls = 0;
      await expectLater(
          loadMediaServerItems(
            endpoint: '/Items?Limit=1000',
            isCurrent: () => true,
            decode: decode,
            request: (_) async {
              calls++;
              return calls == 1 || repeat
                  ? http.Response('{"Items":[{"Id":"a"}]}', 200)
                  : http.Response('failed', 503);
            },
          ),
          throwsStateError);
      expect(calls, 2);
    }
  });

  test('random query remains a single request and preserves its limit',
      () async {
    var calls = 0;
    final result = await loadMediaServerItems(
      endpoint: '/Items?SortBy=Random&Limit=3',
      isCurrent: () => true,
      decode: decode,
      request: (path) async {
        calls++;
        expect(Uri.parse(path).queryParameters['Limit'], '3');
        return http.Response(
            '{"TotalRecordCount":10000,"Items":[{"Id":"r"}]}', 200);
      },
    );
    expect(result, ['r']);
    expect(calls, 1);
  });
}
