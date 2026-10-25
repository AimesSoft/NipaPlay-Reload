import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'package:nipaplay/services/server_history_sync_service.dart';
import 'package:nipaplay/services/web_server_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay_core/services/remote_control_settings.dart';

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

  static Future<void> initialize({bool deferBackground = false}) async {
    // 网络媒体库 provider 的连接验证全部转为后台：启动路径只保留本地偏好
    // 读取。首页对未加载完成的 provider 已有 loading 态。
    unawaited(Future.wait([
      jellyfinProvider.initialize(),
      embyProvider.initialize(),
      dandanplayRemoteProvider.initialize(),
    ]).then((_) {
      // 服务器观看历史同步（当前仅支持 Jellyfin 下行同步）
      serverHistorySyncService.initialize(
        onHistoryUpdated: () => watchHistoryProvider.refresh(),
      );
    }));

    // 本地观看历史延后到首帧后加载：上游 deferBackground/initializeAfterFirstFrame
    // 机制已承接这一意图（历史加载含逐条文件存在性 stat，历史多时占用数百毫秒，
    // 延后避免阻塞首帧）；主入口在首帧后调用 initializeAfterFirstFrame()。
    watchHistoryProvider.setScanService(scanService);
    if (!deferBackground) await initializeAfterFirstFrame();
  }

  static Future<void>? _backgroundInitialization;
  static Future<void> initializeAfterFirstFrame() =>
      _backgroundInitialization ??= _initializeBackground();

  static Future<void> _initializeBackground() async {
    await watchHistoryProvider.loadHistory();

    // 远程访问服务：若用户开启了“软件启动自动开启”，则在此启动服务。
    // 绑定 HTTP 端口不需要发生在首帧之前。
    try {
      await webServer.loadSettings();
      if (!kIsWeb) {
        final receiverEnabled = await RemoteControlSettings.isReceiverEnabled();
        if (receiverEnabled && !webServer.isRunning) {
          final started = await webServer.startServer();
          if (!started) {
            debugPrint(
              'ServiceProvider: 遥控接收端启动失败: ${webServer.lastStartErrorMessage ?? 'unknown'}',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('ServiceProvider: WebServer 初始化失败: $e');
    }
  }
}
