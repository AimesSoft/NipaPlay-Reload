import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一次自动判定的结果快照，用于网络设置界面展示诊断信息。
@immutable
class ServerRoutingSnapshot {
  const ServerRoutingSnapshot({
    required this.mode,
    required this.effectiveServer,
    this.detectedRegion,
    this.detectedIp,
    this.chinaLatency,
    this.hongKongLatency,
    this.failoverServer,
    this.failoverActive = false,
    this.refreshedAt,
  });

  final DandanplayServerMode mode;
  final String effectiveServer;
  final String? detectedRegion;
  final String? detectedIp;
  final Duration? chinaLatency;
  final Duration? hongKongLatency;
  final String? failoverServer;
  final bool failoverActive;
  final DateTime? refreshedAt;

  bool get isAuto => mode == DandanplayServerMode.auto;
}

/// 主/备用 NipaPlay 网关路由器。
///
/// 自动模式使用「IP 归属地 + 可达性」双重判定：
/// 1. 直接向国内备用服务器索取调用方 IP 归属地（国内服务器内置中国 IP 段表）；
/// 2. 并发探测两地网关的 [healthz] 延迟作为兜底；
/// 3. 判定结果会缓存，避免每次请求都探测。
///
/// 运行期任一官方网关连续失败达到阈值后，会临时切到另一台作为备用服务器。
class NipaplayServerRouter {
  NipaplayServerRouter._();

  static final NipaplayServerRouter instance = NipaplayServerRouter._();

  /// 自动判定结果缓存时长。
  static const Duration regionTtl = Duration(hours: 6);

  static const Duration _regionProbeTimeout = Duration(seconds: 4);
  static const Duration _healthTimeout = Duration(seconds: 3);

  /// 备用服务器临时接管时长。
  static const Duration failoverCooldown = Duration(minutes: 5);

  /// 连续失败多少次后触发备用服务器接管。
  static const int failureThreshold = 3;

  /// 判定为国内时，香港延迟需要差于国内多少倍才认为国内更优。
  static const Duration _chinaLatencyCeiling = Duration(milliseconds: 1500);

  final Map<String, int> _consecutiveFailures = {};

  ServerRoutingSnapshot? _snapshot;

  /// 最近一次判定/切换后的状态，供界面订阅。
  final ValueNotifier<ServerRoutingSnapshot?> snapshotNotifier =
      ValueNotifier<ServerRoutingSnapshot?>(null);

  ServerRoutingSnapshot? get snapshot => _snapshot;

  /// 国内备用服务器的归属地接口地址。
  static Uri get regionProbeUri =>
      Uri.parse(NetworkSettings.chinaServer).replace(path: '/region');

  /// 返回当前应当使用的弹弹play网关地址。
  ///
  /// [forceRefresh] 为 true 时忽略自动判定缓存并重新探测。
  Future<String> effectiveServer({bool forceRefresh = false}) async {
    final mode = await NetworkSettings.getDandanplayServerMode();
    final String server;
    if (mode == DandanplayServerMode.custom) {
      server = await NetworkSettings.getDandanplayServer();
    } else {
      server = await officialServer(forceRefresh: forceRefresh);
    }
    await _publishSnapshot(server);
    return server;
  }

  /// 只考虑官方主/备用服务器时的选择结果（自定义网关不参与）。
  ///
  /// 用于随机推荐、日志分享等只部署在官方站点上的接口。
  Future<String> officialServer({bool forceRefresh = false}) async {
    final mode = await NetworkSettings.getDandanplayServerMode();
    switch (mode) {
      case DandanplayServerMode.hongKong:
        return NetworkSettings.hongKongServer;
      case DandanplayServerMode.china:
        return NetworkSettings.chinaServer;
      case DandanplayServerMode.custom:
      case DandanplayServerMode.auto:
        break;
    }
    if (forceRefresh) {
      await NetworkSettings.clearAutoRegion();
      await _detectAndCacheRegion();
    } else {
      await _ensureAutoRegion();
    }
    final prefs = await SharedPreferences.getInstance();
    final failover = NetworkSettings.activeFailover(prefs);
    if (failover != null) return failover;
    return prefs.getString(NetworkSettings.autoRegionKey) ==
            NetworkSettings.autoRegionChina
        ? NetworkSettings.chinaServer
        : NetworkSettings.hongKongServer;
  }

