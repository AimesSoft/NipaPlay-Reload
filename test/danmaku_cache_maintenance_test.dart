import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/utils/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('metadata cleanup migrates old caches and serializes clear/save',
      () async {
    final root = await Directory.systemTemp.createTemp('danmaku-maintenance-');
    StorageService.debugAppStorageDirectoryOverride = root;
    addTearDown(() async {
      StorageService.debugAppStorageDirectoryOverride = null;
      await root.delete(recursive: true);
    });
    final comments = List.generate(
        2000, (i) => {'time': i, 'content': 'line $i', 'type': 1, 'color': 0});
    await DanmakuCacheManager.saveDanmakuToCache('fresh', 20000, comments);
    final dir = Directory('${root.path}/cache/danmaku');
    final fresh = File('${dir.path}/danmaku_cache_fresh.json');
    expect(await File('${fresh.path}.meta').exists(), isTrue);
    expect((await File('${fresh.path}.meta').length()), lessThan(256));
    final expired = File('${dir.path}/danmaku_cache_old.json');
    await expired.writeAsString(
        jsonEncode({'timestamp': 0, 'animeId': 20000, 'comments': comments}));
    final legacy = File('${dir.path}/danmaku_cache_legacy.json');
    await legacy.writeAsString(jsonEncode({
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'animeId': 20000,
      'comments': comments
    }));
    final corrupt = File('${dir.path}/danmaku_cache_broken.json');
    await corrupt.writeAsString('{broken');
    await Future.wait([
      DanmakuCacheManager.clearExpiredCache(),
      DanmakuCacheManager.clearExpiredCache()
    ]);
    expect(await expired.exists(), isFalse);
    expect(await corrupt.exists(), isFalse);
    expect(await File('${legacy.path}.meta').exists(), isTrue);
    expect((await DanmakuCacheManager.getDanmakuFromCache('legacy'))!.length,
        2000);
    // Metadata is sufficient for cleanup even without a parseable payload.
    final stat = await fresh.stat();
    await fresh.writeAsString('x' * stat.size);
    await fresh.setLastModified(stat.modified);
    final metaFile = File('${fresh.path}.meta');
    final metadata = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    metadata['modified'] = (await fresh.stat()).modified.microsecondsSinceEpoch;
    await metaFile.writeAsString(jsonEncode(metadata));
    await DanmakuCacheManager.clearExpiredCache();
    expect(await fresh.exists(), isTrue);
    await Future.wait([
      DanmakuCacheManager.clearAllCache(),
      DanmakuCacheManager.saveDanmakuToCache('new', 20000, comments)
    ]);
    expect(await DanmakuCacheManager.getDanmakuFromCache('fresh'), isNull);
    expect(
        (await DanmakuCacheManager.getDanmakuFromCache('new'))!.length, 2000);
    await DanmakuCacheManager.clearAllCache();
    expect(await dir.list().length, 0);
  });
}
