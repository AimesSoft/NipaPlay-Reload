import 'package:nipaplay/models/bangumi_model.dart';

enum TrendingRankingKind {
  allHot,
  allRising,
  newAnimeHot,
}

extension TrendingRankingKindExtension on TrendingRankingKind {
  String get label {
    switch (this) {
      case TrendingRankingKind.allHot:
        return '全站热播';
      case TrendingRankingKind.allRising:
        return '全站飙升';
      case TrendingRankingKind.newAnimeHot:
        return '新番热播';
    }
  }
}

enum TrendingPeriod {
  week,
  month,
  quarter,
}

extension TrendingPeriodExtension on TrendingPeriod {
  String get apiValue => name;

  String get label {
    switch (this) {
      case TrendingPeriod.week:
        return '周榜';
      case TrendingPeriod.month:
        return '月榜';
      case TrendingPeriod.quarter:
        return '季度榜';
    }
  }
}

enum TrendingNewAnimeScope {
  currentSeason,
  previousSeason,
}

extension TrendingNewAnimeScopeExtension on TrendingNewAnimeScope {
  String get apiValue {
    switch (this) {
      case TrendingNewAnimeScope.currentSeason:
        return 'current-season';
      case TrendingNewAnimeScope.previousSeason:
        return 'previous-season';
    }
  }

  String get label {
    switch (this) {
      case TrendingNewAnimeScope.currentSeason:
        return '本季';
      case TrendingNewAnimeScope.previousSeason:
        return '上季';
    }
  }
}

class TrendingBangumiQuery {
  const TrendingBangumiQuery({
    required this.kind,
    this.period = TrendingPeriod.week,
    this.scope = TrendingNewAnimeScope.currentSeason,
  });

  final TrendingRankingKind kind;
  final TrendingPeriod period;
  final TrendingNewAnimeScope scope;

  String get apiPath {
    switch (kind) {
      case TrendingRankingKind.allHot:
        return '/api/v2/trending/all/hot/${period.apiValue}';
      case TrendingRankingKind.allRising:
        return '/api/v2/trending/all/rising/${period.apiValue}';
      case TrendingRankingKind.newAnimeHot:
        return '/api/v2/trending/new-anime/hot/${scope.apiValue}';
    }
  }

  String get cacheKey {
    switch (kind) {
      case TrendingRankingKind.allHot:
        return 'all_hot_${period.apiValue}';
      case TrendingRankingKind.allRising:
        return 'all_rising_${period.apiValue}';
      case TrendingRankingKind.newAnimeHot:
        return 'new_anime_hot_${scope.apiValue}';
    }
  }

  String get dimensionLabel =>
      kind == TrendingRankingKind.newAnimeHot ? scope.label : period.label;
}

class TrendingBangumiResult {
  const TrendingBangumiResult({
    required this.summary,
    required this.items,
  });

  final TrendingSummary summary;
  final List<TrendingBangumiItem> items;

  factory TrendingBangumiResult.fromJson(Map<String, dynamic> json) {
    final rawSummary = json['summary'];
    final rawItems = json['bangumiList'];
    return TrendingBangumiResult(
      summary: rawSummary is Map
          ? TrendingSummary.fromJson(rawSummary.cast<String, dynamic>())
          : const TrendingSummary(),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => TrendingBangumiItem.fromJson(
                    item.cast<String, dynamic>(),
                  ))
              .where((item) => item.anime.id > 0)
              .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'summary': summary.toJson(),
      'bangumiList': items.map((item) => item.toJson()).toList(),
    };
  }
}

class TrendingSummary {
  const TrendingSummary({
    this.title,
    this.rankingType,
    this.period,
    this.scope,
    this.dateFrom,
    this.dateTo,
    this.compareDateFrom,
    this.compareDateTo,
    this.latestDataDate,
  });

  final String? title;
  final String? rankingType;
  final String? period;
  final String? scope;
  final String? dateFrom;
  final String? dateTo;
  final String? compareDateFrom;
  final String? compareDateTo;
  final String? latestDataDate;

  factory TrendingSummary.fromJson(Map<String, dynamic> json) {
    String? readString(String key) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    return TrendingSummary(
      title: readString('title'),
      rankingType: readString('rankingType'),
      period: readString('period'),
      scope: readString('scope'),
      dateFrom: readString('dateFrom'),
      dateTo: readString('dateTo'),
      compareDateFrom: readString('compareDateFrom'),
      compareDateTo: readString('compareDateTo'),
      latestDataDate: readString('latestDataDate'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'rankingType': rankingType,
      'period': period,
      'scope': scope,
      'dateFrom': dateFrom,
      'dateTo': dateTo,
      'compareDateFrom': compareDateFrom,
      'compareDateTo': compareDateTo,
      'latestDataDate': latestDataDate,
    };
  }
}

class TrendingBangumiItem {
  const TrendingBangumiItem({
    required this.anime,
    required this.rank,
    this.heat,
    this.activeDays,
    this.previousHeat,
    this.heatDelta,
    this.heatGrowthRate,
  });

  final BangumiAnime anime;
  final int rank;
  final String? heat;
  final int? activeDays;
  final String? previousHeat;
  final String? heatDelta;
  final String? heatGrowthRate;

  TrendingBangumiItem copyWith({BangumiAnime? anime}) {
    return TrendingBangumiItem(
      anime: anime ?? this.anime,
      rank: rank,
      heat: heat,
      activeDays: activeDays,
      previousHeat: previousHeat,
      heatDelta: heatDelta,
      heatGrowthRate: heatGrowthRate,
    );
  }

  factory TrendingBangumiItem.fromJson(Map<String, dynamic> json) {
    int? readInt(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    String? readString(dynamic value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final rawAnime = json['anime'];
    final anime = rawAnime is Map
        ? BangumiAnime.fromJson(rawAnime.cast<String, dynamic>())
        : BangumiAnime.fromDandanplayIntro(json);

    return TrendingBangumiItem(
      anime: anime,
      rank: readInt(json['rank']) ?? 0,
      heat: readString(json['heat']),
      activeDays: readInt(json['activeDays']),
      previousHeat: readString(json['previousHeat']),
      heatDelta: readString(json['heatDelta']),
      heatGrowthRate: readString(json['heatGrowthRate']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'anime': anime.toJson(),
      'rank': rank,
      'heat': heat,
      'activeDays': activeDays,
      'previousHeat': previousHeat,
      'heatDelta': heatDelta,
      'heatGrowthRate': heatGrowthRate,
    };
  }
}
