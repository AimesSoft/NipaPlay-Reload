/// Shared normalization for Classic and Next. Only explicit origin fields
/// establish a platform identity; the aggregator's cid is a source entry ID.
List<Map<String, dynamic>> restoreDandanplayOrigins(List<dynamic> comments) => [
      for (final raw in comments)
        {
          ...Map<String, dynamic>.from(raw as Map),
          if (raw['source'] == 'dandanplay' && !raw.containsKey('originSource'))
            'source': 'unknown'
        }
    ];

Map<String, dynamic> parseDandanplayComment(Map<String, dynamic> row) {
  if (row['p'] is! String || row['m'] is! String) {
    throw const FormatException('Invalid dandanplay comment');
  }
  final parts = (row['p'] as String).split(',');
  if (parts.length < 4) throw const FormatException('Invalid dandanplay p');
  final time = double.parse(parts[0]);
  if (!time.isFinite || time < 0) {
    throw const FormatException('Invalid comment time');
  }
  final mode = int.parse(parts[1]), color = int.parse(parts[2]);
  final origin = row['source'];
  if (origin != null && origin is! String && origin is! int) {
    throw const FormatException('Invalid origin');
  }
  for (final field in ['cid', 'sourceVideoId', 'originalId']) {
    final value = row[field];
    if (value != null &&
        (value is! String && value is! int ||
            value is String && value.isEmpty ||
            value is int && value <= 0)) {
      throw const FormatException('Invalid origin identifier');
    }
  }
  final platform =
      origin is String && RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(origin)
          ? origin
          : 'unknown';
  return {
    'time': time,
    'sourceTimeMs': (time * 1000).round(),
    'content': row['m'] as String,
    'type': mode == 4
        ? 'bottom'
        : mode == 5
            ? 'top'
            : 'scroll',
    'originalMode': mode,
    'colorRgb': color,
    'color': 'rgb(${color >> 16},${(color >> 8) & 255},${color & 255})',
    'source': platform,
    'sourceId': 'dandanplay',
    'originSource': origin?.toString(),
    'sourceEntryId': row['cid']?.toString(),
    'platformVideoId': row['sourceVideoId']?.toString(),
    'platformDanmakuId': row['originalId']?.toString(),
    if (parts[3].isNotEmpty && parts[3] != '0') 'senderId': parts[3],
    if (row['cid'] != null) 'cid': row['cid'],
    'isMe': false
  };
}
