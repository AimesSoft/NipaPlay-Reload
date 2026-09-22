import 'package:shared_preferences/shared_preferences.dart';

/// 弹弹play 网关服务器选择模式。
///
/// - [auto]：按用户网络环境（IP 归属地 + 可达性）自动挑选主/备用服务器；
/// - [hongKong]：固定使用香港主服务器（域名）；
/// - [china]：固定使用国内备用服务器（IP，免域名/免备案）；
/// - [custom]：用户自填的第三方兼容弹弹play API 的服务器。
enum DandanplayServerMode { auto, hongKong, china, custom }

/// 网络设置管理类
class NetworkSettings {
  static const String _dandanplayServerKey = 'dandanplay_server_url';
  static const String _dandanplayModeKey = 'dandanplay_server_mode';
  static const String _bangumiServerKey = 'bangumi_server_url';

  /// 自动模式判定的区域缓存（由 [NipaplayServerRouter] 写入）。
  static const String autoRegionKey = 'nipaplay_auto_region';
  static const String autoRegionAtKey = 'nipaplay_auto_region_at';

  /// 故障转移状态：主服务器连续失败后临时切到备用服务器。
  static const String failoverServerKey = 'nipaplay_failover_server';
  static const String failoverUntilKey = 'nipaplay_failover_until';

  static const String autoRegionChina = 'CN';
  static const String autoRegionOverseas = 'OVERSEAS';

  /// 香港主服务器：走域名（有证书、有备案，海外与港澳台直连）。
  static const String hongKongServer =
      'https://nipaplay.aimes-soft.com/dandanplay';

  /// 国内备用服务器：走 IP（不依赖域名解析与备案，国内直连稳定）。
  static const String chinaServer = 'http://43.142.85.190/dandanplay';

  /// 兼容旧代码：`primaryServer` 始终代表官方 NipaPlay 网关（香港域名）。
  static const String primaryServer = hongKongServer;

  /// 兼容旧代码：官方备用网关（国内 IP）。
  static const String backupServer = chinaServer;

  // 旧版本保存过的地址，仅用于迁移，客户端不再主动使用。
  static const String _legacyOfficialServer = 'https://api.dandanplay.net';
  static const String _legacyBackupServer = 'http://139.224.252.88:16001';

  /// 所有官方网关地址（顺序即下拉菜单顺序）。
  static const List<String> officialServers = [hongKongServer, chinaServer];

  // Bangumi 服务器常量
  static const String bangumiDefaultServer = 'https://api.bgm.tv';

