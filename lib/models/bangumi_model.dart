class BangumiAnime {
  final int id; // Corresponds to Dandanplay's animeId
  final String name; // Corresponds to Dandanplay's animeTitle, primary name
  final String nameCn; // Potentially from Dandanplay's titles array or use animeTitle if only one
  final String imageUrl;
  final String? summary;
  final String? airDate; // Dandanplay's BangumiQueueIntroV2 provides airDate, BangumiDetails might have more specific first episode air date
  final int? airWeekday; // Corresponds to Dandanplay's airDay (0 for Sun, 1-6 for Mon-Sat)
  final double? rating; // Dandanplay's rating (0-10)
  final Map<String, dynamic>? ratingDetails;
  final List<String>? tags; // From Dandanplay's tags array (BangumiTag object needs name extraction)
  final List<String>? metadata; // Store Dandanplay's metadata string array
  final bool? isNSFW; // Corresponds to Dandanplay's isRestricted
  final String? platform; // No direct equivalent in Dandanplay Intro/Details for this specific field name
  final int? totalEpisodes; // From Dandanplay's episodes array count in BangumiDetails
  final String? typeDescription; // From Dandanplay's typeDescription
  final String? bangumiUrl;

  // Dandanplay specific fields we might want to use:
  final bool? isOnAir;
  final bool? isFavorited; // User-specific, from Dandanplay
  final List<Map<String, String>>? titles; // Store Dandanplay's titles array [{'title': 'name', 'language': 'lang'}]
  final String? searchKeyword;

  final List<EpisodeData>? episodeList; // Changed from 'episodes' to 'episodeList' to avoid conflict if 'episodes' is a field name in JSON for BangumiDetails itself.

  bool get hasDetails => summary != null && (rating != null || ratingDetails != null) && (tags != null || metadata != null);

  BangumiAnime({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    this.summary,
    this.airDate,
    this.airWeekday,
    this.rating,
    this.ratingDetails,
    this.tags,
    this.metadata,
    this.isNSFW,
    this.platform,
    this.totalEpisodes,
    this.typeDescription,
    this.bangumiUrl,
    this.isOnAir,
    this.isFavorited,
    this.titles,
    this.searchKeyword,
    this.episodeList,
  });

  // Used for list items from Dandanplay's /api/v2/bangumi/shin (BangumiIntro schema)
  factory BangumiAnime.fromDandanplayIntro(Map<String, dynamic> json) {
    final String? imgUrl = json['imageUrl'];
    // if (imgUrl == null || imgUrl.isEmpty) {
    //   // Consider a placeholder or different handling if image is crucial
    //   // For now, let's allow it to be potentially empty and handle in UI
    // }

    return BangumiAnime(
      id: json['animeId'] as int? ?? 0,
      name: json['animeTitle'] as String? ?? '',
      nameCn: json['animeTitle'] as String? ?? '', // Default to animeTitle, can be refined if 'titles' are available in intro
      imageUrl: imgUrl ?? 'assets/backempty.png', // Provide a default placeholder
      airWeekday: json['airDay'] as int?, // 0 for Sun, 1-6 for Mon-Sat
      rating: (json['rating'] as num?)?.toDouble(),
      isOnAir: json['isOnAir'] as bool?,
      isFavorited: json['isFavorited'] as bool?,
      isNSFW: json['isRestricted'] as bool?,
      searchKeyword: json['searchKeyword'] as String?,
      // Fields not in BangumiIntro, will be null or default:
      summary: null,
      airDate: null, // airDate in BangumiQueueIntroV2, not directly in BangumiIntro for shin bangumi list
      tags: null,
      metadata: null,
      platform: null,
      totalEpisodes: null,
      typeDescription: null,
      titles: null,
      episodeList: null, // Episodes are not in BangumiIntro
    );
  }

  // Used for detailed items from Dandanplay's /api/v2/bangumi/{animeId} (BangumiDetails schema)
  factory BangumiAnime.fromDandanplayDetail(Map<String, dynamic> json) {
    // BangumiDetails inherits from BangumiIntro, so all intro fields are present
    // final String? imageUrl = json['imageUrl'];

    // //debugPrint('Rating Details from API: ${json['ratingDetails']}'); // 这行之前移除了

    // 新增：打印 bangumiUrl
    //debugPrint('Bangumi URL from API: ${json['bangumiUrl']}');

    List<String> parseTags(List<dynamic>? tagsData) {
      if (tagsData == null) return [];
      return tagsData
          .map((tag) => (tag is Map && tag['name'] != null) ? tag['name'] as String : null)
          .where((name) => name != null)
          .cast<String>()
          .toList();
    }
    
    String primaryTitle = json['animeTitle'] as String? ?? '';
    String chineseTitle = primaryTitle; // Default

    List<Map<String, String>> parsedTitles = [];
    if (json['titles'] != null && json['titles'] is List) {
      for (var titleEntry in json['titles']) {
        if (titleEntry is Map && titleEntry['title'] != null && titleEntry['language'] != null) {
          parsedTitles.add({
            'title': titleEntry['title'] as String,
            'language': titleEntry['language'] as String,
          });
          // Attempt to find a Chinese title
          if ((titleEntry['language'] as String).toLowerCase().contains('zh') || (titleEntry['language'] as String).toLowerCase().contains('cn')) {
            chineseTitle = titleEntry['title'] as String;
          }
        }
      }
      if (parsedTitles.isNotEmpty && primaryTitle.isEmpty) {
        primaryTitle = parsedTitles.first['title']!;
      }
    }


    List<String>? parsedMetadata;
    if (json['metadata'] != null && json['metadata'] is List) {
      parsedMetadata = (json['metadata'] as List).map((item) => item.toString()).toList();
    }

    List<EpisodeData>? parsedEpisodeList;
    // 首先检查episodes字段（API返回格式）
    if (json['episodes'] != null && json['episodes'] is List) {
      parsedEpisodeList = (json['episodes'] as List)
          .map((epJson) => EpisodeData.fromJson(epJson as Map<String, dynamic>))
          .toList();
    }
    // 如果没有episodes字段，则尝试从episodeList字段加载（缓存格式）
    else if (json['episodeList'] != null && json['episodeList'] is List) {
      parsedEpisodeList = [];
      for (var epJson in json['episodeList'] as List) {
        if (epJson is Map<String, dynamic>) {
          // 处理旧格式（只有id和title）
          if (epJson.containsKey('id') && epJson.containsKey('title')) {
            parsedEpisodeList.add(EpisodeData(
              id: epJson['id'] as int? ?? 0,
              title: epJson['title'] as String? ?? '未知剧集',
              airDate: null,
            ));
          }
          // 处理新格式（与API格式相同）
          else if (epJson.containsKey('episodeId') && epJson.containsKey('episodeTitle')) {
            parsedEpisodeList.add(EpisodeData(
              id: epJson['episodeId'] as int? ?? 0,
              title: epJson['episodeTitle'] as String? ?? '未知剧集',
              airDate: epJson['airDate'] as String?,
            ));
          }
        }
      }
    }

    Map<String, dynamic>? rawRatingDetails = json['ratingDetails'] as Map<String, dynamic>?;
    String? bangumiUrlValue = json['bangumiUrl'] as String?;

    // 检查是否存在totalEpisodes信息
    int? totalEpisodesCount = json['totalEpisodes'] as int?;
    // 如果没有直接的totalEpisodes但有剧集列表，从列表中计算总数
    if (totalEpisodesCount == null && parsedEpisodeList != null) {
      totalEpisodesCount = parsedEpisodeList.length;
    }

    return BangumiAnime(
      id: json['animeId'] as int? ?? json['id'] as int? ?? 0, // 支持两种格式
      name: primaryTitle,
      nameCn: chineseTitle,
      imageUrl: json['imageUrl'] as String? ?? 'assets/backempty.png',
      summary: json['summary'] as String?,
      // 尝试从多个可能的来源获取首播日期
      airDate: json['air_date'] as String? ?? 
              ((parsedEpisodeList != null && parsedEpisodeList.isNotEmpty && parsedEpisodeList[0].airDate != null) 
                ? parsedEpisodeList[0].airDate
                : ((json['episodes'] != null && (json['episodes'] as List).isNotEmpty && json['episodes'][0]['airDate'] != null)
                    ? json['episodes'][0]['airDate'] as String
                    : null)),
      airWeekday: json['airDay'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
      ratingDetails: rawRatingDetails,
      tags: parseTags(json['tags'] as List<dynamic>?),
      metadata: parsedMetadata,
      isNSFW: json['isNSFW'] as bool?,
      totalEpisodes: totalEpisodesCount,
      typeDescription: json['typeDescription'] as String?,
      bangumiUrl: bangumiUrlValue,
      isOnAir: json['isOnAir'] as bool?,
      isFavorited: json['isFavorited'] as bool?,
      titles: parsedTitles,
      searchKeyword: json['searchKeyword'] as String?,
      episodeList: parsedEpisodeList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'name_cn': nameCn,
      'imageUrl': imageUrl,
      'summary': summary,
      'air_date': airDate,
      'airDay': airWeekday,
      'rating': rating,
      'ratingDetails': ratingDetails,
      'tags': tags,
      'metadata': metadata,
      'isNSFW': isNSFW,
      'platform': platform,
      'totalEpisodes': totalEpisodes,
      'typeDescription': typeDescription,
      'bangumiUrl': bangumiUrl,
      'isOnAir': isOnAir,
      'isFavorited': isFavorited,
      'titles': titles?.map((t) => {'title': t['title'], 'language': t['language']}).toList(),
      'searchKeyword': searchKeyword,
      'episodeList': episodeList?.map((e) => {
        'episodeId': e.id, 
        'episodeTitle': e.title,
        'airDate': e.airDate
      }).toList(),
      'episodes': episodeList?.map((e) => {
        'episodeId': e.id, 
        'episodeTitle': e.title,
        'airDate': e.airDate
      }).toList(), // 额外保存一份原始格式的数据，确保fromDandanplayDetail能正确解析
    };
  }
}

class EpisodeData {
  final int id; // Corresponds to Dandanplay's episodeId in BangumiEpisode schema
  final String title;
  final String? airDate; // From BangumiEpisode schema

  EpisodeData({required this.id, required this.title, this.airDate});

  factory EpisodeData.fromJson(Map<String, dynamic> json) {
    // Assuming 'json' is an item from the 'episodes' array in BangumiDetails
    // which refers to '#/components/schemas/BangumiEpisode'
    return EpisodeData(
      id: json['episodeId'] as int? ?? 0,
      title: json['episodeTitle'] as String? ?? '未知剧集',
      airDate: json['airDate'] as String?,
    );
  }
} 