enum AppPageComponentType {
  homeFeed,
  playback,
  webdavBrowser,
  mediaLibrary,
  torrentTasks,
  account,
}

class AppPageComponent {
  const AppPageComponent({
    required this.id,
    required this.type,
  });

  final String id;
  final AppPageComponentType type;
}
