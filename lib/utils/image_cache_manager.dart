import 'package:cached_network_image/cached_network_image.dart';
import 'package:nipaplay/widgets/media_server_network_image.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart'
    if (dart.library.html) 'package:nipaplay/utils/mock_path_provider.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';

class ImageCacheManager {
  static final ImageCacheManager instance = ImageCacheManager._();
  final Map<String, ui.Image> _cache = {};
  final Map<String, Completer<ui.Image>> _loading = {};
  final Map<String, int> _refCount = {};
  final Map<String, DateTime> _lastAccessed = {}; // 跟踪图片最后访问时间

  /// 每张缓存图片的估算字节数，以及总量。
  /// 解码后的 ui.Image 像素位于 native/external 内存，不受 Dart GC 管理，
  /// 在 32 位设备（低端安卓电视）上必须有硬上限，否则地址空间会被耗尽。
  final Map<String, int> _bytes = {};
  int _totalBytes = 0;

  /// 默认内存上限：低内存设备更保守。
  static int get _defaultMaxBytes {
    if (kIsWeb) return 32 * 1024 * 1024;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // 32 位低端电视/盒子按低内存设备处理。
        return 32 * 1024 * 1024;
      }
    } catch (_) {
      // defaultTargetPlatform 在极端早期阶段可能不可用，退回默认值。
    }
    return 64 * 1024 * 1024;
  }

  /// 当前内存预算，测试可覆盖。
  static int maxBytes = _defaultMaxBytes;

  /// 生命周期代际：缓存里的句柄被主动释放、或 App 回到前台时自增。
  ///
  /// [CachedNetworkImageWidget] 监听它。收到通知时看当前生命周期：
  /// 不在前台，说明自己手里的句柄已经被释放，必须同步放下引用，否则回前台
  /// 会画出空白；已回到前台，则重新加载一次（磁盘缓存兜底，不产生网络请求）。
  final ValueNotifier<int> lifecycleGeneration = ValueNotifier<int>(0);

  static const Duration _maxCacheAge = Duration(minutes: 10); // 最大缓存时间
  static const Duration _evictionProtectionWindow = Duration(seconds: 2);
  static const Duration _diskCleanupInterval = Duration(hours: 12);
  static const Duration _compressedImageMaxAge = Duration(days: 30);
  static const Duration _thumbnailMaxAge = Duration(days: 30);
  static const Duration _timelineThumbnailMaxAge = Duration(days: 14);
  Directory? _cacheDir;
  bool _isInitialized = false;
  bool _isClearingCache = false;
  Timer? _cleanupTimer;
  DateTime? _lastDiskCleanupAt;

  /// 当前缓存占用的估算字节数（测试与调试用）。
  int get currentCacheBytes => _totalBytes;

  /// 当前缓存的图片张数（测试与调试用）。
  int get currentCacheCount => _cache.length;

  /// 估算一张解码后位图的字节数，向上取整到 4 字节像素对齐。
  static int _estimateImageBytes(ui.Image image) {
    final int stride = ((image.width * 4) + 3) & ~3;
    return stride * image.height;
  }

  ImageCacheManager._() {
    _initCacheDir();
    _startPeriodicCleanup();
  }

  Future<void> _initCacheDir() async {
    if (kIsWeb || _isInitialized) return;

    try {
      final appDir = await StorageService.getAppStorageDirectory();
      _cacheDir = Directory('${appDir.path}/compressed_images');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      _isInitialized = true;
    } catch (e) {
      //////debugPrint('初始化缓存目录失败: $e');
      rethrow;
    }
  }

  String _getCacheKey(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<File> _getCacheFile(String url) async {
    if (!_isInitialized && !kIsWeb) {
      await _initCacheDir();
    }
    final key = _getCacheKey(url);
    return File('${_cacheDir?.path ?? 'web_cache'}/$key.jpg');
  }

  String _getCacheKeyWithDimensions(String url, int? width, int? height) {
    if (width == null && height == null) return url;
    return '${url}_w${width ?? 0}_h${height ?? 0}';
  }

  ui.Image? getCachedImage(String url, {int? targetWidth, int? targetHeight}) {
    final cacheKey = _getCacheKeyWithDimensions(url, targetWidth, targetHeight);
    final cachedImage = _cache[cacheKey];
    if (cachedImage != null) {
      _lastAccessed[cacheKey] = DateTime.now();
    }
    return cachedImage;
  }

  /// 标记某张图片"此刻正在被显示"。
  ///
  /// 由 [CachedNetworkImageWidget] 在 build 时调用。LRU 淘汰只看
  /// [_lastAccessed]，而它只在缓存命中或新存入时更新 —— 静止显示在屏幕上的
  /// 图片不会再走命中路径，于是会慢慢变成"最久未访问"并被淘汰，
  /// 释放掉一个正在绘制的句柄。每帧标记一次，"看得见的"就永远比"滚出去的"新。
  void touch(String url, {int? targetWidth, int? targetHeight}) {
    final cacheKey = _getCacheKeyWithDimensions(url, targetWidth, targetHeight);
    if (_lastAccessed.containsKey(cacheKey)) {
      _lastAccessed[cacheKey] = DateTime.now();
    }
  }

  Future<ui.Image> loadImage(
    String url, {
    int? targetWidth,
    int? targetHeight,
    bool forceRefresh = false,
  }) async {
    if (!_isInitialized && !kIsWeb) {
      await _initCacheDir();
    }

    final cacheKey = _getCacheKeyWithDimensions(url, targetWidth, targetHeight);

    // 如果图片已经在内存缓存中，更新访问时间并增加引用计数
    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      _lastAccessed[cacheKey] = DateTime.now();
      _refCount[cacheKey] = (_refCount[cacheKey] ?? 0) + 1;
      return _cache[cacheKey]!;
    }

    // 如果图片正在加载中，等待加载完成
    if (_loading.containsKey(cacheKey)) {
      return _loading[cacheKey]!.future;
    }

    // 创建新的加载任务
    final completer = Completer<ui.Image>();
    _loading[cacheKey] = completer;

    // 使用一个异步的IIFE（立即执行的函数表达式）来执行加载逻辑
    () async {
      try {
        // 检查本地缓存 (本地缓存文件本身不区分尺寸，只存原图数据)
        // 我们从本地读取原图数据，然后按需解码
        if (!forceRefresh && !kIsWeb) {
          final cacheFile = await _getCacheFile(url); // 文件名只跟URL有关
          if (await cacheFile.exists()) {
            final bytes = await cacheFile.readAsBytes();
            final codec = await ui.instantiateImageCodec(
              bytes,
              targetWidth: targetWidth,
              targetHeight: targetHeight,
            );
            final frame = await codec.getNextFrame();
            final image = frame.image;

            _store(cacheKey, image);
            completer.complete(image);
            return; // 加载成功，退出IIFE
          }
        }

        // 从网络下载
        final downloadedBytes = await loadNetworkImageBytes(Uri.parse(url));

        // 保存到本地缓存 (只保存原图数据)
        //
        // 注意：这里曾经先用 package:image 在 compute isolate 里完整解码一次，
        // 目的只是"校验图片"，然后丢弃结果、原样返回原始字节。纯 Dart 解码一张
        // 1080p JPEG 在低端设备上要几百毫秒并产生一次整图 RGBA 分配，加上
        // isolate 启动和字节缓冲跨 isolate 拷贝，产出为零。真正的解码由下面
        // instantiateImageCodec 完成，它本身就是流式的，也能做降采样。
        if (!kIsWeb) {
          final cacheFile = await _getCacheFile(url);
          await cacheFile.writeAsBytes(downloadedBytes);
        }

        // 解码图片数据
        final codec = await ui.instantiateImageCodec(
          downloadedBytes,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
        final frame = await codec.getNextFrame();
        final uiImage = frame.image;

        // 存入内存缓存
        _store(cacheKey, uiImage);
        completer.complete(uiImage);
      } catch (e) {
        // 如果发生任何错误，都通过completer报告
        completer.completeError(e);
      } finally {
        // 无论成功或失败，都从_loading中移除
        _loading.remove(cacheKey);
      }
    }();

    // 立即返回completer.future
    return completer.future;
  }

  /// 记录一张新解码的图片并维护字节预算。
  void _store(String cacheKey, ui.Image image) {
    _dropBytes(cacheKey);
    _cache[cacheKey] = image;
    _refCount[cacheKey] = 1;
    _lastAccessed[cacheKey] = DateTime.now();
    _bytes[cacheKey] = _estimateImageBytes(image);
    _totalBytes += _bytes[cacheKey]!;
    _enforceByteBudget(protectKey: cacheKey);
  }

  /// 从字节统计中移除一个键（不 dispose，由调用方决定）。
  void _dropBytes(String cacheKey) {
    final removed = _bytes.remove(cacheKey);
    if (removed != null) {
      _totalBytes -= removed;
      if (_totalBytes < 0) _totalBytes = 0;
    }
  }

  /// 从缓存索引里移除一张图片。
  ///
  /// [disposeImage] 为 true 时才释放句柄。调用方必须确认没有 widget 仍持有它：
  /// 字节预算淘汰和前台内存警告都会碰到"屏幕上看不见但组件还没销毁"的图片，
  /// 这种情况只能丢索引，让 Dart GC 在最后一个引用消失后回收 native 像素。
  void _disposeEntry(String cacheKey, {bool disposeImage = true}) {
    final image = _cache.remove(cacheKey);
    _dropBytes(cacheKey);
    _refCount.remove(cacheKey);
    _lastAccessed.remove(cacheKey);
    if (disposeImage && image != null) {
      try {
        image.dispose();
      } catch (_) {
        // 已被释放或正被其它层持有，忽略即可。
      }
    }
  }

  /// 超出字节预算时按 LRU 淘汰。
  ///
  /// 关键点：必须无视 `_refCount`。历史实现里 refCount 只在**缓存命中**时递增，
  /// 而唯一的递减点几乎从不被调用，因此 refCount 只增不减，任何"仅淘汰 refCount<=0"
  /// 的策略在真实使用中等同于"永不淘汰"，最终耗尽 32 位设备的地址空间。
  /// 这里改为以最后访问时间为准的 LRU；最近被访问过的图片（很可能正在被绘制）
  /// 受到 [_evictionProtectionWindow] 保护。
  void _enforceByteBudget({String? protectKey}) {
    final budget = maxBytes;
    if (budget <= 0) return;
    if (_totalBytes <= budget) return;

    final now = DateTime.now();
    final candidates = <String>[];
    for (final key in _cache.keys) {
      // 刚存入的条目不能由它自己触发的那次淘汰杀掉：此刻它还在 _loading 里
      // （要等 finally 才移除），会被判定成"随时可淘汰"；若它恰好是唯一候选，
      // 就会把刚解码好的图立刻释放，再通过 completer 交给调用方一个失效句柄。
      if (key == protectKey) continue;
      final lastAccessed = _lastAccessed[key];
      final isRecentlyUsed = lastAccessed != null &&
          now.difference(lastAccessed) < _evictionProtectionWindow;
      // 正在加载中的条目没有句柄被外部持有，随时可淘汰。
      if (!isRecentlyUsed || _loading.containsKey(key)) {
        candidates.add(key);
      }
    }

    // 最久未访问的先淘汰，配平到预算的 80%，避免每存一张就淘汰一次。
    candidates.sort((a, b) {
      final la = _lastAccessed[a];
      final lb = _lastAccessed[b];
      if (la == null && lb == null) return 0;
      if (la == null) return -1;
      if (lb == null) return 1;
      return la.compareTo(lb);
    });

    final target = (budget * 0.8).round();
    for (final key in candidates) {
      if (_totalBytes <= target) break;
      // 只丢索引：这些图片可能仍在屏幕上显示，句柄交给 GC 回收。
      _disposeEntry(key, disposeImage: false);
    }
  }

  /// 系统内存压力下的紧急释放：只保留最近仍在使用的少量图片。
  ///
  /// 由 App 生命周期（didHaveMemoryPressure / onTrimMemory）调用。
  ///
  /// [releaseHandles] 区分两种场景：
  /// - false（前台收到内存警告）：只清缓存索引。屏幕上的图片仍握着自己的句柄，
  ///   画面不会突然变白，省下的是下一次加载才需要的内存。
  /// - true（退到后台）：连句柄一起释放，并通知图片组件放下引用 —— 用户看不见，
  ///   这时把像素真正还给系统才是安全的；回前台由组件自己重新加载。
  void handleMemoryPressure({bool releaseHandles = false}) {
    if (kIsWeb) return;
    final now = DateTime.now();
    final evictable = <String>[];
    for (final key in _cache.keys) {
      final lastAccessed = _lastAccessed[key];
      final isRecentlyUsed = lastAccessed != null &&
          now.difference(lastAccessed) < _evictionProtectionWindow;
      if (!isRecentlyUsed) evictable.add(key);
    }
    for (final key in evictable) {
      _disposeEntry(key, disposeImage: releaseHandles);
    }
    if (releaseHandles && evictable.isNotEmpty) {
      // 句柄已经失效，通知组件放下引用。
      lifecycleGeneration.value++;
    }
  }

  Future<void> preloadImages(List<String> urls) async {
    final failedUrls = <String>[];
    final futures = <Future>[];

    for (final url in urls) {
      try {
        // 检查 URL 是否有效
        if (url.isEmpty ||
            url == 'assets/backempty.png' ||
            url == 'assets/backEmpty.png') {
          //////debugPrint('跳过无效的图片 URL: $url');
          continue;
        }

        // 创建加载任务
        final future = loadImage(url).then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            //////debugPrint('预加载图片失败: $url, 错误: $error');
            failedUrls.add(url);
          },
        );
        futures.add(future);
      } catch (e) {
        //////debugPrint('预加载图片时发生错误: $url, 错误: $e');
        failedUrls.add(url);
      }
    }

    // 等待所有图片加载完成
    await Future.wait(futures, eagerError: false);

    if (failedUrls.isNotEmpty) {
      //////debugPrint('以下图片预加载失败: ${failedUrls.length} 张');
    }
  }

  /// 递减某张图片的引用计数。
  ///
  /// [url] 是原始 URL；同一 URL 可能以多个降采样尺寸缓存
  /// （见 [_getCacheKeyWithDimensions]），因此需要匹配所有尺寸变体，
  /// 否则 releaseImage 会命中不到条目、计数永远不回落。
  void releaseImage(String url) {
    final prefix = '${url}_w';
    final keys = <String>{
      if (_refCount.containsKey(url) || _cache.containsKey(url)) url,
      for (final key in _refCount.keys)
        if (key.startsWith(prefix)) key,
    };

    for (final key in keys) {
      final count = _refCount[key];
      if (count == null) continue;
      final next = count - 1;
      if (next <= 0) {
        _refCount.remove(key);
        // 标记为久未访问，让字节预算与定期清理优先处理它。
        _lastAccessed[key] = DateTime.now().subtract(const Duration(hours: 1));
      } else {
        _refCount[key] = next;
      }
    }
  }

  // 定期清理机制
  void _startPeriodicCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _cleanupExpiredImages();
      _maybeCleanupDiskCaches();
    });
    unawaited(_cleanupDiskCaches(force: true));
  }

  void _cleanupExpiredImages() {
    final now = DateTime.now();
    final expiredUrls = <String>[];

    for (final entry in _lastAccessed.entries) {
      final url = entry.key;
      final lastAccessed = entry.value;

      // 检查是否过期且没有引用
      if (now.difference(lastAccessed) > _maxCacheAge &&
          (_refCount[url] ?? 0) <= 0) {
        expiredUrls.add(url);
      }
    }

    // 安全释放过期图片（_disposeEntry 同步维护字节统计）
    for (final url in expiredUrls) {
      _disposeEntry(url);
    }
  }

  void _maybeCleanupDiskCaches() {
    if (kIsWeb || _isClearingCache) return;
    final now = DateTime.now();
    final lastCleanup = _lastDiskCleanupAt;
    if (lastCleanup != null &&
        now.difference(lastCleanup) < _diskCleanupInterval) {
      return;
    }
    unawaited(_cleanupDiskCaches());
  }

  Future<void> _cleanupDiskCaches({bool force = false}) async {
    if (kIsWeb || _isClearingCache) return;

    final now = DateTime.now();
    if (!force &&
        _lastDiskCleanupAt != null &&
        now.difference(_lastDiskCleanupAt!) < _diskCleanupInterval) {
      return;
    }
    _lastDiskCleanupAt = now;

    try {
      final appDir = await StorageService.getAppStorageDirectory();
      final compressedDir = Directory('${appDir.path}/compressed_images');
      final thumbnailsDir = Directory('${appDir.path}/thumbnails');
      final timelineDir = Directory('${appDir.path}/timeline_thumbnails');

      await _cleanupDirectoryByAge(compressedDir, _compressedImageMaxAge);
      await _cleanupDirectoryByAge(thumbnailsDir, _thumbnailMaxAge);
      await _cleanupDirectoryByAge(
        timelineDir,
        _timelineThumbnailMaxAge,
        removeEmptyDirs: true,
      );
    } catch (e) {
      //////debugPrint('清理磁盘图片缓存失败: $e');
    }
  }

  Future<void> _cleanupDirectoryByAge(
    Directory dir,
    Duration maxAge, {
    bool removeEmptyDirs = false,
  }) async {
    if (!await dir.exists()) return;
    final now = DateTime.now();
    final dirs = <Directory>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          if (now.difference(stat.modified) > maxAge) {
            await entity.delete();
          }
        } catch (_) {}
      } else if (removeEmptyDirs && entity is Directory) {
        dirs.add(entity);
      }
    }

    if (!removeEmptyDirs) return;
    dirs.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final subDir in dirs) {
      try {
        if (await subDir.list(followLinks: false).isEmpty) {
          await subDir.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _deleteDirectoryIfExists(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  void clear() {
    // 先释放所有图片资源
    for (final image in _cache.values) {
      try {
        image.dispose();
      } catch (e) {
        //////debugPrint('释放图片资源时出错: $e');
      }
    }
    // 清除缓存
    _cache.clear();
    _loading.clear();
    _refCount.clear();
    _lastAccessed.clear();
    _bytes.clear();
    _totalBytes = 0;
    // 句柄全部释放了，通知组件放下引用，否则它们会一直画空白。
    lifecycleGeneration.value++;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  Future<void> clearCache() async {
    if (_isClearingCache) return;
    _isClearingCache = true;

    try {
      // 清除内存缓存
      //
      // 这是用户显式触发的"清空缓存"，必须真正清空：历史实现跳过所有
      // refCount > 0 的条目，而 refCount 只增不减，导致用户点了清空之后
      // 内存占用毫无变化。此处改为全部释放，并同步重置字节统计。
      final keys = _cache.keys.toList();
      for (final key in keys) {
        _disposeEntry(key);
      }
      _refCount.clear();
      _lastAccessed.clear();
      _bytes.clear();
      _totalBytes = 0;

      if (!kIsWeb) {
        await _initCacheDir();
        // 清除本地文件缓存
        try {
          if (_cacheDir != null && await _cacheDir!.exists()) {
            await _cacheDir!.delete(recursive: true);
            await _cacheDir!.create();
            //////debugPrint('已清除压缩图片缓存目录: ${_cacheDir!.path}');
          }
        } catch (e) {
          //////debugPrint('清除压缩图片缓存失败: $e');
        }

        // 清除播放器生成的缩略图缓存
        try {
          final appDir = await StorageService.getAppStorageDirectory();
          await _deleteDirectoryIfExists(
            Directory('${appDir.path}/thumbnails'),
          );
          await _deleteDirectoryIfExists(
            Directory('${appDir.path}/timeline_thumbnails'),
          );
        } catch (e) {
          //////debugPrint('清除缩略图缓存失败: $e');
        }

        await CachedNetworkImageProvider.defaultCacheManager.emptyCache();

        // 清除自定义图片缓存
        try {
          final cacheDir = await getTemporaryDirectory();
          final imageCacheDir = Directory('${cacheDir.path}/image_cache');

          if (await imageCacheDir.exists()) {
            await imageCacheDir.delete(recursive: true);
            //////debugPrint('已清除自定义图片缓存目录: ${imageCacheDir.path}');
          }
        } catch (e) {
          //////debugPrint('清除自定义图片缓存失败: $e');
        }

        // 临时目录可能是 Windows 全局 TEMP，包含正在使用的文件和其他
        // 应用的数据。图片清理只能访问上面明确属于本应用的图片目录。
      }

      clearMediaServerImageMemoryCache();
      // 清除 Flutter 的图片缓存
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (_cleanupTimer == null) {
        _startPeriodicCleanup();
      }
    } finally {
      _isClearingCache = false;
    }
  }
}
