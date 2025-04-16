class BangumiAnime {
  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final String? summary;
  final String? airDate;
  final int? airWeekday;
  final double? rating;
  final List<String>? tags;
  final Map<String, dynamic> staff;
  final bool? isNSFW;
  final bool? isLocked;
  final String? platform;
  final int? totalEpisodes;
  final String? originalWork; // 原作
  final String? director; // 导演
  final String? studio; // 制作公司

  bool get hasDetails => summary != null && rating != null && tags != null;

  BangumiAnime({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    this.summary,
    this.airDate,
    this.airWeekday,
    this.rating,
    this.tags,
    this.staff = const {},
    this.isNSFW,
    this.isLocked,
    this.platform,
    this.totalEpisodes,
    this.originalWork,
    this.director,
    this.studio,
  });

  // 用于列表页的简化构造方法
  factory BangumiAnime.fromCalendarItem(Map<String, dynamic> json) {
    final String? imageUrl = json['images']?['large'];
    if (imageUrl == null || imageUrl.isEmpty) {
      throw Exception('Missing or empty image URL');
    }

    final airWeekday = json['air_weekday'] as int?;

    return BangumiAnime(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      nameCn: json['name_cn'] as String? ?? json['name'] as String? ?? '',
      imageUrl: imageUrl,
      airDate: json['air_date'] as String?,
      airWeekday: airWeekday,
    );
  }

  // 用于详情页的完整构造方法
  factory BangumiAnime.fromJson(Map<String, dynamic> json) {
    ////debugPrint('开始解析番剧数据');
    final String? imageUrl = json['images']?['large'];
    if (imageUrl == null || imageUrl.isEmpty) {
      throw Exception('Missing or empty image URL');
    }

    // 处理日期数据
    String? airDate = json['air_date'] as String?;
    if (airDate == null || airDate.isEmpty) {
      airDate = json['date'] as String?; // 尝试使用 date 字段作为备选
    }
    ////debugPrint('解析到的播放日期: $airDate');

    // 处理 infobox 数据
    String? originalWork;
    String? director;
    String? studio;
    if (json['infobox'] != null) {
      ////debugPrint('处理制作信息:');
      for (var item in json['infobox']) {
        if (item['key'] != null && item['value'] != null) {
          ////debugPrint('检查字段: ${item['key']} = ${item['value']}');
          switch (item['key']) {
            case '原作':
              originalWork = item['value'] as String;
              break;
            case '导演':
              director = item['value'] as String;
              break;
            case '动画制作':
            case '制作':
            case 'アニメーション制作':
              studio = item['value'] as String;
              break;
          }
        }
      }
      ////debugPrint('解析结果:');
      ////debugPrint('- 原作: $originalWork');
      ////debugPrint('- 导演: $director');
      ////debugPrint('- 制作公司: $studio');
    }

    // 处理标签数据
    List<String>? tags;
    if (json['tags'] != null) {
      tags = (json['tags'] as List)
          .map((tag) => tag['name'] as String)
          .toList();
    }

    final anime = BangumiAnime(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      nameCn: json['name_cn'] as String? ?? json['name'] as String? ?? '',
      imageUrl: imageUrl,
      summary: json['summary'] as String?,
      airDate: airDate,
      airWeekday: json['air_weekday'] as int?,
      rating: (json['rating']?['score'] as num?)?.toDouble(),
      tags: tags,
      staff: {},
      isNSFW: json['nsfw'] as bool?,
      isLocked: json['locked'] as bool?,
      platform: json['platform'] as String?,
      totalEpisodes: json['total_episodes'] as int?,
      originalWork: originalWork,
      director: director,
      studio: studio,
    );
    ////debugPrint('创建的番剧对象: ${anime.toJson()}');
    return anime;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'name_cn': nameCn,
      'imageUrl': imageUrl,
      'summary': summary,
      'air_date': airDate,
      'air_weekday': airWeekday,
      'rating': rating,
      'tags': tags,
      'staff': staff,
      'isNSFW': isNSFW,
      'isLocked': isLocked,
      'platform': platform,
      'totalEpisodes': totalEpisodes,
      'originalWork': originalWork,
      'director': director,
      'studio': studio,
    };
  }
} 