import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';

/// 解析应交给外部播放器的媒体地址.
///
/// 地址按以下优先级选择:
///
/// 1. [playbackSession] 中非空的流地址;
/// 2. 非空的 [actualPlayUrl];
/// 3. 原始 [videoPath].
///
/// 新格式 WebDAV/SMB 持久化路径会在返回前转换为播放器能够访问的 HTTP URL.
/// 找不到连接或 SMB 本地代理启动失败时返回 `null`.
Future<String?> resolveExternalPlayerMediaPath({
  required String videoPath,
  String? actualPlayUrl,
  PlaybackSession? playbackSession,
}) async {
  final sessionUrl = playbackSession?.streamUrl;
  String finalPath;
  if      (sessionUrl != null && sessionUrl.trim().isNotEmpty)       { finalPath = sessionUrl; }
  else if (actualPlayUrl != null && actualPlayUrl.trim().isNotEmpty) { finalPath = actualPlayUrl; }
  else                                                               { finalPath = videoPath; }

  if (MediaSourceUtils.isNewWebDavPath(finalPath)) {
    await WebDAVService.instance.initialize();
    return MediaSourceUtils.resolveWebDavPathToUrl(finalPath);
  }
  if (MediaSourceUtils.isNewSmbPath(finalPath)) {
    await SMBProxyService.instance.initialize();
    if (!SMBProxyService.instance.isRunning) return null;
    return MediaSourceUtils.resolveSmbPathToUrl(finalPath);
  }
  return finalPath;
}
