import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/nipaplay_server_router.dart';
import 'package:nipaplay/services/random_recommendation_service.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 预置自动判定缓存，避免测试真的发起网络探测。
void seedAutoRegion(String region, {Duration age = Duration.zero}) {
  final at = DateTime.now().subtract(age).millisecondsSinceEpoch;
  SharedPreferences.setMockInitialValues({
    NetworkSettings.autoRegionKey: region,
    NetworkSettings.autoRegionAtKey: at,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('server mode preferences', () {
    test('defaults to automatic mode', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await NetworkSettings.getDandanplayServerMode(),
        DandanplayServerMode.auto,
      );
    });

    test('explicit mode survives a round trip', () async {
      SharedPreferences.setMockInitialValues({});
      for (final mode in DandanplayServerMode.values) {
        await NetworkSettings.setDandanplayServerMode(mode);
        expect(await NetworkSettings.getDandanplayServerMode(), mode);
      }
    });

    test('storing an official URL infers the matching fixed mode', () async {
      SharedPreferences.setMockInitialValues({});
      await NetworkSettings.setDandanplayServer(NetworkSettings.chinaServer);
      expect(
        await NetworkSettings.getDandanplayServerMode(),
        DandanplayServerMode.china,
      );
      expect(
        await NetworkSettings.getDandanplayServer(),
        NetworkSettings.chinaServer,
      );

      await NetworkSettings.setDandanplayServer(
        NetworkSettings.hongKongServer,
      );
      expect(
        await NetworkSettings.getDandanplayServerMode(),
        DandanplayServerMode.hongKong,
      );
      expect(
        await NetworkSettings.getDandanplayServer(),
        NetworkSettings.hongKongServer,
      );
    });

    test('storing a third-party URL switches to custom mode', () async {
      SharedPreferences.setMockInitialValues({});
      await NetworkSettings.setDandanplayServer('https://third.example/api');
      expect(
        await NetworkSettings.getDandanplayServerMode(),
        DandanplayServerMode.custom,
      );
      expect(
        await NetworkSettings.getDandanplayServer(),
        'https://third.example/api',
      );
      expect(
        NetworkSettings.isCustomServer('https://third.example/api'),
        isTrue,
      );
    });

    test('resetting returns to automatic mode', () async {
      SharedPreferences.setMockInitialValues({});
      await NetworkSettings.setDandanplayServer('https://third.example/api');
      await NetworkSettings.resetToDefaultServer();
      expect(
        await NetworkSettings.getDandanplayServerMode(),
        DandanplayServerMode.auto,
      );
    });

    test('switching away from custom keeps the entered address', () async {
      SharedPreferences.setMockInitialValues({});
      await NetworkSettings.setDandanplayServer('https://third.example/api');
      await NetworkSettings.setDandanplayServerMode(
        DandanplayServerMode.auto,
      );
      // 地址被保留以便切回自定义时回填，但不再参与解析。
      expect(
        await NetworkSettings.getCustomServer(),
        'https://third.example/api',
      );
      expect(
        await NetworkSettings.getDandanplayServer(),
        isNot('https://third.example/api'),
      );

      await NetworkSettings.clearCustomServer();
      expect(await NetworkSettings.getCustomServer(), isEmpty);
    });

    test('legacy stored URLs migrate to automatic mode', () async {
      for (final legacy in [
        'https://api.dandanplay.net',
        'http://139.224.252.88:16001',
        NetworkSettings.hongKongServer,
        NetworkSettings.chinaServer,
      ]) {
        SharedPreferences.setMockInitialValues({
          'dandanplay_server_url': legacy,
        });
        expect(
          await NetworkSettings.getDandanplayServerMode(),
          DandanplayServerMode.auto,
          reason: 'legacy URL $legacy should migrate to auto',
        );
        expect(
          await NetworkSettings.getDandanplayServer(),
          NetworkSettings.hongKongServer,
        );
      }
    });
  });

  group('automatic region selection', () {
    test('cached China region resolves to the China server', () async {
      seedAutoRegion(NetworkSettings.autoRegionChina);
      expect(
        await NipaplayServerRouter.instance.effectiveServer(),
        NetworkSettings.chinaServer,
      );
    });

    test('cached overseas region resolves to the Hong Kong server', () async {
      seedAutoRegion(NetworkSettings.autoRegionOverseas);
      expect(
        await NipaplayServerRouter.instance.effectiveServer(),
        NetworkSettings.hongKongServer,
      );
    });

    test('a stale cache is not trusted', () async {
      seedAutoRegion(
        NetworkSettings.autoRegionChina,
        age: NipaplayServerRouter.regionTtl + const Duration(minutes: 1),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        NetworkSettings.cachedAutoRegion(
          prefs,
          NipaplayServerRouter.regionTtl,
        ),
        isNull,
      );
    });

    test('fixed modes ignore the cached region', () async {
      seedAutoRegion(NetworkSettings.autoRegionChina);
      await NetworkSettings.setDandanplayServerMode(
        DandanplayServerMode.hongKong,
      );
      expect(
        await NipaplayServerRouter.instance.effectiveServer(),
        NetworkSettings.hongKongServer,
      );
    });

    test('custom mode takes precedence over the official gateways', () async {
      seedAutoRegion(NetworkSettings.autoRegionChina);
      await NetworkSettings.setDandanplayServer('https://third.example/api');
      expect(
        await NipaplayServerRouter.instance.effectiveServer(),
        'https://third.example/api',
      );
    });
  });

  group('official site base', () {
    test('derives the site root from the gateway path', () async {
      seedAutoRegion(NetworkSettings.autoRegionChina);
      expect(
        await NipaplayServerRouter.instance.officialSiteBase(),
        'http://43.142.85.190',
      );
    });

    test('a third-party gateway never leaks into official site features',
        () async {
      SharedPreferences.setMockInitialValues({});
      await NetworkSettings.setDandanplayServer('https://third.example/api');
      // 自定义网关不参与官方站点接口：官方线路仍按自动判定走国内。
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        NetworkSettings.autoRegionKey,
        NetworkSettings.autoRegionChina,
      );
      await prefs.setInt(
        NetworkSettings.autoRegionAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      expect(
        await RandomRecommendationService.instance.resolveEndpoint(),
        'http://43.142.85.190/api/random-recommendations',
      );
    });
  });

  group('gateway URL recognition', () {
    test('recognizes both official gateways and their sub paths', () {
      for (final base in [
        NetworkSettings.hongKongServer,
        NetworkSettings.chinaServer,
      ]) {
        expect(
          NetworkSettings.isDandanplayServiceUri(Uri.parse(base)),
          isTrue,
          reason: base,
        );
        expect(
          NetworkSettings.isDandanplayServiceUri(
            Uri.parse('$base/api/v2/bangumi/1'),
          ),
          isTrue,
          reason: base,
        );
        // 健康检查不应被当成需要注入凭据的业务请求。
        expect(
          NetworkSettings.isDandanplayServiceUri(Uri.parse('$base/healthz')),
          isFalse,
          reason: base,
        );
      }
    });

    test('still recognizes the upstream Dandanplay API', () {
      expect(
        NetworkSettings.isDandanplayServiceUri(
          Uri.parse('https://api.dandanplay.net/api/v2/search/episodes'),
        ),
        isTrue,
      );
    });

    test('rejects unrelated hosts even with a compatible path', () {
      expect(
        NetworkSettings.isDandanplayServiceUri(
          Uri.parse('https://third.example/dandanplay/api/v2/bangumi/1'),
        ),
        isFalse,
      );
      expect(
        NetworkSettings.isDandanplayServiceUri(
          Uri.parse('http://43.142.85.190:8080/dandanplay/api/v2/bangumi/1'),
        ),
        isFalse,
      );
    });

    test('site root strips only the gateway suffix', () {
      expect(
        NetworkSettings.siteRootOf(NetworkSettings.hongKongServer),
        'https://nipaplay.aimes-soft.com',
      );
      expect(
        NetworkSettings.siteRootOf(NetworkSettings.chinaServer),
        'http://43.142.85.190',
      );
      expect(
        NetworkSettings.siteRootOf('https://third.example/api'),
        'https://third.example/api',
      );
    });
  });

  group('backup server failover', () {
    final router = NipaplayServerRouter.instance;
    final chinaUri = Uri.parse(NetworkSettings.chinaServer);
    final hongKongUri = Uri.parse(NetworkSettings.hongKongServer);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // 单例的连续失败计数会跨测试保留，这里显式清零。
      router.reportSuccess(chinaUri);
      router.reportSuccess(hongKongUri);
    });

    test('repeated failures switch the active server to the backup', () async {
      seedAutoRegion(NetworkSettings.autoRegionChina);

      for (var i = 0; i < NipaplayServerRouter.failureThreshold; i++) {
        router.reportFailure(chinaUri);
      }
      // 故障转移是异步落盘的，等待微任务队列清空。
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final prefs = await SharedPreferences.getInstance();
      expect(
        NetworkSettings.activeFailover(prefs),
        NetworkSettings.hongKongServer,
      );
      expect(
        await router.effectiveServer(),
        NetworkSettings.hongKongServer,
      );
    });

    test('a success clears the failure counter before the threshold',
        () async {
      seedAutoRegion(NetworkSettings.autoRegionChina);

      for (var i = 0; i < NipaplayServerRouter.failureThreshold - 1; i++) {
        router.reportFailure(chinaUri);
      }
      router.reportSuccess(chinaUri);
      router.reportFailure(chinaUri);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final prefs = await SharedPreferences.getInstance();
      expect(NetworkSettings.activeFailover(prefs), isNull);
    });

    test('an expired failover entry is ignored', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        NetworkSettings.failoverServerKey,
        NetworkSettings.hongKongServer,
      );
      await prefs.setInt(
        NetworkSettings.failoverUntilKey,
        DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );
      expect(NetworkSettings.activeFailover(prefs), isNull);
    });

    test('custom mode never fails over to an official gateway', () async {
      await NetworkSettings.setDandanplayServer('https://third.example/api');
      for (var i = 0; i < NipaplayServerRouter.failureThreshold; i++) {
        router.reportFailure(chinaUri);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(NetworkSettings.activeFailover(prefs), isNull);
    });
  });
}
