import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/media_source_utils.dart';

enum UnifiedMediaLibraryContentType {
  mediaCollection,
  libraryManagement,
  sharedCollection,
  sharedManagement,
  dandanplay,
  networkServer,
}

enum UnifiedMediaLibrarySource {
  local,
  webdav,
  smb,
}

enum UnifiedMediaLibraryServer {
  jellyfin,
  emby,
}

class UnifiedMediaLibrarySection {
  const UnifiedMediaLibrarySection({
    required this.id,
    required this.label,
    required this.phoneSymbol,
    required this.contentType,
    this.source,
    this.server,
  });

  final String id;
  final String label;
  final String phoneSymbol;
  final UnifiedMediaLibraryContentType contentType;
  final UnifiedMediaLibrarySource? source;
  final UnifiedMediaLibraryServer? server;
}

class MediaLibraryAvailability {
  const MediaLibraryAvailability({
    required this.showLocal,
    required this.showWebDAVLibrary,
    required this.showWebDAVManagement,
    required this.showSMBLibrary,
    required this.showSMBManagement,
    required this.showShared,
    required this.showDandanplay,
    required this.showJellyfin,
    required this.showEmby,
  });

  final bool showLocal;
  final bool showWebDAVLibrary;
  final bool showWebDAVManagement;
  final bool showSMBLibrary;
  final bool showSMBManagement;
  final bool showShared;
  final bool showDandanplay;
  final bool showJellyfin;
  final bool showEmby;
}

List<UnifiedMediaLibrarySection> buildUnifiedMediaLibrarySections(
  MediaLibraryAvailability availability,
) {
  return <UnifiedMediaLibrarySection>[
    if (availability.showLocal) ...[
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.local,
        label: '本地媒体库',
        phoneSymbol: 'rectangle.stack',
        contentType: UnifiedMediaLibraryContentType.mediaCollection,
        source: UnifiedMediaLibrarySource.local,
      ),
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.localManagement,
        label: '本地库管理',
        phoneSymbol: 'folder',
        contentType: UnifiedMediaLibraryContentType.libraryManagement,
        source: UnifiedMediaLibrarySource.local,
      ),
    ],
    if (availability.showWebDAVLibrary)
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.webdav,
        label: 'WebDAV媒体库',
        phoneSymbol: 'cloud',
        contentType: UnifiedMediaLibraryContentType.mediaCollection,
        source: UnifiedMediaLibrarySource.webdav,
      ),
    if (availability.showWebDAVManagement)
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.webdavManagement,
        label: 'WebDAV库管理',
        phoneSymbol: 'cloud.fill',
        contentType: UnifiedMediaLibraryContentType.libraryManagement,
        source: UnifiedMediaLibrarySource.webdav,
      ),
    if (availability.showSMBLibrary)
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.smb,
        label: 'SMB媒体库',
        phoneSymbol: 'externaldrive.connected.to.line.below',
        contentType: UnifiedMediaLibraryContentType.mediaCollection,
        source: UnifiedMediaLibrarySource.smb,
      ),
    if (availability.showSMBManagement)
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.smbManagement,
        label: 'SMB库管理',
        phoneSymbol: 'externaldrive.fill',
        contentType: UnifiedMediaLibraryContentType.libraryManagement,
        source: UnifiedMediaLibrarySource.smb,
      ),
    if (availability.showShared) ...[
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.shared,
        label: '共享媒体库',
        phoneSymbol: 'rectangle.stack.badge.person.crop',
        contentType: UnifiedMediaLibraryContentType.sharedCollection,
      ),
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.sharedManagement,
        label: '共享库管理',
        phoneSymbol: 'person.2.badge.gearshape',
        contentType: UnifiedMediaLibraryContentType.sharedManagement,
      ),
    ],
    if (availability.showDandanplay)
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.dandanplay,
        label: '弹弹play',
        phoneSymbol: 'play.tv',
        contentType: UnifiedMediaLibraryContentType.dandanplay,
      ),
    if (availability.showJellyfin)
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.jellyfin,
        label: 'Jellyfin',
        phoneSymbol: 'play.tv.fill',
        contentType: UnifiedMediaLibraryContentType.networkServer,
        server: UnifiedMediaLibraryServer.jellyfin,
      ),
    if (availability.showEmby)
      const UnifiedMediaLibrarySection(
        id: MediaLibrarySectionIds.emby,
        label: 'Emby',
        phoneSymbol: 'tv.fill',
        contentType: UnifiedMediaLibraryContentType.networkServer,
        server: UnifiedMediaLibraryServer.emby,
      ),
  ];
}

bool mediaLibraryItemMatchesSource(
  WatchHistoryItem item,
  UnifiedMediaLibrarySource source,
) {
  if (item.animeId == null || item.isDandanplayRemote) return false;

  final path = item.filePath;
  final isWebDAV = MediaSourceUtils.isWebDavPath(path);
  final isSMB = MediaSourceUtils.isSmbPath(path);

  return switch (source) {
    UnifiedMediaLibrarySource.webdav => isWebDAV,
    UnifiedMediaLibrarySource.smb => isSMB,
    UnifiedMediaLibrarySource.local => !path.startsWith('jellyfin://') &&
        !path.startsWith('emby://') &&
        !isWebDAV &&
        !isSMB &&
        !path.contains('/api/media/local/share/'),
  };
}

bool mediaLibraryHasItemsForSource(
  Iterable<WatchHistoryItem> history,
  UnifiedMediaLibrarySource source,
) {
  return history.any((item) => mediaLibraryItemMatchesSource(item, source));
}

List<WatchHistoryItem> mediaLibraryLatestItemsByAnime(
  Iterable<WatchHistoryItem> history,
  UnifiedMediaLibrarySource source,
) {
  final latestByAnime = <int, WatchHistoryItem>{};
  for (final item in history) {
    if (!mediaLibraryItemMatchesSource(item, source)) continue;
    final animeId = item.animeId!;
    final previous = latestByAnime[animeId];
    if (previous == null ||
        item.lastWatchTime.isAfter(previous.lastWatchTime)) {
      latestByAnime[animeId] = item;
    }
  }

  return latestByAnime.values.toList()
    ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
}

int mediaLibrarySectionIndexById(
  List<UnifiedMediaLibrarySection> sections,
  String? sectionId,
) {
  if (sectionId == null) return -1;
  return sections.indexWhere((section) => section.id == sectionId);
}
