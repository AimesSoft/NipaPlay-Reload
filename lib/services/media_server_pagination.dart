import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

class MediaServerRequestSuperseded extends StateError {
  MediaServerRequestSuperseded() : super('Media server request superseded');
}

class MediaServerPage<T> {
  const MediaServerPage(this.items, this.ids, this.total);
  final List<T> items;
  final List<String?> ids;
  final int? total;
}

/// Called by the server-specific isolate entry point, so JSON and models need
/// not coexist with the full library on the UI isolate.
MediaServerPage<T> decodeMediaServerPage<T>(
    String body, T Function(Map<String, dynamic>) fromJson) {
  final data = jsonDecode(body) as Map<String, dynamic>;
  final raw = (data['Items'] as List).cast<Map<String, dynamic>>();
  return MediaServerPage(
    raw.map(fromJson).toList(growable: false),
    raw.map((item) => item['Id']?.toString()).toList(growable: false),
    (data['TotalRecordCount'] as num?)?.toInt(),
  );
}

/// Retains the complete-list contract while bounding each HTTP/JSON response.
/// Random queries deliberately remain one request: paging reshuffles their set.
Future<List<T>> loadMediaServerItems<T>({
  required String endpoint,
  required Future<http.Response> Function(String) request,
  required Future<MediaServerPage<T>> Function(String) decode,
  required bool Function() isCurrent,
  int pageSize = 200,
}) async {
  if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');
  final uri = Uri.parse(endpoint);
  final query = Map<String, String>.of(uri.queryParameters);
  final limit = int.parse(query['Limit'] ?? '99999');
  if (limit <= 0) return [];
  final random =
      (query['SortBy'] ?? '').toLowerCase().split(',').contains('random');
  var offset = int.parse(query['StartIndex'] ?? '0');
  final result = <T>[];
  final seen = <String>{};
  while (result.length < limit) {
    if (!isCurrent()) throw MediaServerRequestSuperseded();
    query['Limit'] =
        (random ? limit : math.min(pageSize, limit - result.length)).toString();
    query['StartIndex'] = offset.toString();
    final response =
        await request(uri.replace(queryParameters: query).toString());
    if (!isCurrent()) throw MediaServerRequestSuperseded();
    if (response.statusCode != 200) {
      throw StateError('Media server page HTTP ${response.statusCode}');
    }
    final page = await decode(response.body);
    if (!isCurrent()) throw MediaServerRequestSuperseded();
    if (page.items.isEmpty) break;
    final before = result.length;
    for (var i = 0; i < page.items.length && result.length < limit; i++) {
      final id = page.ids[i];
      if (id == null || id.isEmpty || seen.add(id)) result.add(page.items[i]);
    }
    offset += page.items.length;
    if (random) break;
    if (result.length == before) {
      // A server ignoring StartIndex must not spin or silently return a prefix.
      throw StateError('Media server pagination made no progress');
    }
    if (page.total != null && offset >= page.total!) break;
    await Future<void>.delayed(Duration.zero);
  }
  return result;
}
