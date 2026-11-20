import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TVPaths extends PathProviderPlatform {
  _TVPaths(this.cache);
  final String cache;

  @override
  Future<String?> getApplicationCachePath() async => cache;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      throw StateError('Documents is read-only on Apple TV');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TV history and library storage is writable without Documents',
      () async {
    final root = await Directory.systemTemp.createTemp('nipaplay_tv_storage_');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TVPaths('${root.path}/Caches');
    addTearDown(() async {
      PathProviderPlatform.instance = previous;
      await root.delete(recursive: true);
    });

    final directory = await StorageService.getTvOSStorageDirectory();
    final history = File('${directory.path}/history.json');
    await history.writeAsString('{"position":42}');
    final reopened = await StorageService.getTvOSStorageDirectory();
    expect(await File('${reopened.path}/history.json').readAsString(),
        '{"position":42}');
  });
}
