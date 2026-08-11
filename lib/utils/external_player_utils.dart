
// lib/utils/external_player_utils.dart
// 外部播放器相关工具函数

import 'package:flutter/widgets.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
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
Future<String?> resolveExternalPlayerMediaPath(PlayableItem item) async {
  final sessionUrl = item.playbackSession?.streamUrl;
  String finalPath;
  if (sessionUrl != null && sessionUrl.trim().isNotEmpty) {
    finalPath = sessionUrl;
  } else if (item.actualPlayUrl != null &&
      item.actualPlayUrl!.trim().isNotEmpty) {
    finalPath = item.actualPlayUrl!.trim();
  } else {
    finalPath = item.videoPath;
  }

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

/// 安全显示 snackbar.
///
/// 服务层拿到的 context 可能缺少 Overlay 祖先（如 Navigator 自己的 context,
/// 其 Overlay 在 Navigator 内部而非祖先）, 此时 [BlurSnackBar.show] 会抛
/// "No Overlay widget found". 这里吞掉异常, 避免阻断播放器启动主流程——
/// snackbar 只是提示, 启动逻辑必须继续.
void safeShowSnack(BuildContext context, String msg, {void Function(String)? log}) {
  try {
    if (!context.mounted) return;
    BlurSnackBar.show(context, msg);
  } catch (e) {
    log?.call('tryHandlePlayback: snackbar 显示失败(忽略): $e');
  }
}

/// 按 [path] 最后一段文件名推断外部播放器类型.
///
/// 匹配不区分大小写, 并同时接受 `/` 与 `\\` 路径分隔符. mpv.net 会先于
/// mpv 匹配; 无法识别时返回 [ExternalPlayerType.generic]. 此判断只用于选择
/// 命令行参数, 不会读取或启动目标文件.
ExternalPlayerType detectExternalPlayerType(String path) {
  final lower = path.toLowerCase();
  final base = lower.split(RegExp(r'[\\/]')).last;
  if (base.contains('mpvnet') || base.contains('mpv.net')) {
    return ExternalPlayerType.mpvNet;
  }
  if (base.contains('mpv')) return ExternalPlayerType.mpv;
  if (base.contains('potplayer')) return ExternalPlayerType.potPlayer;
  if (base.contains('vlc')) return ExternalPlayerType.vlc;
  return ExternalPlayerType.generic;
}
