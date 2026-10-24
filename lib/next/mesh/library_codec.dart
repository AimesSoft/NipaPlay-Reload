import 'package:nipa_harness/nipa_harness.dart';
import '../ui_data/ui_data.dart';

JsonMap episodeJson(UiEpisode e) => {
      'episodeId': e.episodeId,
      'workId': e.workId,
      'number': e.number,
      'season': e.season,
      'title': e.title,
      'runtimeMs': e.runtime?.inMilliseconds,
      'still': e.still,
      'progress': e.progress,
      'heat': e.heat,
      'playable': e.playable,
      'device': e.device == null
          ? null
          : {'name': e.device!.name, 'online': e.device!.online},
    };
JsonMap workJson(UiWork w) => {
      'workId': w.workId,
      'title': w.title,
      'originalTitle': w.originalTitle,
      'year': w.year,
      'genres': w.genres,
      'episodeCount': w.episodeCount,
      'film': w.film,
      'runtimeMs': w.runtime?.inMilliseconds,
      'studio': w.studio,
      'overview': w.overview,
      'ratings': [
        for (final r in w.ratings) {'source': r.source, 'value': r.value}
      ],
      'artwork': {
        'backdrop': w.artwork.backdrop,
        'poster': w.artwork.poster,
        'logo': w.artwork.logo,
        'tint': w.artwork.tint
      },
      'danmaku': w.danmaku,
      'devices': [
        for (final d in w.devices) {'name': d.name, 'online': d.online}
      ],
      'next': w.next == null ? null : episodeJson(w.next!),
    };
UiEpisode episodeValue(JsonMap e, {UiDevice? device}) => UiEpisode(
    episodeId: e['episodeId'] as String,
    workId: e['workId'] as String,
    number: e['number'] as int?,
    season: e['season'] as int?,
    title: e['title'] as String?,
    runtime: e['runtimeMs'] == null
        ? null
        : Duration(milliseconds: e['runtimeMs'] as int),
    still: e['still'] as String?,
    progress: (e['progress'] as num?)?.toDouble(),
    heat: (e['heat'] as List?)?.map((n) => (n as num).toDouble()).toList(),
    playable: e['playable'] == true && (device?.online ?? true),
    device: device);
UiWork workValue(JsonMap w, List<UiEpisode> episodes, List<UiDevice> devices) {
  final a = w['artwork'] as Map;
  final next = episodes
          .where((e) =>
              e.playable && (e.progress ?? 0) > 0 && (e.progress ?? 0) < 1)
          .firstOrNull ??
      episodes.where((e) => e.playable && (e.progress ?? 0) < 1).firstOrNull ??
      episodes.where((e) => (e.progress ?? 0) < 1).firstOrNull;
  return UiWork(
      workId: w['workId'] as String,
      title: w['title'] as String,
      originalTitle: w['originalTitle'] as String?,
      year: w['year'] as int?,
      genres: (w['genres'] as List).cast<String>(),
      episodeCount: (w['episodeCount'] as int?) ??
          (episodes.isEmpty ? null : episodes.length),
      film: w['film'] == true,
      runtime: w['runtimeMs'] == null
          ? null
          : Duration(milliseconds: w['runtimeMs'] as int),
      studio: w['studio'] as String?,
      overview: w['overview'] as String?,
      ratings: [
        for (final r in (w['ratings'] as List).cast<Map>())
          UiRating(r['source'] as String, (r['value'] as num).toDouble())
      ],
      artwork: UiArtwork(
          backdrop: a['backdrop'] as String?,
          poster: a['poster'] as String?,
          logo: a['logo'] as String?,
          tint: a['tint'] as int?),
      danmaku: (w['danmaku'] as List).cast<String>(),
      next: next,
      devices: devices);
}

/// Rebuilds one work from the compact record published by the library worker.
/// The record carries the selected next episode directly, so the UI does not
/// need a catalogue-sized episode map just to decode a work on demand.
UiWork transferredWorkValue(JsonMap w) {
  final rawNext = w['next'] as Map?;
  final nextDevice = rawNext?['device'] as Map?;
  final next = rawNext == null
      ? const <UiEpisode>[]
      : [
          episodeValue(rawNext.cast<String, Object?>(),
              device: nextDevice == null
                  ? null
                  : UiDevice(
                      name: nextDevice['name'] as String,
                      online: nextDevice['online'] == true))
        ];
  final devices = [
    for (final device in (w['devices'] as List? ?? const []).cast<Map>())
      UiDevice(name: device['name'] as String, online: device['online'] == true)
  ];
  return workValue(w, next, devices);
}
