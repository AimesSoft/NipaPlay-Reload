import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/next/state/calendar_material.dart';

void main() {
  BangumiAnime anime(int id) => BangumiAnime(
      id: id, name: 'n$id', nameCn: '名$id', imageUrl: 'u$id', airWeekday: 1);

  test(
      'the calendar material gives the rows Classic\'s own models give, and crosses isolates',
      () async {
    final intro = [anime(1), anime(2)];
    final held = anime(2).copyWith(
        episodeList: [EpisodeData(id: 20, title: 'ep', airDate: '2026-10-25')],
        isFavorited: true);
    final material = CalendarMaterial(
        cache: jsonEncode({
          'animes': [for (final a in intro) a.toJson()]
        }),
        memory: [held]);
    final expected = [
      for (final stored in intro)
        Map<String, Object?>.from((() {
          final a = BangumiAnime.fromJson(stored.toJson());
          return a.id == 2
              ? a.copyWith(
                  episodeList: held.episodeList,
                  isFavorited: held.isFavorited ?? a.isFavorited)
              : a;
        })()
            .toJson())
    ];
    expect(material.rows(), expected);
    expect(identical(material.rows(), material.rows()), isTrue);
    expect(material.rows()[1]['episodeList'], isNotEmpty);

    // The worker receives it through a port and decodes it there.
    final viaPort = await Isolate.run(() => material.rows());
    expect(viaPort, expected);
    expect(CalendarMaterial().rows(), isEmpty);
    expect(CalendarMaterial.encoded(jsonEncode(expected)).rows(), expected);
  });
}
