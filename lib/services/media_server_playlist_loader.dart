/// 获取当前媒体的播放列表。电影和没有季信息的独立视频保留为单项列表。
Future<List<T>> loadMediaServerPlaylist<T>({
  required T currentItem,
  required String? seriesId,
  required String? seasonId,
  required Future<List<T>> Function(String seriesId, String seasonId)
      loadSeason,
}) async {
  if (seriesId == null ||
      seriesId.isEmpty ||
      seasonId == null ||
      seasonId.isEmpty) {
    return [currentItem];
  }
  return loadSeason(seriesId, seasonId);
}
