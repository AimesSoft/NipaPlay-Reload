import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

// 用于在 isolate 中处理图片的函数
Future<Uint8List> _processImageInIsolate(Uint8List imageData) async {
  // 使用image包解码和压缩图片
  final image = img.decodeImage(imageData);
  if (image == null) {
    throw Exception('Failed to decode image');
  }

  // 计算目标尺寸
  const targetWidth = 512;
  final scale = targetWidth / image.width;
  final targetHeight = (image.height * scale).round();

  // 压缩图片
  final resizedImage = img.copyResize(
    image,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.linear,
  );

  // 将压缩后的图片转换为字节，使用最低的JPEG质量
  return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 100));
}

class ImageCacheManager {
  static final ImageCacheManager instance = ImageCacheManager._();
  final Map<String, ui.Image> _cache = {};
  final Map<String, Completer<ui.Image>> _loading = {};
  final Map<String, int> _refCount = {};
  static const int targetWidth = 512;
  Directory? _cacheDir;
  bool _isInitialized = false;
  bool _isClearingCache = false;

  ImageCacheManager._() {
    _initCacheDir();
  }

  Future<void> _initCacheDir() async {
    if (_isInitialized) return;
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
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
    if (!_isInitialized) {
      await _initCacheDir();
    }
    final key = _getCacheKey(url);
    return File('${_cacheDir!.path}/$key.jpg');
  }

  Future<ui.Image> loadImage(String url) async {
    if (!_isInitialized) {
      await _initCacheDir();
    }
    // 如果图片已经在内存缓存中，增加引用计数并返回
    if (_cache.containsKey(url)) {
      _refCount[url] = (_refCount[url] ?? 0) + 1;
      return _cache[url]!;
    }

    // 如果图片正在加载中，等待加载完成
    if (_loading.containsKey(url)) {
      return _loading[url]!.future;
    }

    // 创建新的加载任务
    final completer = Completer<ui.Image>();
    _loading[url] = completer;

    try {
      // 检查本地缓存
      final cacheFile = await _getCacheFile(url);
      if (await cacheFile.exists()) {
        // 从本地缓存加载
        final bytes = await cacheFile.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final image = frame.image;
        
        _cache[url] = image;
        _refCount[url] = 1;
        completer.complete(image);
        _loading.remove(url);
        return image;
      }

      // 下载图片
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to load image');
      }

      // 在单独的 isolate 中处理图片
      final compressedBytes = await compute(_processImageInIsolate, response.bodyBytes);

      // 保存到本地缓存
      await cacheFile.writeAsBytes(compressedBytes);

      // 解码压缩后的图片数据
      final codec = await ui.instantiateImageCodec(compressedBytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;

      // 存入内存缓存
      _cache[url] = uiImage;
      _refCount[url] = 1;
      completer.complete(uiImage);
      _loading.remove(url);

      return uiImage;
    } catch (e) {
      _loading.remove(url);
      completer.completeError(e);
      rethrow;
    }
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
    if (_refCount.containsKey(url)) {
      _refCount[url] = (_refCount[url]! - 1);
      if (_refCount[url]! <= 0) {
        _refCount.remove(url);
        if (_cache.containsKey(url)) {
          _cache[url]!.dispose();
          _cache.remove(url);
        }
      }
    }
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
  }

  Future<void> clearCache() async {
    if (_isClearingCache) return;
    _isClearingCache = true;

    try {
      // 清除内存缓存
      clear();

      // 清除本地文件缓存
      try {
        if (await _cacheDir!.exists()) {
          await _cacheDir!.delete(recursive: true);
          await _cacheDir!.create();
          //////debugPrint('已清除压缩图片缓存目录: ${_cacheDir!.path}');
        }
      } catch (e) {
        //////debugPrint('清除压缩图片缓存失败: $e');
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

      // 清除 Flutter 的图片缓存
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

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
    } finally {
      _isClearingCache = false;
    }
  }
} 