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
    final stored = prefs.getString(_dandanplayServerKey) ?? defaultServer;
    return _normalizeServerUrl(stored);
  }

  /// 设置弹弹play服务器地址
  static Future<void> setDandanplayServer(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeServerUrl(serverUrl);
    await prefs.setString(_dandanplayServerKey, normalized);
    print('[网络设置] 弹弹play服务器已切换到: $normalized');
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

  /// 检查当前服务器是否为自定义服务器
  static bool isCustomServer(String serverUrl) {
    if (serverUrl.trim().isEmpty) {
      return false;
    }
    final normalized = _normalizeServerUrl(serverUrl);
    return normalized != primaryServer && normalized != backupServer;
  }

  /// 粗略校验用户输入的服务器地址
  static bool isValidServerUrl(String serverUrl) {
    final normalized = _normalizeServerUrl(serverUrl);
    final uri = Uri.tryParse(normalized);
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
  }

  static String _normalizeServerUrl(String serverUrl) {
    var url = serverUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
