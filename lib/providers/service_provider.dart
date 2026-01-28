import 'package:flutter/foundation.dart';
import 'package:nipaplay/services/server_history_sync_service.dart';
import 'package:nipaplay/services/web_server_service.dart';
import 'package:nipaplay/services/scan_service.dart';

import 'dandanplay_remote_provider.dart';
import 'emby_provider.dart';
import 'jellyfin_provider.dart';
import 'watch_history_provider.dart';

class ServiceProvider {
  ServiceProvider._();

  static final WebServerService webServer = WebServerService();
  static final JellyfinProvider jellyfinProvider = JellyfinProvider();
  static final EmbyProvider embyProvider = EmbyProvider();
  static final DandanplayRemoteProvider dandanplayRemoteProvider =
      DandanplayRemoteProvider();
  static final WatchHistoryProvider watchHistoryProvider =
      WatchHistoryProvider();
  static final ScanService scanService = ScanService();
  static final ServerHistorySyncService serverHistorySyncService =
      ServerHistorySyncService.instance;

  static Future<void> initialize() async {
    // 可以在这里添加服务的初始化逻辑
    // 并行初始化网络媒体库服务，不等待连接验证完成
    await Future.wait([
      jellyfinProvider.initialize(),
      embyProvider.initialize(),
      dandanplayRemoteProvider.initialize(),
    ]);

    // 本地观看历史需要同步等待加载完成
    await watchHistoryProvider.loadHistory();
    // 让 WatchHistoryProvider 能响应扫描完成（包括来自远程 API 的扫描请求）
    watchHistoryProvider.setScanService(scanService);

    // 初始化服务器观看历史同步（当前仅支持 Jellyfin 下行同步）
    serverHistorySyncService.initialize(
      onHistoryUpdated: () => watchHistoryProvider.refresh(),
    );

    // 远程访问服务：若用户开启了“软件启动自动开启”，则在此启动服务
    try {
      await webServer.loadSettings();
    } catch (e) {
      debugPrint('ServiceProvider: WebServer 初始化失败: $e');
    }
  }
}
