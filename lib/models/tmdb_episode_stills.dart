import 'package:nipaplay/models/bangumi_model.dart';

DateTime? _date(dynamic value) =>
    value is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)
        ? DateTime.tryParse(value)
        : null;

bool _special(String title) => RegExp(
        r'^(?:SP|OVA|OAD|NCOP|NCED|OP|ED|PV|CM|特别篇|特別篇|特典|总集篇|總集篇)(?:\b|\s|\d|[第：:])',
        caseSensitive: false)
    .hasMatch(title.trim());

/// Dandanplay subjects can represent one season of a multi-season TMDB show.
/// Never assume that a resolved show means season one.
Map<String, dynamic>? selectTmdbStillSeason(
    BangumiAnime anime, List<Map<String, dynamic>> seasons) {
  final regular = seasons
      .where((s) => s['season_number'] is int && s['season_number'] > 0)
      .toList();
  final episodeDates = (anime.episodeList ?? <EpisodeData>[])
      .where((e) => !_special(e.title))
      .map((e) => _date(e.airDate))
      .whereType<DateTime>()
      .toList()
    ..sort();
  final sourceDates = (anime.sourceAirDates ?? <String>[])
      .map(_date)
      .whereType<DateTime>()
      .toList()
    ..sort();
  final premiere = episodeDates.firstOrNull ??
      _date(anime.airDate) ??
      sourceDates.firstOrNull;
  if (premiere != null) {
    final exact = regular.where((s) {
      final date = _date(s['air_date']);
      return date != null && date.difference(premiere).inDays.abs() <= 1;
    }).toList();
    if (exact.length == 1) return exact.single;
    // A unique season in the subject's premiere year also handles small
    // provider date differences; two cours in the same year remain ambiguous.
    final sameYear = regular
        .where((s) => _date(s['air_date'])?.year == premiere.year)
        .toList();
    return sameYear.length == 1 ? sameYear.single : null;
  }
  return regular.length == 1 ? regular.single : null;
}

/// Match by real air date first, then explicit episode number. Do not use list
/// indices: specials, missing episodes and reversed lists would shift images.
Map<int, String> matchTmdbEpisodeStills(BangumiAnime anime,
    List<Map<String, dynamic>> rows, String? Function(String) imageUrl) {
  final result = <int, String>{};
  for (final episode in anime.episodeList ?? <EpisodeData>[]) {
    if (_special(episode.title)) continue;
    final date = _date(episode.airDate);
    final dated = date == null
        ? <Map<String, dynamic>>[]
        : rows.where((r) => _date(r['air_date']) == date).toList();
    Map<String, dynamic>? row;
    if (dated.length == 1) {
      row = dated.single;
    } else {
      final match = RegExp(r'^第\s*(\d+)\s*[话話集]').firstMatch(episode.title);
      final number = match == null ? null : int.tryParse(match.group(1)!);
      final numbered =
          rows.where((r) => r['episode_number'] == number).toList();
      if (number != null && number > 0 && numbered.length == 1) {
        final candidate = numbered.single;
        final otherDate = _date(candidate['air_date']);
        if (date == null ||
            otherDate == null ||
            date.difference(otherDate).inDays.abs() <= 1) {
          row = candidate;
        }
      }
    }
    final path = row?['still_path'];
    final url = path is String ? imageUrl(path) : null;
    if (url != null) result[episode.id] = url;
  }
  return result;
}
