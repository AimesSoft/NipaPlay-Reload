import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';

import '../../next_runtime.dart';
import '../../ui_data/found.dart';
import '../../ui_data/ui_data.dart';

export '../../ui_data/found.dart' show Found, FoundRef;

/// What the 发现 page reads: the new-series calendar and the rankings, from
/// the same `discover.*` Actions the agent uses. Read only; kept apart from
/// [NextUiData]. [details] also fills the page of a found work an agent's
/// card opened.
abstract interface class NextDiscoverData {
  Future<UiDiscover> discover();

  /// A found work with what its page needs (overview, episode count), read
  /// when the page opens.
  Future<UiWork> details(UiWork work);
}

/// A work as the calendar or a ranking shows it.
final class UiFound {
  const UiFound(this.work, {this.followed = false});

  /// In the library: its library work. Otherwise a work only known from
  /// discovery ([Found.isFound]), whose page offers “让 Nipa 准备”.
  final UiWork work;

  /// You follow it (a favourite on your account).
  final bool followed;
}

final class UiRanking {
  const UiRanking(
      {required this.source, required this.title, required this.items});

  /// Where the ranking comes from, as people call it: “弹弹play”, “Bangumi”.
  final String source;

  /// “本周热播”.
  final String title;

  /// In rank order.
  final List<UiFound> items;
}

final class UiDiscover {
  const UiDiscover({
    this.today = 0,
    this.days = const {},
    this.rankings = const [],
    this.signedOut = false,
  });

  /// 0 = Sunday … 6 = Saturday.
  final int today;
  final Map<int, List<UiFound>> days;
  final List<UiRanking> rankings;

  /// The calendar and rankings need a 弹弹play account.
  final bool signedOut;
}

/// The real data: `discover.calendar` and `discover.trending_batch` (X29),
/// and `media.metadata.get` for a page, invoked as the interface.
final class CoreDiscover implements NextDiscoverData {
  CoreDiscover(this.runtime);
  final NextRuntime runtime;

  Future<JsonMap> _call(String action, JsonMap input) async {
    final outcome = await (await runtime.harnessReady)
        .invokeJson(action, input, Invocation(origin: 'gui'));
    return switch (outcome) {
      Completed(:final value) => value.toJson(),
      Failed(:final failure) => throw failure,
      NeedsDecision() => throw StateError('$action asked for a decision'),
    };
  }

  static const _rankings = [
    ('allHot', 'week', '本周热播'),
    ('allRising', 'week', '本周飙升'),
    ('newAnimeHot', 'currentSeason', '本季新番'),
  ];

  @override
  Future<UiDiscover> discover() async {
    final accounts = (await _call('accounts.status', {}))['accounts'] as List;
    final dandanplay =
        accounts.cast<Map>().firstWhere((a) => a['provider'] == 'dandanplay');
    if (dandanplay['loggedIn'] != true) {
      return const UiDiscover(signedOut: true);
    }
    final (calendar, trending) = await (
      _call('discover.calendar', {}),
      _call('discover.trending_batch', {
        'requests': [
          for (final (kind, range, _) in _rankings)
            {'kind': kind, 'range': range, 'limit': 20}
        ]
      }),
    ).wait;
    final days = <int, List<UiFound>>{
      for (final group in (calendar['groups'] as List).cast<Map>())
        if (group['weekday'] as int >= 0)
          group['weekday'] as int: [
            for (final anime in (group['animes'] as List).cast<Map>())
              _found(anime)
          ],
    };
    final results = (trending['results'] as List).cast<Map>();
    return UiDiscover(
      today: calendar['todayWeekday'] as int,
      days: days,
      rankings: [
        for (final (i, (_, _, title)) in _rankings.indexed)
          if (results[i]['result'] case final Map result)
            UiRanking(source: '弹弹play', title: title, items: [
              for (final row in (result['bangumiList'] as List).cast<Map>())
                _found(row['anime'] as Map)
            ]),
      ],
    );
  }

  static UiFound _found(Map anime) {
    String? text(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    final rating = anime['rating'];
    final tags = anime['tags'];
    return UiFound(
      UiWork(
        workId: Found.id('dandanplay', anime['id']),
        title: text(anime['name_cn']) ?? text(anime['name']) ?? '',
        originalTitle: text(anime['name']),
        year: int.tryParse(text(anime['air_date'])?.split('-').first ?? ''),
        genres: tags is List ? tags.whereType<String>().take(3).toList() : [],
        episodeCount: anime['totalEpisodes'] as int?,
        overview: text(anime['summary']),
        ratings: [
          if (rating is num && rating > 0) UiRating('弹弹play', rating.toDouble())
        ],
        artwork: UiArtwork(poster: text(anime['imageUrl'])),
      ),
      followed: anime['isFavorited'] == true,
    );
  }

  @override
  Future<UiWork> details(UiWork work) async {
    final ref = Found.ref(work.workId);
    if (ref == null) return work;
    final record = (await _call('media.metadata.get', {
      'ref': {
        'provider': ref.provider,
        'objectType': ref.objectType,
        'externalId': ref.externalId,
        'scope': '',
      }
    }))['record'] as Map;
    return Found.withRecord(work, record);
  }
}
