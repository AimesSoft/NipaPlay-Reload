/// All acquisition paths register into the player's existing maps.
void registerDanmakuSourceTrack(
    Map<String, Map<String, dynamic>> tracks,
    Map<String, bool> enabled,
    String id,
    Map<String, dynamic> track,
    bool isEnabled) {
  final platform = track['platform'] ?? 'unknown';
  final videoId = track['platformVideoId'];
  final duplicates = tracks.entries
      .where((entry) {
        if (entry.key == id) return false;
        final existing = entry.value;
        final otherPlatform = existing['platform'] ?? existing['source'];
        return platform == 'dandanplay' && otherPlatform == 'dandanplay' ||
            platform != 'unknown' &&
                videoId != null &&
                platform == otherPlatform &&
                videoId == existing['platformVideoId'];
      })
      .map((entry) => entry.key)
      .toList();
  for (final duplicate in duplicates) {
    tracks.remove(duplicate);
    enabled.remove(duplicate);
  }
  tracks[id] = track;
  enabled[id] = isEnabled;
}
