import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ImageCacheManager {
  static final ImageCacheManager instance = ImageCacheManager._();
  final Map<String, ui.Image> _cache = {};
  final Map<String, Completer<ui.Image>> _loading = {};

  ImageCacheManager._();

  Future<ui.Image> loadImage(String url) async {
    // 如果图片已经在缓存中，直接返回
    if (_cache.containsKey(url)) {
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
      // 下载图片数据
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to load image');
      }

      // 解码图片数据
      final codec = await ui.instantiateImageCodec(response.bodyBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // 存入缓存
      _cache[url] = image;
      completer.complete(image);
      _loading.remove(url);

      return image;
    } catch (e) {
      _loading.remove(url);
      completer.completeError(e);
      rethrow;
    }
  }

  Future<void> preloadImages(List<String> urls) async {
    for (final url in urls) {
      try {
        await loadImage(url);
      } catch (e) {
        //print('预加载图片失败: $e');
        // 继续处理下一个图片
        continue;
      }
    }
  }

  void clear() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _loading.clear();
  }

  Future<void> clearCache() async {
    // 清除内存缓存
    clear();

    // 清除 cached_network_image 的缓存
    try {
      final cacheDir = await getTemporaryDirectory();
      final imageCacheDir = Directory('${cacheDir.path}/cached_network_image');
      
      if (await imageCacheDir.exists()) {
        await imageCacheDir.delete(recursive: true);
        print('已清除 cached_network_image 缓存目录: ${imageCacheDir.path}');
      }
    } catch (e) {
      print('清除 cached_network_image 缓存失败: $e');
    }

    // 清除自定义图片缓存
    try {
      final cacheDir = await getTemporaryDirectory();
      final imageCacheDir = Directory('${cacheDir.path}/image_cache');
      
      if (await imageCacheDir.exists()) {
        await imageCacheDir.delete(recursive: true);
        print('已清除自定义图片缓存目录: ${imageCacheDir.path}');
      }
    } catch (e) {
      print('清除自定义图片缓存失败: $e');
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
      print('已清除所有临时文件: ${cacheDir.path}');
    } catch (e) {
      print('清除临时文件失败: $e');
    }
  }
} 