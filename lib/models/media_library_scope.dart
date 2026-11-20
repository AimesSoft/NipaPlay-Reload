import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/shared_remote_history_helper.dart';

enum MediaLibraryScopeKind {
  local,
  webdav,
  smb,
  sharedRemote,
  dandanplay,
  jellyfin,
  emby
}

/// The library used for this navigation, independent of a show's metadata or
/// the temporary playback URL. A null scope means all libraries.
class MediaLibraryScope {
  const MediaLibraryScope(this.kind, {this.hostOrigin});

  final MediaLibraryScopeKind kind;
  // Remote libraries are separated by host; WebDAV/SMB tabs aggregate connections.
  final String? hostOrigin;

  bool contains(WatchHistoryItem item) => containsPath(item.filePath);

  bool containsPath(String path) {
    final lower = path.toLowerCase();
    final dandanplay =
        lower.startsWith('dandanplay://') || lower.contains('/api/v1/stream/');
    final uri = Uri.tryParse(path);
    final shared = SharedRemoteHistoryHelper.isSharedRemoteStreamPath(path) ||
        uri?.path == '/api/media/local/manage/stream';
    final webdav = !shared && MediaSourceUtils.isWebDavPath(path);
    final smb = !shared && MediaSourceUtils.isSmbPath(path);
    return switch (kind) {
      MediaLibraryScopeKind.webdav => webdav && !dandanplay,
      MediaLibraryScopeKind.smb => smb && !dandanplay,
      MediaLibraryScopeKind.sharedRemote => shared && _sameHost(uri),
      MediaLibraryScopeKind.dandanplay => dandanplay && _sameHost(uri),
      MediaLibraryScopeKind.jellyfin => lower.startsWith('jellyfin://'),
      MediaLibraryScopeKind.emby => lower.startsWith('emby://'),
      MediaLibraryScopeKind.local => !shared &&
          !webdav &&
          !smb &&
          !dandanplay &&
          (uri == null ||
              uri.scheme.isEmpty ||
              uri.scheme == 'file' ||
              uri.scheme == 'content' ||
              RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)),
    };
  }

  bool _sameHost(Uri? uri) {
    if (hostOrigin == null) return true;
    final host = Uri.tryParse(hostOrigin!);
    if (uri == null || host == null) return false;
    return uri.scheme == host.scheme &&
        uri.host == host.host &&
        uri.port == host.port;
  }
}
