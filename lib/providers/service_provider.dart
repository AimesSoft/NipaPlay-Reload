import 'package:nipaplay/services/web_server_service.dart';
import 'jellyfin_provider.dart';
import 'emby_provider.dart';
import 'watch_history_provider.dart';

class ServiceProvider {
  ServiceProvider._();

  static final WebServerService webServer = WebServerService();
  static final JellyfinProvider jellyfinProvider = JellyfinProvider();
  static final EmbyProvider embyProvider = EmbyProvider();
  static final WatchHistoryProvider watchHistoryProvider = WatchHistoryProvider();


  static Future<void> initialize() async {
    // 可以在这里添加服务的初始化逻辑
    // 并行初始化网络媒体库服务，不等待连接验证完成
    await Future.wait([
      jellyfinProvider.initialize(),
      embyProvider.initialize(),
    ]);
    
    // 本地观看历史需要同步等待加载完成
    await watchHistoryProvider.loadHistory();
    
    print('ServiceProvider: 所有服务初始化完成，连接验证将在后台异步进行');
  }
} 