import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 视频文件扫描器，负责遍历文件夹并统计视频文件
class VideoFileScanner {
  static const List<String> _videoExtensions = ['.mp4', '.mkv'];
  
  /// 扫描单个文件夹，返回视频文件列表
  static Future<List<File>> scanFolder(String folderPath) async {
    if (kIsWeb) return [];
    
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      return [];
    }
    
    final List<File> videoFiles = [];
    
    try {
      await for (var entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          String extension = p.extension(entity.path).toLowerCase();
          if (_videoExtensions.contains(extension)) {
            videoFiles.add(entity);
          }
        }
      }
    } catch (e) {
      debugPrint('VideoFileScanner: 扫描文件夹失败 $folderPath: $e');
      rethrow;
    }
    
    return videoFiles;
  }
  
  /// 统计文件夹中的视频文件数量（不实际读取文件列表，性能更好）
  static Future<int> countVideoFiles(String folderPath) async {
    if (kIsWeb) return 0;
    
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      return 0;
    }
    
    int count = 0;
    
    try {
      await for (var entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          String extension = p.extension(entity.path).toLowerCase();
          if (_videoExtensions.contains(extension)) {
            count++;
          }
        }
      }
    } catch (e) {
      debugPrint('VideoFileScanner: 统计文件失败 $folderPath: $e');
      return 0;
    }
    
    return count;
  }
  
  /// 批量统计多个文件夹的视频文件数量
  static Future<Map<String, int>> countVideoFilesInFolders(List<String> folderPaths) async {
    final Map<String, int> result = {};
    
    for (String folderPath in folderPaths) {
      result[folderPath] = await countVideoFiles(folderPath);
    }
    
    return result;
  }
  
  /// 检查文件是否为支持的视频格式
  static bool isVideoFile(String filePath) {
    String extension = p.extension(filePath).toLowerCase();
    return _videoExtensions.contains(extension);
  }
}