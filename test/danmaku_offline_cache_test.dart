import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #1024：新番的弹幕缓存只有 2 小时新鲜期。过期后不能马上删除，
// 联网失败（离线）时要能回退使用，看过的集离线重播仍有弹幕。

void main() {
  // 测试绑定让所有 HTTP 请求返回 400，正好模拟联网取弹幕失败。
  TestWidgetsFlutterBinding.ensureInitialized();

  test('过了新鲜期的缓存保留下来，联网失败时回退使用', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('danmaku-offline-');
    StorageService.debugAppStorageDirectoryOverride = root;
    addTearDown(() async {
      StorageService.debugAppStorageDirectoryOverride = null;
      await root.delete(recursive: true);
    });

    final comments = List.generate(
        3, (i) => {'time': i, 'content': 'line $i', 'type': 1, 'color': 0});
    // 先正常写一次，让缓存目录和元数据就位。
    await DanmakuCacheManager.saveDanmakuToCache('warmup', 20000, comments);
    final dir = Directory('${root.path}/cache/danmaku');

    Future<File> writeCache(String episodeId, Duration age) async {
      final file = File('${dir.path}/danmaku_cache_$episodeId.json');
      await file.writeAsString(jsonEncode({
        'timestamp': DateTime.now().subtract(age).millisecondsSinceEpoch,
        'animeId': 20000, // 新番：新鲜期 2 小时
        'comments': comments,
      }));
      return file;
    }

    final stale = await writeCache('stale', const Duration(hours: 3));
    final ancient = await writeCache('ancient', const Duration(days: 40));

    // 过了新鲜期：默认读取不命中，允许过期时能读到。
    expect(await DanmakuCacheManager.getDanmakuFromCache('stale'), isNull);
    expect(
      await DanmakuCacheManager.getDanmakuFromCache('stale',
          allowExpired: true),
      hasLength(3),
    );

    // 清理只删超过保留期的文件。
    await DanmakuCacheManager.clearExpiredCache();
    expect(await stale.exists(), isTrue);
    expect(await ancient.exists(), isFalse);
    expect(
      await DanmakuCacheManager.getDanmakuFromCache('ancient',
          allowExpired: true),
      isNull,
    );

    // 已登录但联网失败时，getDanmaku 回退到过期缓存。
    await DandanplayService.saveLoginInfo('token', 'user', 'User');
    addTearDown(DandanplayService.clearLoginInfo);
    final result = await DandanplayService.getDanmaku('stale', 20000);
    expect(result['fromCache'], isTrue);
    expect(result['stale'], isTrue);
    expect(result['comments'], hasLength(3));

    // 没有任何缓存时照常报错。
    await expectLater(
      DandanplayService.getDanmaku('missing', 20000),
      throwsA(anything),
    );
  });
}
