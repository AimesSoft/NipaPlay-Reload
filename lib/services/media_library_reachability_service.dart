import 'package:flutter/foundation.dart';

import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';

/// 应用启动阶段的后台媒体库可达性检测。
///
/// 遍历已配置的 WebDAV / SMB 连接，分别探测其内网与公网地址：
/// - 只配置一个地址时只检测该地址；
/// - 两个都配置时都检测；
/// - 两个都可达则优先使用内网地址，仅一个可达则使用可达的那个；
/// - 都不可达则保留内网为默认。
///
/// 使用与管理页手动检测相同的状态更新流程，同时保存连接状态与优选地址。
/// 每个连接探测结束后会 [notifyListeners]，库管理界面据此刷新地址行
/// 的连通性状态，避免页面在检测完成前打开时一直停留在「未知」。
class MediaLibraryReachabilityService extends ChangeNotifier {
  MediaLibraryReachabilityService._({WebDAVService? webdav, SMBService? smb})
      : _webdav = webdav ?? WebDAVService.instance,
        _smb = smb ?? SMBService.instance;

  @visibleForTesting
  MediaLibraryReachabilityService.forTesting({
    required WebDAVService webdav,
    required SMBService smb,
  }) : this._(webdav: webdav, smb: smb);

  final WebDAVService _webdav;
  final SMBService _smb;

  static final MediaLibraryReachabilityService instance =
      MediaLibraryReachabilityService._();

  bool _isChecking = false;

  bool get isChecking => _isChecking;

  Future<void> checkAll() async {
    if (kIsWeb || _isChecking) return;
    _isChecking = true;
    try {
      await _webdav.initialize();
      await _smb.initialize();

      final webdavConnections =
          List<WebDAVConnection>.from(_webdav.connections);
      final smbConnections = List<SMBConnection>.from(_smb.connections);

      await Future.wait([
        for (final connection in webdavConnections) _checkWebDav(connection),
        for (final connection in smbConnections) _checkSmb(connection),
      ]);
    } catch (e) {
      debugPrint('媒体库可达性检测失败: $e');
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<void> _checkWebDav(WebDAVConnection connection) async {
    try {
      await _webdav.updateConnectionStatus(connection.name);
    } catch (e) {
      debugPrint('WebDAV 可达性检测失败 (${connection.name}): $e');
    } finally {
      notifyListeners();
    }
  }

  Future<void> _checkSmb(SMBConnection connection) async {
    try {
      await _smb.updateConnectionStatus(connection.name);
    } catch (e) {
      debugPrint('SMB 可达性检测失败 (${connection.name}): $e');
    } finally {
      notifyListeners();
    }
  }
}
