import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';
import 'package:nipaplay/services/media_server_service_base.dart';

void main() {
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

    final bytes = await loadNetworkImageBytes(target);

    expect(savedUserAgent, 'EmbyClient/2.0Injected');
    expect(receivedRequests, [
      (uri: target, userAgent: 'EmbyClient/2.0Injected'),
    ]);
    expect(bytes, expectedBytes);
  });

  test('uncompressed detail images use the unified network image loader', () {
    final widgetSource = File(
      'lib/themes/nipaplay/widgets/cached_network_image_widget.dart',
    ).readAsStringSync();
    final detailSource = File(
      'lib/pages/media_server_detail_page.dart',
    ).readAsStringSync();

    expect(detailSource, contains('shouldCompress: false'));
    expect(widgetSource, isNot(contains('http.get(')));
    expect(
      RegExp('loadNetworkImageBytes').allMatches(widgetSource),
      hasLength(greaterThanOrEqualTo(2)),
    );
  });
}
