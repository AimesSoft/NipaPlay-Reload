import 'dart:convert';

class DandanplayRemoteEpisode {
  const DandanplayRemoteEpisode({
    required this.animeId,
    required this.episodeId,
    required this.animeTitle,
    required this.episodeTitle,
    required this.entryId,
    required this.hash,
    required this.name,
    required this.path,
    required this.size,
    required this.isStandalone,
    required this.created,
    required this.lastMatch,
    required this.lastPlay,
    required this.lastThumbnail,
    required this.duration,
  });

  final int? animeId;
  final int? episodeId;
  final String animeTitle;
  final String episodeTitle;
  final String entryId;
  final String hash;
  final String name;
  final String path;
  final int size;
  final bool isStandalone;
  final DateTime? created;
  final DateTime? lastMatch;
  final DateTime? lastPlay;
  final DateTime? lastThumbnail;
  final int? duration;

  bool get hasHash => hash.isNotEmpty;

  factory DandanplayRemoteEpisode.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is String &&
          value.isNotEmpty &&
          value != '0001-01-01T00:00:00') {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return DandanplayRemoteEpisode(
      animeId: (json['AnimeId'] ?? json['animeId']) as int?,
      episodeId: (json['EpisodeId'] ?? json['episodeId']) as int?,
      animeTitle:
          (json['AnimeTitle'] ?? json['animeTitle'] ?? '未知番剧') as String,
      episodeTitle:
          (json['EpisodeTitle'] ?? json['episodeTitle'] ?? '未知剧集') as String,
      entryId: (json['Id'] ?? json['id'] ?? '') as String,
      hash: (json['Hash'] ?? json['hash'] ?? '') as String,
      name: (json['Name'] ?? json['name'] ?? '') as String,
      path: (json['Path'] ?? json['path'] ?? '') as String,
      size: (json['Size'] ?? json['size'] ?? 0) as int,
      isStandalone:
          (json['IsStandalone'] ?? json['isStandalone'] ?? false) as bool,
      created: parseDate(json['Created'] ?? json['created']),
      lastMatch: parseDate(json['LastMatch'] ?? json['lastMatch']),
      lastPlay: parseDate(json['LastPlay'] ?? json['lastPlay']),
      lastThumbnail: parseDate(json['LastThumbnail'] ?? json['lastThumbnail']),
      duration: (json['Duration'] ?? json['duration']) as int?,
    );
  }

  Map<String, dynamic> toJson() {
    DateTime? normalize(DateTime? value) => value;
    return {
      'animeId': animeId,
      'episodeId': episodeId,
      'animeTitle': animeTitle,
      'episodeTitle': episodeTitle,
      'entryId': entryId,
      'hash': hash,
      'name': name,
      'path': path,
      'size': size,
      'isStandalone': isStandalone,
      'created': normalize(created)?.toIso8601String(),
      'lastMatch': normalize(lastMatch)?.toIso8601String(),
      'lastPlay': normalize(lastPlay)?.toIso8601String(),
      'lastThumbnail': normalize(lastThumbnail)?.toIso8601String(),
      'duration': duration,
    };
  }

  static List<DandanplayRemoteEpisode> listFromJson(String payload) {
    final List<dynamic> decoded = json.decode(payload) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DandanplayRemoteEpisode.fromJson)
        .toList();
  }
}

class DandanplayRemoteAnimeGroup {
  DandanplayRemoteAnimeGroup({
    required this.animeId,
    required this.title,
    required this.episodes,
    required this.latestPlayTime,
  });

  final int? animeId;
  final String title;
  final List<DandanplayRemoteEpisode> episodes;
  final DateTime? latestPlayTime;

  int get episodeCount => episodes.length;
  DandanplayRemoteEpisode get firstEpisode => episodes.first;
  DandanplayRemoteEpisode get latestEpisode => episodes.last;
  String? get primaryHash {
    for (final episode in episodes) {
      if (episode.hasHash) {
        return episode.hash;
      }
    }
    return null;
  }
}
