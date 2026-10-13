import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';

const bangumiStatuses = {
  1: 'wish',
  2: 'done',
  3: 'doing',
  4: 'onHold',
  5: 'dropped'
};

Future<JsonMap> listCollections(
  JsonMap input, {
  required Future<JsonMap> Function(int offset, int limit) bangumi,
  required Future<List<JsonMap>> Function() dandanplay,
}) async {
  final provider = input['provider'] as String;
  final statuses = (input['statuses'] as List? ?? [])
      .cast<String>()
      .toSet()
      .toList()
    ..sort();
  final valid = provider == 'bangumi'
      ? bangumiStatuses.values.toSet()
      : {'favorited', 'finished', 'abandoned'};
  if (statuses.any((s) => !valid.contains(s))) {
    throw const Failure(
        FailureCode.invalidInput, 'Use statuses belonging to this provider.');
  }
  final limit = input['limit'] as int? ?? 100;
  final signature = sha256
      .convert(utf8.encode(jsonEncode([provider, statuses, limit])))
      .toString();
  var position = 0;
  if (input['cursor'] case final String cursor) {
    try {
      final data = jsonDecode(utf8.decode(base64Url.decode(cursor))) as Map;
      if (data['query'] != signature ||
          data['position'] is! int ||
          (data['position'] as int) < 0) {
        throw const FormatException();
      }
      position = data['position'] as int;
    } on FormatException {
      throw const Failure(
          FailureCode.invalidInput, 'Invalid collections cursor.');
    } on TypeError {
      throw const Failure(
          FailureCode.invalidInput, 'Invalid collections cursor.');
    }
  }
  bool accepts(String status) => statuses.isEmpty || statuses.contains(status);
  final items = <JsonMap>[];
  bool more;
  if (provider == 'bangumi') {
    final page = await bangumi(position, limit);
    final rows = (page['data'] as List).cast<Map>();
    for (final row in rows) {
      final status = bangumiStatuses[row['type']];
      if (status == null)
        throw const Failure(
            FailureCode.unavailable, 'Unknown Bangumi collection status.');
      if (accepts(status))
        items.add({
          'workId': row['subject_id'],
          'status': status,
          'rating': row['rate']
        });
    }
    position += rows.length;
    more = position < (page['total'] as int);
  } else {
    final rows = (await dandanplay())
        .where((row) => (row['animeId'] as int) > position)
        .toList()
      ..sort((a, b) => (a['animeId'] as int).compareTo(b['animeId'] as int));
    final selected = <JsonMap>[];
    for (final row in rows) {
      final status = row['favoriteStatus'] as String;
      if (!valid.contains(status))
        throw const Failure(
            FailureCode.unavailable, 'Unknown Dandanplay collection status.');
      if (accepts(status))
        selected.add({
          'workId': row['animeId'],
          'status': status,
          'rating': row['userRating'] ?? row['rating']
        });
    }
    items.addAll(selected.take(limit));
    if (items.isNotEmpty) position = items.last['workId'] as int;
    more = selected.length > items.length;
  }
  return {
    'items': items,
    'nextCursor': more
        ? base64Url.encode(utf8.encode(jsonEncode({
            'query': signature,
            'position': position,
          })))
        : null
  };
}
