import 'package:shared_preferences/shared_preferences.dart';

/// 网络设置管理类
class NetworkSettings {
  static const String _dandanplayServerKey = 'dandanplay_server_url';
  
  // 服务器常量
  static const String primaryServer = 'https://api.dandanplay.net';
  static const String backupServer = 'http://139.217.235.62:16001';
  
  // 默认服务器（主服务器）
  static const String defaultServer = primaryServer;

  /// 获取当前弹弹play服务器地址
  static Future<String> getDandanplayServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dandanplayServerKey) ?? defaultServer;
  }

  /// 设置弹弹play服务器地址
  static Future<void> setDandanplayServer(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dandanplayServerKey, serverUrl);
    print('[网络设置] 弹弹play服务器已切换到: $serverUrl');
  }

  /// 重置为默认服务器
  static Future<void> resetToDefaultServer() async {
    await setDandanplayServer(defaultServer);
  }

  /// 检查是否使用备用服务器
  static Future<bool> isUsingBackupServer() async {
    final currentServer = await getDandanplayServer();
    return currentServer == backupServer;
  }

  /// 获取所有可用服务器列表
  static List<Map<String, String>> getAvailableServers() {
    return [
      {
        'name': '主服务器',
        'url': primaryServer,
        'description': 'api.dandanplay.net（官方服务器）',
      },
      {
        'name': '备用服务器', 
        'url': backupServer,
        'description': '139.217.235.62:16001（镜像服务器）',
      },
    ];
  }
}