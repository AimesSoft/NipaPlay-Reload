import '../services/web_server_service.dart';
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
    await jellyfinProvider.initialize();
    await embyProvider.initialize();
    await watchHistoryProvider.loadHistory();
  }
} 