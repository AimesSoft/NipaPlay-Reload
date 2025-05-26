class SearchConfig {
  final List<ConfigItem> types;
  final List<ConfigItem> tags;
  final List<ConfigItem> sorts;
  final int minYear;
  final int maxYear;

  SearchConfig({
    required this.types,
    required this.tags,
    required this.sorts,
    required this.minYear,
    required this.maxYear,
  });

  factory SearchConfig.fromJson(Map<String, dynamic> json) {
    return SearchConfig(
      types: (json['types'] as List<dynamic>?)
          ?.map((item) => ConfigItem.fromJson(item))
          .toList() ?? [],
      tags: (json['tags'] as List<dynamic>?)
          ?.map((item) => ConfigItem.fromJson(item))
          .toList() ?? [],
      sorts: (json['sorts'] as List<dynamic>?)
          ?.map((item) => ConfigItem.fromJson(item))
          .toList() ?? [],
      minYear: json['minYear'] ?? 1990,
      maxYear: json['maxYear'] ?? DateTime.now().year,
    );
  }
}

class ConfigItem {
  final int key;
  final String value;

  ConfigItem({
    required this.key,
    required this.value,
  });

  factory ConfigItem.fromJson(Map<String, dynamic> json) {
    return ConfigItem(
      key: json['key'] ?? 0,
      value: json['value'] ?? '',
    );
  }
}

class SearchResult {
  final List<SearchResultAnime> animes;
  final bool hasMore;

  SearchResult({
    required this.animes,
    this.hasMore = false,
  });

  factory SearchResult.fromTagSearchJson(Map<String, dynamic> json) {
    final bangumis = (json['bangumis'] as List<dynamic>?) ?? [];
    return SearchResult(
      animes: bangumis.map((item) => SearchResultAnime.fromJson(item)).toList(),
      hasMore: false,
    );
  }

  factory SearchResult.fromAdvancedSearchJson(Map<String, dynamic> json) {
    final bangumis = (json['bangumis'] as List<dynamic>?) ?? [];
    return SearchResult(
      animes: bangumis.map((item) => SearchResultAnime.fromJson(item)).toList(),
      hasMore: false,
    );
  }
}

class SearchResultAnime {
  final int animeId;
  final String? bangumiId;
  final String animeTitle;
  final String type;
  final String? typeDescription;
  final String? imageUrl;
  final String? startDate;
  final int episodeCount;
  final double rating;
  final bool isFavorited;
  final int? rank;
  final String? searchKeyword;
  final bool? isOnAir;
  final bool? isRestricted;
  final String? intro;

  SearchResultAnime({
    required this.animeId,
    this.bangumiId,
    required this.animeTitle,
    required this.type,
    this.typeDescription,
    this.imageUrl,
    this.startDate,
    required this.episodeCount,
    required this.rating,
    required this.isFavorited,
    this.rank,
    this.searchKeyword,
    this.isOnAir,
    this.isRestricted,
    this.intro,
  });

  factory SearchResultAnime.fromJson(Map<String, dynamic> json) {
    return SearchResultAnime(
      animeId: json['animeId'] ?? 0,
      bangumiId: json['bangumiId'],
      animeTitle: json['animeTitle'] ?? '',
      type: json['type'] ?? '',
      typeDescription: json['typeDescription'],
      imageUrl: json['imageUrl'],
      startDate: json['startDate'],
      episodeCount: json['episodeCount'] ?? 0,
      rating: (json['rating'] ?? 0.0).toDouble(),
      isFavorited: json['isFavorited'] ?? false,
      rank: json['rank'],
      searchKeyword: json['searchKeyword'],
      isOnAir: json['isOnAir'],
      isRestricted: json['isRestricted'],
      intro: json['intro'],
    );
  }
} 