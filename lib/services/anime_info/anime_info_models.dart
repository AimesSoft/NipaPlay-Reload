part of 'anime_info_service.dart';

class DandanplayFileMatchArgument {

  final String fileName;
  final String fileHash;
  final int    fileSize;

  DandanplayFileMatchArgument({
    required this.fileName,
    required this.fileHash,
    required this.fileSize,
  });
}

class DandanplayFileMatchResult {

  final int    dandanplayAnimeId;
  final int    dandanplayEpisodeId;
  final double danmakuOffset;

  DandanplayFileMatchResult({
    required this.dandanplayAnimeId,
    required this.dandanplayEpisodeId,
    required this.danmakuOffset,
  });
}

typedef _AnimeEpisodeDebugTitles = ({
  Map<int, String> dandanplayAnime,
  Map<int, String> bangumiAnime,
  Map<int, String> dandanplayEpisode,
  Map<int, String> bangumiEpisode,
});
