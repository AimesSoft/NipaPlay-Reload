import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:nipaplay/models/media_identity.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';

class MediaIdentityResolver {
  const MediaIdentityResolver._();

  static String forPath(String videoPath) {
    final webDav = WebDAVService.instance.resolveMediaPath(videoPath);
    if (webDav != null) {
      return MediaIdentity.remotePathKey(
        source: 'webdav',
        connectionId: webDav.connection.id,
        rawPath: webDav.relativePath,
      );
    }
    final unresolvedWebDav = MediaSourceUtils.parseWebDavPath(videoPath);
    if (unresolvedWebDav != null) {
      return MediaIdentity.remotePathKey(
        source: 'webdav',
        connectionId: unresolvedWebDav.connectionName,
        rawPath: unresolvedWebDav.relativePath,
      );
    }

    final smb = MediaSourceUtils.parseSmbMediaPath(videoPath);
    if (smb != null) {
      final connection =
          SMBService.instance.getConnectionByIdOrName(smb.connectionName);
      return MediaIdentity.remotePathKey(
        source: 'smb',
        connectionId: connection?.id ?? smb.connectionName,
        rawPath: smb.relativePath,
        normalizeBackslashes: true,
      );
    }

    if (videoPath.startsWith('jellyfin://')) {
      return MediaIdentity.object(
        source: 'jellyfin',
        sourceId: 'default',
        objectId: videoPath.substring('jellyfin://'.length),
      );
    }
    if (videoPath.startsWith('emby://')) {
      return MediaIdentity.object(
        source: 'emby',
        sourceId: 'default',
        objectId: videoPath.substring('emby://'.length),
      );
    }

    final uri = Uri.tryParse(videoPath);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final queryParts =
          uri.query.isEmpty ? const <String>[] : (uri.query.split('&')..sort());
      final objectId =
          queryParts.isEmpty ? uri.path : '${uri.path}?${queryParts.join('&')}';
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      return MediaIdentity.object(
        source: 'network',
        sourceId: '${uri.scheme}://${uri.host}:$port',
        objectId: objectId,
      );
    }

    var localPath = p.normalize(videoPath);
    if (defaultTargetPlatform == TargetPlatform.windows) {
      localPath = localPath.toLowerCase();
    }
    return MediaIdentity.object(
      source: 'local',
      sourceId: 'filesystem',
      objectId: localPath,
    );
  }

  static bool samePath(String a, String b) => forPath(a) == forPath(b);
}
