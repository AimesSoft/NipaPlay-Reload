import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  Directory? previousStorage;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('lan-image-loader-');
    previousStorage = StorageService.debugAppStorageDirectoryOverride;
    StorageService.debugAppStorageDirectoryOverride = directory;
    ImageCacheManager.instance.clear();
  });
  tearDownAll(() async {
    ImageCacheManager.instance.clear();
    StorageService.debugAppStorageDirectoryOverride = previousStorage;
    await directory.delete(recursive: true);
  });
  test('image downloads cannot anonymously call a Dandanplay API', () async {
    await expectLater(
      loadNetworkImageBytes(
        Uri.parse('${NetworkSettings.primaryServer}/api/v2/image/1'),
      ),
      throwsA(isA<DandanplayLoginRequired>()),
    );
  });

  test('media-server image detection stays inside the registered base path',
      () {
    setMediaServerBaseUrl('test-emby', 'https://media.example/emby');
    addTearDown(() => setMediaServerBaseUrl('test-emby', null));

    expect(
      isMediaServerImageUri(
        Uri.parse(
          'https://media.example/emby/Items/library-id/Images/Primary',
        ),
      ),
      isTrue,
    );
    expect(
      isMediaServerImageUri(
        Uri.parse(
          'https://media.example/other/Items/library-id/Images/Primary',
        ),
      ),
      isFalse,
    );
  });

  test('the default media-server image loader uses the configured transport',
      () async {
    final receivedRequests = <({Uri uri, String? userAgent})>[];
    final expectedBytes = Uint8List.fromList([1, 2, 3, 4]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      receivedRequests.add((
        uri: request.requestedUri,
        userAgent: request.headers.value('user-agent'),
      ));
      request.response
        ..statusCode = HttpStatus.ok
        ..add(expectedBytes);
      await request.response.close();
    });
    final savedUserAgent = await MediaServerServiceBase.saveConnectionUserAgent(
      '  EmbyClient/2.0\r\nInjected  ',
    );
    addTearDown(() => MediaServerServiceBase.saveConnectionUserAgent(''));
    final target = Uri.parse(
      'http://${server.address.address}:${server.port}'
      '/emby/Items/library-id/Images/Primary',
    );
    setMediaServerBaseUrl(
      'test-emby',
      'http://${server.address.address}:${server.port}',
    );
    addTearDown(() => setMediaServerBaseUrl('test-emby', null));

    final bytes = await HttpOverrides.runWithHttpOverrides(
      () => loadNetworkImageBytes(target),
      _DirectHttpOverrides(),
    );

    expect(savedUserAgent, 'EmbyClient/2.0Injected');
    expect(receivedRequests, [
      (uri: target, userAgent: 'EmbyClient/2.0Injected'),
    ]);
    expect(bytes, expectedBytes);
  });

  test('uncompressed images use the unified client without creating disk files',
      () async {
    const url = 'https://image.fixture.example/detail.png';
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    var requests = 0;
    final image = await http.runWithClient(
      () => ImageCacheManager.instance.loadImage(url, cacheOnDisk: false),
      () => MockClient((request) async {
        requests++;
        expect(request.url.toString(), url);
        return http.Response.bytes(png, 200,
            headers: {'content-type': 'image/png'});
      }),
    );
    expect(requests, 1);
    expect(image.width, 1);
    expect(image.height, 1);
    expect(
        await directory
            .list(recursive: true)
            .where((entity) => entity is File)
            .length,
        0);
  });

  test('uncompressed detail images use the unified network image loader', () {
    final widgetSource = File(
      'lib/themes/nipaplay/widgets/cached_network_image_widget.dart',
    ).readAsStringSync();
    final cacheSource = File(
      'lib/utils/image_cache_manager.dart',
    ).readAsStringSync();
    final detailSource = File(
      'lib/pages/media_server_detail_page.dart',
    ).readAsStringSync();

    expect(detailSource, contains('shouldCompress: false'));
    // The widget loads every image, compressed or not, through the cache
    // manager, which downloads with the unified loader.
    expect(widgetSource, isNot(contains('http.get(')));
    expect(
      RegExp(r'ImageCacheManager\.instance\.loadImage\(')
          .allMatches(widgetSource),
      hasLength(greaterThanOrEqualTo(2)),
    );
    expect(cacheSource, isNot(contains('http.get(')));
    expect(cacheSource, contains('loadNetworkImageBytes('));
  });
}

class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
