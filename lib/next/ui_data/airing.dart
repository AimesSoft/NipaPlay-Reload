import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipa_harness/nipa_harness.dart';
import '../media/identity_store.dart';

/// Episode dates are facts; a weekly slot alone cannot establish a new episode.
Future<List<JsonMap>> todayUpdates(
    IdentityStore store, Set<String> following, List<JsonMap> cached) async {
  var calendar = [for (final row in cached) BangumiAnime.fromJson(Map<String, dynamic>.from(row))];
  if (calendar.isEmpty && following.isNotEmpty && DandanplayService.isLoggedIn) {
    calendar = await BangumiService.instance.getCalendar();
  }
  if (calendar.isEmpty) return [];
  final now = DateTime.now();
  final result = <JsonMap>[];
  for (final anime in calendar) {
    final works = await store.database.rawQuery(
        "SELECT DISTINCT e.id FROM media_entities e JOIN media_bindings b ON b.entity_id=e.id JOIN media_external_objects o ON o.id=b.object_id WHERE e.kind='work' AND b.status='accepted' AND o.provider='dandanplay' AND o.object_type='anime' AND o.external_id=?",
        ['${anime.id}']);
    for (final work in works) {
      final id = work['id'] as String;
      if (!following.contains(id) && anime.isFavorited != true) continue;
      final episodes = anime.episodeList ?? (DandanplayService.isLoggedIn
          ? (await BangumiService.instance.getAnimeDetails(anime.id)).episodeList
          : null) ?? [];
      for (var index = 0; index < episodes.length; index++) {
        final episode = episodes[index];
        final raw = episode.airDate;
        if (raw == null) continue;
        final parsed = DateTime.tryParse(raw);
        if (parsed == null) continue;
        final date = parsed.toLocal();
        if (date.year != now.year ||
            date.month != now.month ||
            date.day != now.day) continue;
        final hasTime = RegExp(r'[T ]\d{2}:\d{2}').hasMatch(raw);
        final clock = hasTime
            ? ' ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
            : '';
        result.removeWhere((row) => row['workId'] == id);
        result.add({
          'workId': id,
          'externalEpisodeId': '${episode.id}',
          'number': index + 1,
          'caption': '第 ${index + 1} 集 · 今天$clock'
        });
      }
    }
  }
  return result;
}
