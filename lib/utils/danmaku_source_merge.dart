import 'dart:convert';

/// Display folding never edits source lists. Reliable origin identities fold
/// across tracks; unknown aggregation overlap uses exact long text in 100 ms.
List<Map<String, dynamic>> foldDanmakuSources(
    List<Map<String, dynamic>> input) {
  final result = <Map<String, dynamic>>[];
  final identities = <String, Map<String, dynamic>>{};
  final textGroups = <String, List<Map<String, dynamic>>>{};
  for (final original in input) {
    final item = {...original};
    final track = item['nextTrackId'] ?? item['sourceId'] ?? item['source'];
    final reliable = item['platformVideoId'] != null &&
        item['platformDanmakuId'] != null &&
        item['source'] != 'unknown';
    final key = reliable
        ? jsonEncode([
            item['source'],
            item['platformVideoId'],
            item['platformDanmakuId']
          ])
        : null;
    Map<String, dynamic>? duplicate;
    bool hasTrack(Map<String, dynamic> candidate) =>
        (candidate['displayMembers'] as List<Map<String, dynamic>>)
            .any((member) => member['trackId'] == track);
    if (key != null) {
      final candidate = identities[key];
      if (candidate != null &&
          candidate['nextTrackId'] != item['nextTrackId'] &&
          candidate['foldEnabled'] == true &&
          item['foldEnabled'] == true &&
          !hasTrack(candidate) &&
          ((candidate['time'] as num) - (item['time'] as num)).abs() <= .1) {
        duplicate = candidate;
      }
    }
    final text = item['content'] as String;
    final textKey = jsonEncode([text, item['type'], item['color']]);
    final groups = textGroups[textKey] ??= [];
    if (duplicate == null &&
        text.runes.length >= 8 &&
        item['foldEnabled'] == true) {
      for (final candidate in groups.reversed) {
        if ((item['time'] as num) - (candidate['time'] as num) > .1) break;
        final candidateTrack = candidate['nextTrackId'] ??
            candidate['sourceId'] ??
            candidate['source'];
        final unknownOverlap = (candidate['aggregation'] == true &&
                candidate['source'] == 'unknown' ||
            item['aggregation'] == true && item['source'] == 'unknown');
        if (candidateTrack != track &&
            !hasTrack(candidate) &&
            candidate['foldEnabled'] == true &&
            unknownOverlap) {
          duplicate = candidate;
          break;
        }
      }
    }
    if (duplicate != null) {
      final members = duplicate['displayMembers'] as List<Map<String, dynamic>>;
      members.add({
        'trackId': track,
        'source': item['source'],
        'id': item['platformDanmakuId']
      });
      duplicate['displayCount'] = members.length;
    } else {
      item['displayMembers'] = <Map<String, dynamic>>[
        {
          'trackId': track,
          'source': item['source'],
          'id': item['platformDanmakuId']
        }
      ];
      item['displayCount'] = 1;
      result.add(item);
      groups.add(item);
      if (key != null) identities[key] = item;
    }
  }
  return result;
}