  /// 官方站点根地址（去掉网关路径前缀）。
  Future<String> officialSiteBase({bool forceRefresh = false}) async {
    return NetworkSettings.siteRootOf(
      await officialServer(forceRefresh: forceRefresh),
    );
  }

  /// 主动刷新自动判定（网络设置界面“网络诊断”和模式切换时使用）。
  Future<String> refresh() async {
    await NetworkSettings.clearFailover();
    final mode = await NetworkSettings.getDandanplayServerMode();
    if (mode == DandanplayServerMode.auto) {
      await NetworkSettings.clearAutoRegion();
      await _detectAndCacheRegion();
    }
    return effectiveServer();
  }

  Future<void> _ensureAutoRegion() async {
    final prefs = await SharedPreferences.getInstance();
    if (NetworkSettings.cachedAutoRegion(prefs, regionTtl) != null) return;
    await _detectAndCacheRegion();
  }

  /// 执行一次「IP 归属地 + 可达性」判定并写入缓存。
  Future<void> _detectAndCacheRegion() async {
    // HTTPS 页面无法直接请求 http:// 的国内备用服务器（混合内容会被浏览器拦截），
    // 此时只能使用香港域名服务器。
    if (kIsWeb && Uri.base.scheme == 'https') {
      await NetworkSettings.cacheAutoRegion(NetworkSettings.autoRegionOverseas);
      return;
    }

    final regionFuture = _probeChinaRegion();
    final chinaFuture = _probeHealth(NetworkSettings.chinaServer);
    final hongKongFuture = _probeHealth(NetworkSettings.hongKongServer);

    final region = await regionFuture;
    final chinaLatency = await chinaFuture;
    final hongKongLatency = await hongKongFuture;

    final decision = _decideRegion(
      region: region,
      chinaLatency: chinaLatency,
      hongKongLatency: hongKongLatency,
    );

    _lastIp = region?.ip;
    _lastChinaLatency = chinaLatency;
    _lastHongKongLatency = hongKongLatency;

    await NetworkSettings.cacheAutoRegion(
      decision == DandanplayServerMode.china
          ? NetworkSettings.autoRegionChina
          : NetworkSettings.autoRegionOverseas,
    );
    debugPrint(
      '[网关路由] 自动判定: region=${region?.region} ip=${region?.ip} '
      'cn=${chinaLatency?.inMilliseconds}ms hk=${hongKongLatency?.inMilliseconds}ms '
      '=> ${decision == DandanplayServerMode.china ? "国内" : "香港"}',
    );
  }

  DandanplayServerMode _decideRegion({
    _RegionProbeResult? region,
    Duration? chinaLatency,
    Duration? hongKongLatency,
  }) {
    // 1. 归属地接口成功时以其为准。国内服务器直接回报调用方 IP 是否属于中国大陆。
    if (region != null) {
      final isChina = region.isChina;
      if (isChina && chinaLatency == null) {
        // 归属地说在国内，但备用服务器此刻探测不通：退回香港保证可用。
        return DandanplayServerMode.hongKong;
      }
      return isChina
          ? DandanplayServerMode.china
          : DandanplayServerMode.hongKong;
    }

    // 2. 归属地接口不可用时退化为可达性判定：
    //    国内服务器可达且延迟可接受，说明用户大概率在国内。
    if (chinaLatency != null && chinaLatency <= _chinaLatencyCeiling) {
      if (hongKongLatency == null) return DandanplayServerMode.china;
      if (chinaLatency * 2 <= hongKongLatency) {
        return DandanplayServerMode.china;
      }
    }

    // 3. 其余情况一律使用香港主服务器（有域名与证书，全球可用）。
    return DandanplayServerMode.hongKong;
  }

  String? _lastIp;
  Duration? _lastChinaLatency;
  Duration? _lastHongKongLatency;

