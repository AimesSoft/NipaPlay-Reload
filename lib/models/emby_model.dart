import 'package:nipaplay/models/watch_history_model.dart';

// Emby媒体库
class EmbyLibrary {
  final String id;
  final String name;
  final String? type;
  final String? imageTagsPrimary;
  final int? totalItems;
  
  EmbyLibrary({
    required this.id,
    required this.name,
    this.type,
    this.imageTagsPrimary,
    this.totalItems,
  });
  
  factory EmbyLibrary.fromJson(Map<String, dynamic> json) {
    return EmbyLibrary(
      id: json['ItemId'] ?? json['Id'],
      name: json['Name'],
      type: json['CollectionType'],
      imageTagsPrimary: json['ImageTags']?['Primary'],
      totalItems: json['ChildCount'],
    );
  }
}

// Emby媒体项目（电视剧、电影等）
class EmbyMediaItem {
  final String id;
  final String name;
  final String? overview;
  final String? originalTitle;
  final String? imagePrimaryTag;
  final String? imageBackdropTag;
  final int? productionYear;
  final DateTime dateAdded;
  final String? premiereDate;
  final String? communityRating;
  
  EmbyMediaItem({
    required this.id,
    required this.name,
    this.overview,
    this.originalTitle,
    this.imagePrimaryTag,
    this.imageBackdropTag,
    this.productionYear,
    required this.dateAdded,
    this.premiereDate,
    this.communityRating,
  });
  
  factory EmbyMediaItem.fromJson(Map<String, dynamic> json) {
    return EmbyMediaItem(
      id: json['Id'],
      name: json['Name'],
      overview: json['Overview'],
      originalTitle: json['OriginalTitle'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
      imageBackdropTag: json['BackdropImageTags']?.isNotEmpty == true ? json['BackdropImageTags'][0] : null,
      productionYear: json['ProductionYear'],
      dateAdded: DateTime.parse(json['DateCreated'] ?? DateTime.now().toIso8601String()),
      premiereDate: json['PremiereDate'],
      communityRating: json['CommunityRating']?.toString(),
    );
  }
  
  // 将EmbyMediaItem转换为WatchHistoryItem，用于与现有系统兼容
  WatchHistoryItem toWatchHistoryItem({int? lastPosition = 0, int? duration = 0}) {
    return WatchHistoryItem(
      filePath: 'emby://$id', // 使用emby://协议来区分
      animeName: name,
      episodeTitle: null,
      watchProgress: 0.0,
      lastPosition: lastPosition ?? 0,
      duration: duration ?? 0,
      lastWatchTime: DateTime.now(),
      animeId: null,
      isFromScan: false,
    );
  }
}

// Emby媒体详情（包含更多元数据）
class EmbyMediaItemDetail {
  final String id;
  final String name;
  final String? overview;
  final String? originalTitle;
  final String? imagePrimaryTag;
  final String? imageBackdropTag;
  final int? productionYear;
  final DateTime dateAdded;
  final String? premiereDate;
  final String? communityRating;
  final List<String> genres;
  final String? officialRating;
  final List<EmbyPerson> cast;
  final List<EmbyPerson> directors;
  final int? runTimeTicks;
  final String? seriesStudio;
  final String type; // 新增type字段
  
  EmbyMediaItemDetail({
    required this.id,
    required this.name,
    this.overview,
    this.originalTitle,
    this.imagePrimaryTag,
    this.imageBackdropTag,
    this.productionYear,
    required this.dateAdded,
    this.premiereDate,
    this.communityRating,
    required this.genres,
    this.officialRating,
    required this.cast,
    required this.directors,
    this.runTimeTicks,
    this.seriesStudio,
    required this.type, // 新增type字段
  });
  
