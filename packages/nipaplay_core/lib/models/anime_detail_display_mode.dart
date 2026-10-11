enum AnimeDetailDisplayMode { simple, vivid }

extension AnimeDetailDisplayModeStorage on AnimeDetailDisplayMode {
  String get storageKey => this == AnimeDetailDisplayMode.vivid ? 'vivid' : 'simple';

  static AnimeDetailDisplayMode fromString(String? value) {
    if (value == 'vivid') {
      return AnimeDetailDisplayMode.vivid;
    }
    return AnimeDetailDisplayMode.simple;
  }
}
