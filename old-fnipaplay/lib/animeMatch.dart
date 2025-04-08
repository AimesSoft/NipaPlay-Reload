
// ignore_for_file: file_names

class AnimeMatch {
  int? episodeId;
  int? animeId;
  String? animeTitle;
  String? episodeTitle;

  AnimeMatch(
      {this.episodeId, this.animeId, this.animeTitle, this.episodeTitle});
}

// 全局变量
AnimeMatch anime = AnimeMatch();