  factory EmbyMediaItemDetail.fromJson(Map<String, dynamic> json) {
    // 解析类型信息
    List<String> genres = [];
    if (json['Genres'] != null) {
      genres = List<String>.from(json['Genres']);
    }
    
    // 解析演职员信息
    List<EmbyPerson> cast = [];
    List<EmbyPerson> directors = [];
    
    if (json['People'] != null) {
      for (var person in json['People']) {
        final embyPerson = EmbyPerson.fromJson(person);
        if (person['Type'] == 'Actor') {
          cast.add(embyPerson);
        } else if (person['Type'] == 'Director') {
          directors.add(embyPerson);
        }
      }
    }
    
    return EmbyMediaItemDetail(
      id: json['Id'],
      name: json['Name'],
      overview: json['Overview'],
      originalTitle: json['OriginalTitle'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
      imageBackdropTag: json['BackdropImageTags']?.isNotEmpty == true ? json['BackdropImageTags'][0] : null,
      productionYear: json['ProductionYear'],
      dateAdded: DateTime.parse(json['DateCreated'] ?? DateTime.now().toIso8601String()),
      premiereDate: json['PremiereDate'],
      communityRating: json['CommunityRating']?.toString(),
      genres: genres,
      officialRating: json['OfficialRating'],
      cast: cast,
      directors: directors,
      runTimeTicks: json['RunTimeTicks'],
      seriesStudio: json['Studios']?.isNotEmpty == true ? json['Studios'][0]['Name'] : null,
      type: json['Type'] ?? 'Unknown', // 新增type字段
    );
  }
}

// Emby剧集季节信息
class EmbySeasonInfo {
  final String id;
  final String name;
  final String? seriesId;
  final String? seriesName;
  final String? imagePrimaryTag;
  final int? indexNumber;
  
  EmbySeasonInfo({
    required this.id,
    required this.name,
    this.seriesId,
    this.seriesName,
    this.imagePrimaryTag,
    this.indexNumber,
  });
  
  factory EmbySeasonInfo.fromJson(Map<String, dynamic> json) {
    return EmbySeasonInfo(
      id: json['Id'],
      name: json['Name'],
      seriesId: json['SeriesId'],
      seriesName: json['SeriesName'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
      indexNumber: json['IndexNumber'],
    );
  }
}

// Emby剧集信息
class EmbyEpisodeInfo {
  final String id;
  final String name;
  final String? overview;
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final String? seasonName;
  final int? indexNumber;
  final int? parentIndexNumber;
  final String? imagePrimaryTag;
  final DateTime dateAdded;
  final String? premiereDate;
  final int? runTimeTicks;
  
  EmbyEpisodeInfo({
    required this.id,
    required this.name,
    this.overview,
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.seasonName,
    this.indexNumber,
    this.parentIndexNumber,
    this.imagePrimaryTag,
    required this.dateAdded,
    this.premiereDate,
    this.runTimeTicks,
  });
  
  factory EmbyEpisodeInfo.fromJson(Map<String, dynamic> json) {
    return EmbyEpisodeInfo(
      id: json['Id'],
      name: json['Name'] ?? '',
      overview: json['Overview'],
      seriesId: json['SeriesId'],
      seriesName: json['SeriesName'],
      seasonId: json['SeasonId'],
      seasonName: json['SeasonName'],
      indexNumber: json['IndexNumber'],
      parentIndexNumber: json['ParentIndexNumber'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
      dateAdded: DateTime.parse(json['DateCreated'] ?? DateTime.now().toIso8601String()),
      premiereDate: json['PremiereDate'],
      runTimeTicks: json['RunTimeTicks'],
    );
  }
  
  // 将EmbyEpisodeInfo转换为WatchHistoryItem，用于与现有系统兼容
  WatchHistoryItem toWatchHistoryItem({int? lastPosition = 0, int? duration = 0}) {
    String safeName = seriesName ?? '';
    if (safeName.isEmpty) safeName = "未知剧集";
    
    return WatchHistoryItem(
      filePath: 'emby://$id', // 使用emby://协议来区分本地文件，实际播放时需要替换为真实的流媒体URL
      animeName: safeName,
      episodeTitle: name.isNotEmpty ? name : '未知',
      watchProgress: 0.0,
      lastPosition: lastPosition ?? 0,
      duration: duration ?? 0,
      lastWatchTime: DateTime.now(),
      animeId: null, // 初始值为null，但会通过EmbyDandanplayMatcher更新
      episodeId: null, // 初始值为null，但会通过EmbyDandanplayMatcher更新
      isFromScan: false,
      videoHash: null, // 初始为null，计算哈希值后会更新
    );
  }
}

// Emby人员信息（演员、导演等）
class EmbyPerson {
  final String name;
  final String? role;
  final String? type;
  final String? id;
  final String? imagePrimaryTag;
  