  Future<_RegionProbeResult?> _probeChinaRegion() async {
    final uri = regionProbeUri;
    final stopwatch = Stopwatch()..start();
    try {
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_regionProbeTimeout);
      stopwatch.stop();
      if (response.statusCode != 200) return null;
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      return _RegionProbeResult(
        region: decoded['region']?.toString(),
        country: decoded['country']?.toString(),
        ip: decoded['ip']?.toString(),
        latency: stopwatch.elapsed,
      );
    } catch (error) {
      debugPrint('[网关路由] 归属地探测失败: $error');
      return null;
    }
  }

  Future<Duration?> _probeHealth(String server) async {
    final uri = Uri.parse('$server/healthz');
    final stopwatch = Stopwatch()..start();
    try {
      final response =
          await http.get(uri).timeout(_healthTimeout);
      stopwatch.stop();
      if (response.statusCode != 200) return null;
      return stopwatch.elapsed;
    } catch (_) {
      return null;
    }
  }

  /// 请求成功时清除该服务器的失败计数。
  void reportSuccess(Uri uri) {
    final server = _officialServerFor(uri);
    if (server == null) return;
    _consecutiveFailures.remove(server);
  }

  /// 请求失败时累计计数，达到阈值后由备用服务器临时接管。
  void reportFailure(Uri uri) {
    final server = _officialServerFor(uri);
    if (server == null) return;
    final failures = (_consecutiveFailures[server] ?? 0) + 1;
    if (failures < failureThreshold) {
      _consecutiveFailures[server] = failures;
      return;
    }
    _consecutiveFailures[server] = 0;
    unawaited(_failoverTo(server));
  }

  Future<void> _failoverTo(String failedServer) async {
    final mode = await NetworkSettings.getDandanplayServerMode();
    if (mode == DandanplayServerMode.custom) return;

    final prefs = await SharedPreferences.getInstance();
    final current = NetworkSettings.activeFailover(prefs);
    if (current != null && current != failedServer) {
      // 备用服务器也在失败，不要来回抖动。
      return;
    }

    final backup = NetworkSettings.officialServers.firstWhere(
      (server) => server != failedServer,
      orElse: () => '',
    );
    if (backup.isEmpty) return;

    await NetworkSettings.markFailover(backup, failoverCooldown);
    debugPrint('[网关路由] $failedServer 连续失败，临时切换到备用服务器 $backup');
    await _publishSnapshot(backup);
  }

  static String? _officialServerFor(Uri uri) {
    for (final server in NetworkSettings.officialServers) {
      final gateway = Uri.parse(server);
      if (gateway.host.toLowerCase() == uri.host.toLowerCase() &&
          gateway.port == uri.port &&
          uri.path.startsWith(gateway.path)) {
        return server;
      }
    }
    return null;
  }

  Future<void> _publishSnapshot(String effectiveServer) async {
    final mode = await NetworkSettings.getDandanplayServerMode();
    final prefs = await SharedPreferences.getInstance();
    final failover = NetworkSettings.activeFailover(prefs);
    final snapshot = ServerRoutingSnapshot(
      mode: mode,
      effectiveServer: effectiveServer,
      detectedRegion: prefs.getString(NetworkSettings.autoRegionKey),
      detectedIp: _lastIp,
      chinaLatency: _lastChinaLatency,
      hongKongLatency: _lastHongKongLatency,
      failoverServer: failover,
      failoverActive: failover != null,
      refreshedAt: DateTime.now(),
    );
    _snapshot = snapshot;
    snapshotNotifier.value = snapshot;
  }
}

class _RegionProbeResult {
  const _RegionProbeResult({
    required this.region,
    required this.country,
    required this.ip,
    required this.latency,
  });

  final String? region;
  final String? country;
  final String? ip;
  final Duration latency;

  bool get isChina {
    final normalizedRegion = region?.trim().toUpperCase() ?? '';
    final normalizedCountry = country?.trim().toUpperCase() ?? '';
    return normalizedRegion == 'CN' ||
        normalizedRegion == 'CHINA' ||
        normalizedCountry == 'CN' ||
        normalizedCountry == 'CHINA';
  }
}
