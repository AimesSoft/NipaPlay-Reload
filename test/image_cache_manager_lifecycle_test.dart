import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 只覆写"文档目录"，让 [StorageService] 把图片缓存落在测试自己的临时目录里。
///
/// 复用 test/media_server_playback_sync_user_agent_test.dart 里同一个做法。
class _TempDocumentsPathProvider extends PathProviderPlatform {
  _TempDocumentsPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// 现场画一张 1x1 PNG。
///
/// 不硬编码 base64：手写的字符串一旦不合法，失败信息是
/// "Codec failed to produce an image"，会让人以为是缓存逻辑坏了。
Future<Uint8List> _drawOnePixelPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 1, 1),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 与 ImageCacheManager._evictionProtectionWindow（2 秒）保持余量。
const Duration _pastProtectionWindow = Duration(milliseconds: 2200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform previousPathProvider;
  late Directory tempDir;
  late Uint8List pngBytes;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('nipaplay_icm_test');
    previousPathProvider = PathProviderPlatform.instance;
    // 必须赶在第一次访问 ImageCacheManager.instance 之前换掉：
    // 它的构造函数会立刻按当时的 PathProvider 决定缓存目录。
    PathProviderPlatform.instance = _TempDocumentsPathProvider(tempDir.path);
    pngBytes = await _drawOnePixelPng();
  });

  setUp(() async {
    // 单例的缓存目录只初始化一次，所以所有用例共用同一个临时目录，
    // 每个用例开始前把内存里的东西清干净即可。
    ImageCacheManager.instance.clear();
  });

  tearDownAll(() async {
    ImageCacheManager.instance.clear();
    PathProviderPlatform.instance = previousPathProvider;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 把一张 PNG 预置成磁盘缓存，这样 loadImage 不会去碰网络。
  Future<void> seedDiskCache(String url) async {
    final appDir = await StorageService.getAppStorageDirectory();
    final cacheDir = Directory('${appDir.path}/compressed_images');
    await cacheDir.create(recursive: true);
    final key = sha256.convert(utf8.encode(url)).toString();
    await File('${cacheDir.path}/$key.jpg').writeAsBytes(pngBytes);
  }

  test('字节预算淘汰只丢索引，不释放正在显示的句柄', () async {
    final originalBudget = ImageCacheManager.maxBytes;
    ImageCacheManager.maxBytes = 1; // 存进任何一张都超预算，逼出淘汰路径
    try {
      const urlA = 'https://example.com/budget-a.png';
      const urlB = 'https://example.com/budget-b.png';
      await seedDiskCache(urlA);
      await seedDiskCache(urlB);

      // 刚存入的条目受 protectKey 保护，不会被自己触发的那次淘汰杀掉。
      final imageA = await ImageCacheManager.instance.loadImage(urlA);
      expect(ImageCacheManager.instance.currentCacheCount, 1);
      expect(imageA.debugDisposed, isFalse);

      // 等过保护窗，A 才会成为可淘汰对象。
      await Future<void>.delayed(_pastProtectionWindow);

      final imageB = await ImageCacheManager.instance.loadImage(urlB);
      expect(ImageCacheManager.instance.currentCacheCount, 1);
      // 被淘汰的是 A 的缓存索引，句柄必须留着：屏幕上可能正用它画着。
      expect(imageA.debugDisposed, isFalse);
      expect(imageB.debugDisposed, isFalse);
    } finally {
      ImageCacheManager.maxBytes = originalBudget;
    }
  });

  test('前台内存警告只清索引，不动屏幕上正在显示的句柄', () async {
    const url = 'https://example.com/foreground.png';
    await seedDiskCache(url);
    final image = await ImageCacheManager.instance.loadImage(url);
    expect(ImageCacheManager.instance.currentCacheCount, 1);

    await Future<void>.delayed(_pastProtectionWindow);
    final generation = ImageCacheManager.instance.lifecycleGeneration.value;
    ImageCacheManager.instance.handleMemoryPressure();

    expect(ImageCacheManager.instance.currentCacheCount, 0);
    expect(image.debugDisposed, isFalse);
    // 句柄没被释放，就不该通知组件放下引用，否则画面会白白变空。
    expect(ImageCacheManager.instance.lifecycleGeneration.value, generation);
  });

  test('退到后台释放句柄并通知组件放下引用', () async {
    const url = 'https://example.com/background.png';
    await seedDiskCache(url);
    final image = await ImageCacheManager.instance.loadImage(url);

    await Future<void>.delayed(_pastProtectionWindow);
    final generation = ImageCacheManager.instance.lifecycleGeneration.value;
    ImageCacheManager.instance.handleMemoryPressure(releaseHandles: true);

    expect(image.debugDisposed, isTrue);
    // 通知组件：手里的句柄已经失效，必须放下，回前台再重新加载。
    expect(
      ImageCacheManager.instance.lifecycleGeneration.value,
      generation + 1,
    );
  });

  test('touch 让正在显示的图片不再是最久未访问的那一个', () async {
    final originalBudget = ImageCacheManager.maxBytes;
    ImageCacheManager.maxBytes = 1;
    try {
      const urlA = 'https://example.com/touch-a.png';
      const urlB = 'https://example.com/touch-b.png';
      await seedDiskCache(urlA);
      await seedDiskCache(urlB);

      final imageA = await ImageCacheManager.instance.loadImage(urlA);
      await Future<void>.delayed(_pastProtectionWindow);

      // A 在屏幕上重新绘制了一次，重新变成"刚被访问过"。
      ImageCacheManager.instance.touch(urlA);

      // 此时存入 B：A 仍在保护窗内，不该被选为淘汰对象。
      final imageB = await ImageCacheManager.instance.loadImage(urlB);

      expect(ImageCacheManager.instance.currentCacheCount, 2);
      expect(imageA.debugDisposed, isFalse);
      expect(imageB.debugDisposed, isFalse);
    } finally {
      ImageCacheManager.maxBytes = originalBudget;
    }
  });
}