  EmbyPerson({
    required this.name,
    this.role,
    this.type,
    this.id,
    this.imagePrimaryTag,
  });
  
  factory EmbyPerson.fromJson(Map<String, dynamic> json) {
    return EmbyPerson(
      name: json['Name'],
      role: json['Role'],
      type: json['Type'],
      id: json['Id'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
    );
  }
}

// Emby电影信息
class EmbyMovieInfo {
  final String id;
  final String name;
  final String? overview;
  final String? originalTitle;
  final String? imagePrimaryTag;
  final String? imageBackdropTag;
  final int? productionYear;
  final DateTime dateAdded;
  final String? premiereDate;
  final String? communityRating;
  final List<String> genres;
  final String? officialRating;
  final List<EmbyPerson> cast;
  final List<EmbyPerson> directors;
  final int? runTimeTicks;
  final String? studio;
  
  EmbyMovieInfo({
    required this.id,
    required this.name,
    this.overview,
    this.originalTitle,
    this.imagePrimaryTag,
    this.imageBackdropTag,
    this.productionYear,
    required this.dateAdded,
    this.premiereDate,
    this.communityRating,
    required this.genres,
    this.officialRating,
    required this.cast,
    required this.directors,
    this.runTimeTicks,
    this.studio,
  });
  
  factory EmbyMovieInfo.fromJson(Map<String, dynamic> json) {
    // 解析演员信息
    List<EmbyPerson> cast = [];
    if (json['People'] != null) {
      cast = (json['People'] as List)
          .where((person) => person['Type'] == 'Actor')
          .map((e) => EmbyPerson.fromJson(e))
          .toList();
    }
    
    // 解析导演信息
    List<EmbyPerson> directors = [];
    if (json['People'] != null) {
      directors = (json['People'] as List)
          .where((person) => person['Type'] == 'Director')
          .map((e) => EmbyPerson.fromJson(e))
          .toList();
    }
    
    // 解析流派
    List<String> genres = [];
    if (json['Genres'] != null) {
      genres = List<String>.from(json['Genres']);
    }
    
    return EmbyMovieInfo(
      id: json['Id'],
      name: json['Name'],
      overview: json['Overview'],
      originalTitle: json['OriginalTitle'],
      imagePrimaryTag: json['ImageTags']?['Primary'],
      imageBackdropTag: json['BackdropImageTags']?.isNotEmpty == true ? json['BackdropImageTags'][0] : null,
      productionYear: json['ProductionYear'],
      dateAdded: DateTime.parse(json['DateCreated'] ?? DateTime.now().toIso8601String()),
      premiereDate: json['PremiereDate'],
      communityRating: json['CommunityRating']?.toString(),
      genres: genres,
      officialRating: json['OfficialRating'],
      cast: cast,
      directors: directors,
      runTimeTicks: json['RunTimeTicks'],
      studio: json['Studios']?.isNotEmpty == true ? json['Studios'][0]['Name'] : null,
    );
  }
  
  // 将EmbyMovieInfo转换为WatchHistoryItem，用于与现有系统兼容
  WatchHistoryItem toWatchHistoryItem({int? lastPosition = 0, int? duration = 0}) {
    return WatchHistoryItem(
      filePath: 'emby://$id', // 使用emby://协议来区分本地文件
      animeName: name,
      episodeTitle: null, // 电影没有集标题
      watchProgress: 0.0,
      lastPosition: lastPosition ?? 0,
      duration: duration ?? 0,
      lastWatchTime: DateTime.now(),
      animeId: null, // 初始值为null，但会通过EmbyDandanplayMatcher更新
      episodeId: null, // 初始值为null，但会通过EmbyDandanplayMatcher更新
      isFromScan: false,
    );
  }
}
