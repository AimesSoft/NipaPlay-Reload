import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/media_identity_resolver.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/shared_remote_history_helper.dart';

class EpisodeFileCandidate {
  const EpisodeFileCandidate(this.history);

  final WatchHistoryItem history;
  String get identity => MediaIdentityResolver.forPath(history.filePath);

  String get sourceLabel {
    final path = history.filePath;
    if (MediaSourceUtils.isSmbPath(path)) return 'SMB';
    if (MediaSourceUtils.isWebDavPath(path)) return 'WebDAV';
    if (path.startsWith('jellyfin://')) return 'Jellyfin';
    if (path.startsWith('emby://')) return 'Emby';
    if (history.isDandanplayRemote) return '弹弹play远程媒体库';
    if (SharedRemoteHistoryHelper.isSharedRemoteStreamPath(path) ||
        (Uri.tryParse(path)?.path.endsWith('/api/media/local/manage/stream') ??
            false)) {
      return '共享媒体库';
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return '网络媒体';
    }
    return '本地媒体库';
  }

  /// Presentation only: never use this decoded text as a playback URL or key.
  String get displayPath {
    final path = history.filePath;
    final webDav = MediaSourceUtils.parseWebDavPath(path);
    if (webDav != null) {
      final name =
          WebDAVService.instance.resolveMediaPath(path)?.connection.name ??
              webDav.connectionName;
      return 'webdav://$name${_decode(webDav.relativePath)}';
    }
    final smb = MediaSourceUtils.parseSmbMediaPath(path);
    if (smb != null) {
      final name = SMBService.instance
              .getConnectionByIdOrName(smb.connectionName)
              ?.name ??
          smb.connectionName;
      // Proxy query parameters are already decoded by Uri.queryParameters.
      final relative = MediaSourceUtils.isNewSmbPath(path)
          ? _decode(smb.relativePath)
          : smb.relativePath;
      return 'smb://$name$relative';
    }
    final uri = Uri.tryParse(path);
    if (uri != null &&
        const {'http', 'https', 'dav', 'file', 'jellyfin', 'emby', 'dandanplay'}
            .contains(uri.scheme.toLowerCase())) {
      return _decode(uri.replace(userInfo: '').toString());
    }
    return path;
  }

  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    } on FormatException {
      return value;
    }
  }

  PlayableItem toPlayable(PlayableItem requested) {
    final sameFile =
        MediaIdentityResolver.samePath(history.filePath, requested.videoPath);
    return PlayableItem(
      videoPath: history.filePath,
      title: history.animeName,
      subtitle: history.episodeTitle,
      animeId: history.animeId,
      episodeId: history.episodeId,
      historyItem: history,
      mediaKey: history.mediaKey ?? identity,
      actualPlayUrl: sameFile ? requested.actualPlayUrl : null,
      playbackSession: sameFile ? requested.playbackSession : null,
      detailContext: sameFile ? requested.detailContext : null,
    );
  }
}
