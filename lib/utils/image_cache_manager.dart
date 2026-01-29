import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart' if (dart.library.html) 'package:nipaplay/utils/mock_path_provider.dart';
import 'package:image/image.dart' as img;
import 'dart:io' if (dart.library.io) 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'storage_service.dart';

// 用于在 isolate 中处理图片的函数
Future<Uint8List> _processImageInIsolate(Uint8List imageData) async {
  // 使用image包解码图片
  final image = img.decodeImage(imageData);
  if (image == null) {
    throw Exception('Failed to decode image');
  }

  // 直接返回原始图片数据
  return imageData;
}

class ImageCacheManager {
  static final ImageCacheManager instance = ImageCacheManager._();
  final Map<String, ui.Image> _cache = {};
  final Map<String, Completer<ui.Image>> _loading = {};
  final Map<String, int> _refCount = {};
  final Map<String, DateTime> _lastAccessed = {}; // 跟踪图片最后访问时间
  static const Duration _maxCacheAge = Duration(minutes: 10); // 最大缓存时间
  static const Duration _diskCleanupInterval = Duration(hours: 12);
  static const Duration _compressedImageMaxAge = Duration(days: 30);
  static const Duration _thumbnailMaxAge = Duration(days: 30);
  static const Duration _timelineThumbnailMaxAge = Duration(days: 14);
  Directory? _cacheDir;
  bool _isInitialized = false;
  bool _isClearingCache = false;
  Timer? _cleanupTimer;
  DateTime? _lastDiskCleanupAt;

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
            
            _cache[cacheKey] = image;
            _refCount[cacheKey] = 1;
            _lastAccessed[cacheKey] = DateTime.now();
            completer.complete(image);
            return; // 加载成功，退出IIFE
          }
        }

        // 从网络下载
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('Failed to load image with status code ${response.statusCode}');
        }

        // 在单独的 isolate 中处理图片
        final processedBytes = await compute(_processImageInIsolate, response.bodyBytes);

        // 保存到本地缓存 (只保存原图)
        if (!kIsWeb) {
          final cacheFile = await _getCacheFile(url);
          await cacheFile.writeAsBytes(processedBytes);
        }

        // 解码图片数据
        final codec = await ui.instantiateImageCodec(
          processedBytes,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
        final frame = await codec.getNextFrame();
        final uiImage = frame.image;

        // 存入内存缓存
        _cache[cacheKey] = uiImage;
        _refCount[cacheKey] = 1;
        _lastAccessed[cacheKey] = DateTime.now();
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

  Future<void> preloadImages(List<String> urls) async {
    final failedUrls = <String>[];
    final futures = <Future>[];
    
    for (final url in urls) {
      try {
        // 检查 URL 是否有效
        if (url.isEmpty || url == 'assets/backempty.png' || url == 'assets/backEmpty.png') {
          //////debugPrint('跳过无效的图片 URL: $url');
          continue;
        }

        // 创建加载任务
        final future = loadImage(url).catchError((e) {
          //////debugPrint('预加载图片失败: $url, 错误: $e');
          failedUrls.add(url);
        });
        futures.add(future);
      } catch (e) {
        //////debugPrint('预加载图片时发生错误: $url, 错误: $e');
        failedUrls.add(url);
      }
    }

    // 等待所有图片加载完成
    await Future.wait(futures, eagerError: false);

    if (failedUrls.isNotEmpty) {
      //////debugPrint('以下图片预加载失败:');
      for (final url in failedUrls) {
        //////debugPrint('- $url');
      }
    }
  }

  void releaseImage(String url) {
    // 简化释放逻辑，不立即释放图片，由定期清理处理
    if (_refCount.containsKey(url)) {
      _refCount[url] = (_refCount[url]! - 1);
      if (_refCount[url]! <= 0) {
        _refCount.remove(url);
        // 标记最后访问时间为过去，让定期清理处理
        _lastAccessed[url] = DateTime.now().subtract(const Duration(hours: 1));
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
    
    // 安全释放过期图片
    for (final url in expiredUrls) {
      try {
        final image = _cache[url];
        if (image != null) {
          image.dispose();
          _cache.remove(url);
        }
        _lastAccessed.remove(url);
        _refCount.remove(url);
      } catch (e) {
        // 图片已被释放或其他错误，仅移除引用
        _cache.remove(url);
        _lastAccessed.remove(url);
        _refCount.remove(url);
      }
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
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  Future<void> clearCache() async {
    if (_isClearingCache) return;
    _isClearingCache = true;

    try {
      // 清除内存缓存
      clear();

      if (!kIsWeb) {
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

        // 清除 cached_network_image 的缓存
        try {
          final cacheDir = await getTemporaryDirectory();
          final imageCacheDir = Directory('${cacheDir.path}/cached_network_image');
          
          if (await imageCacheDir.exists()) {
            await imageCacheDir.delete(recursive: true);
            //////debugPrint('已清除 cached_network_image 缓存目录: ${imageCacheDir.path}');
          }
        } catch (e) {
          //////debugPrint('清除 cached_network_image 缓存失败: $e');
        }

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

        // 清除所有临时文件
        try {
          final cacheDir = await getTemporaryDirectory();
          final files = await cacheDir.list().toList();
          for (var file in files) {
            if (file is File || file is Directory) {
              await file.delete(recursive: true);
            }
          }
          //////debugPrint('已清除所有临时文件: ${cacheDir.path}');
        } catch (e) {
          //////debugPrint('清除临时文件失败: $e');
        }
      }

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
