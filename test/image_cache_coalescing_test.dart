import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'different sizes share download, failures retry, and disk opt-out remains',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('image-coalesce-');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    final manager = ImageCacheManager.instance;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      manager.clear();
      PathProviderPlatform.instance = previous;
      await directory.delete(recursive: true);
    });
    final bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    var requests = 0;
    var fail = false;
    var corruptNext = false;
    server.listen((request) async {
      requests++;
      // Keep requests in flight long enough for the second decoded size to join.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      request.response.statusCode = fail ? 500 : 200;
      request.response.add(request.uri.path.endsWith('.svg')
          ? utf8.encode(
              '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="30"></svg>')
          : corruptNext
              ? utf8.encode('truncated')
              : bytes);
      corruptNext = false;
      await request.response.close();
    });
    final url = 'http://${server.address.address}:${server.port}/poster.png';
    await HttpOverrides.runWithHttpOverrides(() async {
      final images = await Future.wait([
        manager.loadImage(url, targetWidth: 16, targetHeight: 16),
        manager.loadImage(url, targetWidth: 32, targetHeight: 32),
        manager.loadImage(url, targetWidth: 16, targetHeight: 16),
      ]);
      expect(requests, 1);
      expect(images.map((image) => image.width), [16, 32, 16]);
      expect(identical(images[0], images[2]), isTrue);
      await manager.loadImage(url, targetWidth: 24, targetHeight: 24);
      expect(requests, 1, reason: 'new size can reuse disk bytes');
      // Decoded-memory eviction is not disk eviction. Reopening or requesting
      // encoded logo bytes must not fetch the original again.
      manager.clear();
      await manager.loadImage(url, targetWidth: 16, targetHeight: 16);
      await manager.loadImageBytes(url);
      expect(requests, 1);

      corruptNext = true;
      final damaged = '$url?damaged';
      await manager.loadImageBytes(damaged);
      final beforeRepair = requests;
      await manager.loadImage(damaged, targetWidth: 16);
      expect(requests, beforeRepair + 1,
          reason: 'repair corrupt cached bytes once');
      manager.clear();
      await manager.loadImage(damaged, targetWidth: 16);
      expect(requests, beforeRepair + 1,
          reason: 'repaired disk data is reused');
      final svgUrl = '$url.svg';
      final beforeSvg = requests;
      final svg = await manager.loadImageBytes(svgUrl);
      expect(utf8.decode(svg), startsWith('<svg'));
      await manager.loadImageBytes(svgUrl);
      expect(requests, beforeSvg + 1,
          reason: 'SVG logos share the persistent byte cache');
      final beforeFailure = requests;

      fail = true;
      await expectLater(manager.loadImage('$url?retry', cacheOnDisk: false),
          throwsA(anything));
      fail = false;
      await manager.loadImage('$url?retry', cacheOnDisk: false);
      expect(requests, beforeFailure + 2);
      final before =
          await directory.list(recursive: true).where((f) => f is File).length;
      await manager.loadImage('$url?no-disk', cacheOnDisk: false);
      final after =
          await directory.list(recursive: true).where((f) => f is File).length;
      expect(after, before);
    }, _RealHttp());
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _RealHttp extends HttpOverrides {}
