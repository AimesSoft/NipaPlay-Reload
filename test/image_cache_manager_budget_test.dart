import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an image larger than the cache budget remains usable by its caller',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final previousPathProvider = PathProviderPlatform.instance;
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'nipaplay-image-budget-test-',
    );
    PathProviderPlatform.instance = _TemporaryPathProvider(
      temporaryDirectory.path,
    );
    final manager = ImageCacheManager.instance;
    final previousBudget = ImageCacheManager.maxBytes;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      manager.clear();
      ImageCacheManager.maxBytes = previousBudget;
      PathProviderPlatform.instance = previousPathProvider;
      await temporaryDirectory.delete(recursive: true);
    });

    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
      'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('image', 'png')
        ..add(pngBytes);
      await request.response.close();
    });

    manager.clear();
    ImageCacheManager.maxBytes = 512;
    final image = await HttpOverrides.runWithHttpOverrides(
      () => manager.loadImage(
        'http://${server.address.address}:${server.port}/backdrop.png',
        targetWidth: 16,
        targetHeight: 16,
        forceRefresh: true,
      ),
      _RealHttpOverrides(),
    );

    expect(image.width, 16);
    expect(image.height, 16);
    expect(manager.currentCacheCount, 0);
    expect(manager.currentCacheBytes, 0);
    image.dispose();
  });
}

class _TemporaryPathProvider extends PathProviderPlatform {
  _TemporaryPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

class _RealHttpOverrides extends HttpOverrides {}
