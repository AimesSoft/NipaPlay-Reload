import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/webdav_proxy_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/external_player_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  for (final onlyWan in [false, true]) {
    test(
        'HTTP 500 probe failure falls back to ${onlyWan ? 'WAN-only' : 'LAN-first'} configured URL even with proxy running',
        () async {
      final lan = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final wan = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => lan.close(force: true));
      addTearDown(() => wan.close(force: true));
      final seenPorts = <int>{};
      for (final server in [lan, wan]) {
        unawaited(server.forEach((request) async {
          seenPorts.add(server.port);
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }));
      }
      final connection = WebDAVConnection(
        id: onlyWan ? 'wan-only-failure' : 'dual-failure',
        name: 'DAV',
        url: onlyWan ? '' : 'http://127.0.0.1:${lan.port}/dav/',
        wanUrl: 'http://127.0.0.1:${wan.port}/dav/',
        username: 'user',
        password: 'p@ss word',
      );
      SharedPreferences.setMockInitialValues({
        'webdav_connections': jsonEncode([connection.toJson()]),
        'webdav_proxy_port': 0,
      });
      final service = WebDAVService.instance;
      await service.initialize();
      final proxy = WebDAVProxyService.instance;
      await proxy.initialize();
      addTearDown(proxy.stop);
      service.setPreferredAddress(connection.id, useWan: true);
      await service.updateConnectionStatus('DAV');
      expect(service.lastAddressReachability(connection.id),
          (lan: false, wan: false));
      expect(service.connections.single.isConnected, isFalse);
      expect(seenPorts, onlyWan ? {wan.port} : {lan.port, wan.port});
      const relative = '/Anime/第 1 集.mkv';
      final stable = MediaSourceUtils.buildWebDavPath(connection.id, relative);
      final url =
          await MediaSourceUtils.resolveWebDavPathToUrlInitialized(stable);
      final uri = Uri.parse(url!);
      expect(uri.port, onlyWan ? wan.port : lan.port);
      expect(Uri.decodeComponent(uri.path), '/dav$relative');
      expect(Uri.decodeComponent(uri.userInfo), 'user:p@ss word');
      expect(uri.path, isNot('/webdav/stream'));
      expect(proxy.isRunning, isTrue);
      expect(MediaSourceUtils.resolveWebDavPathToUrl(stable), url);
      expect(
          await resolveExternalPlayerMediaPath(PlayableItem(
            videoPath: stable,
            actualPlayUrl: proxy.buildStreamUrl(connection, relative),
          )),
          url);
      // Reloading configuration must not lose the fallback decision.
      await service.initialize();
      expect(MediaSourceUtils.resolveWebDavPathToUrl(stable), url);
    });
  }
}
