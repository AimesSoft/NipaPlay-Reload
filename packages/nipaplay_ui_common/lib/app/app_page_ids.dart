class AppPageIds {
  const AppPageIds._();

  static const String home = 'home';
  static const String video = 'video';
  static const String webdav = 'webdav';
  static const String mediaLibrary = 'media_library';
  static const String torrent = 'torrent';
  static const String account = 'account';
  static const String externalPlayerConsole = 'external_player_console';
  static const String settings = 'settings';

  static const List<String> primaryOrder = <String>[
    home,
    video,
    webdav,
    mediaLibrary,
    torrent,
    account,
    externalPlayerConsole,
  ];

  // Compatibility order used by callers that still send historical indices.
  static const List<String> legacyOrder = <String>[
    home,
    video,
    mediaLibrary,
    torrent,
    account,
  ];

  static String? fromLegacyIndex(int index) {
    if (index < 0 || index >= legacyOrder.length) {
      return null;
    }
    return legacyOrder[index];
  }
}

class AppActionIds {
  const AppActionIds._();

  static const String toggleTheme = 'toggle_theme';
  static const String settings = 'settings';
}

class MediaLibrarySectionIds {
  const MediaLibrarySectionIds._();

  static const String local = 'local_library';
  static const String localManagement = 'local_management';
  static const String webdav = 'webdav_library';
  static const String webdavManagement = 'webdav_management';
  static const String smb = 'smb_library';
  static const String smbManagement = 'smb_management';
  static const String shared = 'shared_library';
  static const String sharedManagement = 'shared_management';
  static const String dandanplay = 'dandanplay';
  static const String jellyfin = 'jellyfin';
  static const String emby = 'emby';
}