  /// Recognize the provider by origin, never just by its compatible API path.
  static bool isDandanplayServiceUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'api.dandanplay.net' || host.endsWith('.dandanplay.net')) {
      return true;
    }
    for (final base in officialServers) {
      if (_matchesGateway(uri, base)) return true;
    }
    return host == '139.224.252.88' && uri.port == 16001;
  }

  static bool _matchesGateway(Uri uri, String base) {
    final gateway = Uri.parse(base);
    if (hostOf(uri) != hostOf(gateway)) return false;
    if (uri.scheme != gateway.scheme) return false;
    if (uri.port != gateway.port) return false;
    final basePath = gateway.path;
    if (basePath.isEmpty) return true;
    if (uri.path == basePath) return true;
    if (!uri.path.startsWith('$basePath/')) return false;
    // 健康检查不是弹弹play业务请求，不应被当作需要注入凭据的服务地址。
    return uri.path != '$basePath/healthz';
  }

  static String hostOf(Uri uri) => uri.host.toLowerCase();

  /// 当前弹弹play网关选择模式。
  static Future<DandanplayServerMode> getDandanplayServerMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dandanplayModeKey);
    if (raw != null) return _modeFromToken(raw);
    return _migrateMode(prefs);
  }

  /// 设置弹弹play网关选择模式。
  static Future<void> setDandanplayServerMode(
    DandanplayServerMode mode,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dandanplayModeKey, _modeToken(mode));
    // 注意：切换模式时保留用户填过的自定义地址，方便切回自定义时自动回填。
    // 非自定义模式下该地址不参与解析。
    // 手动切换模式会重置自动判定与故障转移的临时状态。
    await clearAutoRegion(prefs);
    await clearFailover(prefs);
    print('[网络设置] 弹弹play服务器模式已切换到: ${_modeToken(mode)}');
  }

  /// 旧版本只保存了服务器 URL，这里把它迁移成新模式。
  static Future<DandanplayServerMode> _migrateMode(
    SharedPreferences prefs,
  ) async {
    final stored = prefs.getString(_dandanplayServerKey);
    if (stored == null || stored.trim().isEmpty) {
      return DandanplayServerMode.auto;
    }
    final normalized = _normalizeServerUrl(stored);
    // 旧默认值（香港网关）与历史遗留地址都不是用户的刻意选择，
    // 迁移到自动模式以便国内用户自动走备用服务器。
    if (normalized == hongKongServer ||
        normalized == chinaServer ||
        normalized == _legacyOfficialServer ||
        normalized == _legacyBackupServer) {
      return DandanplayServerMode.auto;
    }
    return DandanplayServerMode.custom;
  }

  /// 获取当前生效的弹弹play服务器地址。
  ///
  /// 自动模式在此读取 [NipaplayServerRouter] 写入的缓存判定，
  /// 不发起任何网络请求；需要刷新判定请使用
  /// `NipaplayServerRouter.instance.effectiveServer()`。
  static Future<String> getDandanplayServer() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = await getDandanplayServerMode();
    switch (mode) {
      case DandanplayServerMode.hongKong:
        return hongKongServer;
      case DandanplayServerMode.china:
        return chinaServer;
      case DandanplayServerMode.custom:
        final custom = customServerOf(prefs);
        // 数据异常（模式为自定义但地址缺失）时回落到自动判定的结果。
        if (custom.isNotEmpty) return custom;
        final failover = activeFailover(prefs);
        if (failover != null) return failover;
        return prefs.getString(autoRegionKey) == autoRegionChina
            ? chinaServer
            : hongKongServer;
      case DandanplayServerMode.auto:
        final failover = activeFailover(prefs);
        if (failover != null) return failover;
        return prefs.getString(autoRegionKey) == autoRegionChina
            ? chinaServer
            : hongKongServer;
    }
  }

  /// 读取用户自定义服务器地址（未设置时返回空串）。
  static Future<String> getCustomServer() async {
    final prefs = await SharedPreferences.getInstance();
    return customServerOf(prefs);
  }

  /// 清除用户自定义服务器地址。
  static Future<void> clearCustomServer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dandanplayServerKey);
  }

  /// 读取用户自定义服务器地址（未设置时返回空串）。
  static String customServerOf(SharedPreferences prefs) {
    final stored = prefs.getString(_dandanplayServerKey);
    if (stored == null || stored.trim().isEmpty) return '';
    final normalized = _normalizeServerUrl(stored);
    if (officialServers.contains(normalized)) return '';
    return normalized;
  }

  /// 设置弹弹play服务器地址（保留旧 API；会同步推断选择模式）。
  static Future<void> setDandanplayServer(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeServerUrl(serverUrl);
    final mode = _modeForUrl(normalized);
    if (mode == DandanplayServerMode.custom) {
      await prefs.setString(_dandanplayServerKey, normalized);
    } else {
      await prefs.remove(_dandanplayServerKey);
    }
    await prefs.setString(_dandanplayModeKey, _modeToken(mode));
    await clearAutoRegion(prefs);
    await clearFailover(prefs);
    print('[网络设置] 弹弹play服务器已切换到: $normalized');
  }

  /// 把地址映射回选择模式；非官方地址视为自定义。
  static DandanplayServerMode _modeForUrl(String normalized) {
    if (normalized == hongKongServer) return DandanplayServerMode.hongKong;
    if (normalized == chinaServer) return DandanplayServerMode.china;
    if (normalized == _legacyOfficialServer ||
        normalized == _legacyBackupServer) {
      return DandanplayServerMode.auto;
    }
    return DandanplayServerMode.custom;
  }

  /// 获取当前 Bangumi 服务器地址
  static Future<String> getBangumiServer() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_bangumiServerKey) ?? bangumiDefaultServer;
    return _normalizeServerUrl(stored);
  }

  /// 设置 Bangumi 服务器地址
  static Future<void> setBangumiServer(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = await getBangumiServer();
    final normalized = _normalizeServerUrl(serverUrl);
    await prefs.setString(_bangumiServerKey, normalized);
    // 换 API 地址后清旧域名图片/详情缓存，否则旧缓存仍指向旧域名一直加载失败
    if (normalized != previous) {
      final stale = prefs.getKeys()
          .where((k) => k.startsWith('media_library_image_url_') ||
              k.startsWith('bangumi_detail_'))
          .toList();
      for (final key in stale) {
        await prefs.remove(key);
      }
    }
    print('[网络设置] Bangumi服务器已切换到: $normalized');
  }

  /// 检查当前 Bangumi 服务器是否为自定义服务器
  static bool isCustomBangumiServer(String serverUrl) {
    if (serverUrl.trim().isEmpty) {
      return false;
    }
    final normalized = _normalizeServerUrl(serverUrl);
    return normalized != bangumiDefaultServer;
  }

  /// 重置弹弹play为默认（自动选择）模式
  static Future<void> resetToDefaultServer() async {
    await setDandanplayServerMode(DandanplayServerMode.auto);
  }

  /// 重置Bangumi为默认服务器
  static Future<void> resetBangumiServer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bangumiServerKey);
    print('[网络设置] Bangumi服务器已重置为默认: $bangumiDefaultServer');
  }

  /// 获取所有可用服务器列表
  static List<Map<String, String>> getAvailableServers() {
    return [
      {
        'name': 'NipaPlay 服务（香港）',
        'url': hongKongServer,
        'description': '香港主服务器，走域名，海外与港澳台推荐',
      },
      {
        'name': 'NipaPlay 服务（国内）',
        'url': chinaServer,
        'description': '国内备用服务器，走 IP，中国大陆推荐',
      },
    ];
  }

  /// 检查当前服务器是否为自定义服务器
  static bool isCustomServer(String serverUrl) {
    if (serverUrl.trim().isEmpty) {
      return false;
    }
    final normalized = _normalizeServerUrl(serverUrl);
    return !isOfficialServer(normalized) &&
        normalized != _legacyOfficialServer &&
        normalized != _legacyBackupServer;
  }

  /// 是否为官方 NipaPlay 网关（香港或国内）。
  static bool isOfficialServer(String serverUrl) {
    if (serverUrl.trim().isEmpty) return false;
    return officialServers.contains(_normalizeServerUrl(serverUrl));
  }

  /// 给出官方服务器对应的用户可读名称；非官方返回 null。
  static String? officialServerLabel(String serverUrl) {
    final normalized = _normalizeServerUrl(serverUrl);
    if (normalized == hongKongServer) return '香港';
    if (normalized == chinaServer) return '国内';
    return null;
  }

  /// 网关地址 → 官方站点根地址（去掉 `/dandanplay` 前缀）。
  ///
  /// 随机推荐、日志分享等接口挂在站点根上而非网关下。
  static String siteRootOf(String gatewayUrl) {
    const gatewaySuffix = '/dandanplay';
    final normalized = _normalizeServerUrl(gatewayUrl);
    if (normalized.endsWith(gatewaySuffix)) {
      return normalized.substring(0, normalized.length - gatewaySuffix.length);
    }
    return normalized;
  }

  /// 粗略校验用户输入的服务器地址
  static bool isValidServerUrl(String serverUrl) {
    final normalized = _normalizeServerUrl(serverUrl);
    final uri = Uri.tryParse(normalized);
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // 自动判定 / 故障转移 缓存读写（供 NipaplayServerRouter 使用）
  // ---------------------------------------------------------------------------

  /// 缓存自动判定的区域结果。
  static Future<void> cacheAutoRegion(String region) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(autoRegionKey, region);
    await prefs.setInt(autoRegionAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// 读取缓存的自动判定结果，[maxAge] 内视为有效。
  static String? cachedAutoRegion(SharedPreferences prefs, Duration maxAge) {
    final region = prefs.getString(autoRegionKey);
    if (region == null || region.isEmpty) return null;
    final at = prefs.getInt(autoRegionAtKey);
    if (at == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    if (age < 0 || age > maxAge.inMilliseconds) return null;
    return region;
  }

  static Future<void> clearAutoRegion([SharedPreferences? prefs]) async {
    final target = prefs ?? await SharedPreferences.getInstance();
    await target.remove(autoRegionKey);
    await target.remove(autoRegionAtKey);
  }

  /// 记录一次故障转移：在 [until] 之前临时使用 [server]。
  static Future<void> markFailover(String server, Duration cooldown) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(failoverServerKey, server);
    await prefs.setInt(
      failoverUntilKey,
      DateTime.now().add(cooldown).millisecondsSinceEpoch,
    );
  }

  /// 当前生效的故障转移服务器；已过期或不存在时返回 null。
  static String? activeFailover(SharedPreferences prefs) {
    final server = prefs.getString(failoverServerKey);
    if (server == null || server.isEmpty) return null;
    final until = prefs.getInt(failoverUntilKey);
    if (until == null) return null;
    if (DateTime.now().millisecondsSinceEpoch >= until) return null;
    if (!officialServers.contains(server)) return null;
    return server;
  }

  static Future<void> clearFailover([SharedPreferences? prefs]) async {
    final target = prefs ?? await SharedPreferences.getInstance();
    await target.remove(failoverServerKey);
    await target.remove(failoverUntilKey);
  }

  static String _modeToken(DandanplayServerMode mode) {
    switch (mode) {
      case DandanplayServerMode.auto:
        return 'auto';
      case DandanplayServerMode.hongKong:
        return 'hongkong';
      case DandanplayServerMode.china:
        return 'china';
      case DandanplayServerMode.custom:
        return 'custom';
    }
  }

  static DandanplayServerMode _modeFromToken(String token) {
    switch (token) {
      case 'hongkong':
        return DandanplayServerMode.hongKong;
      case 'china':
        return DandanplayServerMode.china;
      case 'custom':
        return DandanplayServerMode.custom;
      case 'auto':
      default:
        return DandanplayServerMode.auto;
    }
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
