import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousOverrides = HttpOverrides.current;
  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
  });
  tearDown(() => HttpOverrides.global = previousOverrides);

  for (final emby in [false, true]) {
    test('${emby ? "Emby" : "Jellyfin"} service decodes all folder pages',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dynamic service =
          emby ? EmbyService.instance : JellyfinService.instance;
      final starts = <int>[];
      service.serverUrl = 'http://127.0.0.1:${server.port}';
      service.userId = 'user';
      service.accessToken = 'fixture';
      service.currentProfile = null;
      service.isConnected = true;
      addTearDown(() async {
        (service as MediaServerServiceBase).isConnected = false;
        service.serverUrl = null;
        service.userId = null;
        service.accessToken = null;
        await server.close(force: true);
      });
      server.listen((request) async {
        if (emby) expect(request.uri.path, '/emby/Users/user/Items');
        final query = request.uri.queryParameters;
        final start = int.parse(query['StartIndex']!);
        final limit = int.parse(query['Limit']!);
        starts.add(start);
        expect(limit, lessThanOrEqualTo(200));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'TotalRecordCount': 1000,
          'Items': List.generate(
              (1000 - start).clamp(0, limit),
              (i) => {
                    'Id': '${start + i}',
                    'Name': 'Item ${(start + i).toString().padLeft(4, "0")}',
                    'Type': 'Movie',
                    'Overview': 'x' * 512,
                    'DateCreated': '2026-01-01T00:00:00Z',
                  }),
        }));
        await request.response.close();
      });
      final List<dynamic> items = await service.getFolderItems('library');
      expect(items.length, 1000);
      expect(items.map((item) => item.id).toSet().length, 1000);
      expect(starts, [0, 200, 400, 600, 800]);
    });

    test('${emby ? "Emby" : "Jellyfin"} provider discards superseded load',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dynamic service =
          emby ? EmbyService.instance : JellyfinService.instance;
      final dynamic provider = emby ? EmbyProvider() : JellyfinProvider();
      service.serverUrl = 'http://127.0.0.1:${server.port}';
      service.userId = 'user';
      service.accessToken = 'fixture';
      service.currentProfile = null;
      service.isConnected = true;
      service.selectedLibraryIds = <String>['library'];
      final firstPage = Completer<void>();
      final releaseOld = Completer<void>();
      var pages = 0;
      addTearDown(() async {
        provider.dispose();
        service.isConnected = false;
        service.serverUrl = null;
        service.userId = null;
        service.accessToken = null;
        service.selectedLibraryIds = <String>[];
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (emby) {
          expect(request.uri.path.startsWith('/emby/Users/user/Items'), isTrue);
        }
        if (request.uri.path.endsWith('/Items/library')) {
          request.response.write('{"CollectionType":"movies"}');
        } else {
          final old = ++pages == 1;
          if (old) {
            firstPage.complete();
            await releaseOld.future;
          }
          request.response.write(jsonEncode({
            'TotalRecordCount': 1,
            'Items': [
              {
                'Id': old ? 'old' : 'new',
                'Name': 'Movie',
                'Type': 'Movie',
                'DateCreated': '2026-01-01T00:00:00Z'
              }
            ],
          }));
        }
        await request.response.close();
      });
      final Future<void> old = provider.loadMediaItems();
      await firstPage.future;
      await provider.loadMediaItems();
      releaseOld.complete();
      await old;
      expect(provider.mediaItems.single.id, 'new');
      expect(provider.isLoading, false);
      expect(pages, 2);
    });
  }
}
