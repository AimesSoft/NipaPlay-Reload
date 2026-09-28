import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/remote_subtitle_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('same-name subtitles keep distinct cache paths and offline contents',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('subtitle_cache_');
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    server.listen((request) async {
      request.response.write(request.uri.path);
      await request.response.close();
    });
    SharedRemoteSubtitleCandidate candidate(String episode) =>
        SharedRemoteSubtitleCandidate(
          shareId: episode,
          fileName: 'zh.srt',
          subtitleUri:
              Uri.parse('http://127.0.0.1:$port/$episode/zh.srt'),
          authorizationHeader: null,
          isLikelyMatch: true,
          name: 'zh.srt',
          extension: '.srt',
        );
    try {
      final first = await RemoteSubtitleService.instance
          .ensureSubtitleCached(candidate('A'));
      final second = await RemoteSubtitleService.instance
          .ensureSubtitleCached(candidate('B'));
      expect(first, isNot(second));
      expect(await File(first).readAsString(), '/A/zh.srt');
      expect(await File(second).readAsString(), '/B/zh.srt');
      await server.close(force: true);
      expect(
          await RemoteSubtitleService.instance
              .ensureSubtitleCached(candidate('A')),
          first);
      expect(await File(first).readAsString(), '/A/zh.srt');
    } finally {
      await server.close(force: true);
      await StorageService.clearCustomStoragePath();
      PathProviderPlatform.instance = previousPaths;
      await dir.delete(recursive: true);
    }
  });
}
