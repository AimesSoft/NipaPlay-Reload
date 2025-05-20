import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'android_storage_helper.dart'; // 导入Android存储帮助类

class StorageService {
  // 用户自定义存储路径的SharedPreferences键
  static const String _customStoragePathKey = 'custom_storage_path';
  
  // 当前使用的存储目录路径
  static String? _currentStoragePath;
  
  // 保存自定义存储路径
  static Future<bool> saveCustomStoragePath(String path) async {
    try {
      debugPrint('保存自定义存储路径: $path');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customStoragePathKey, path);
      _currentStoragePath = path;
      return true;
    } catch (e) {
      debugPrint('保存自定义存储路径失败: $e');
      return false;
    }
  }
  
  // 获取保存的自定义存储路径
  static Future<String?> getCustomStoragePath() async {
    if (_currentStoragePath != null) {
      return _currentStoragePath;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_customStoragePathKey);
      if (path != null && path.isNotEmpty) {
        _currentStoragePath = path;
        debugPrint('读取到保存的自定义存储路径: $path');
      }
      return path;
    } catch (e) {
      debugPrint('获取自定义存储路径失败: $e');
      return null;
    }
  }
  
  // 清除保存的自定义存储路径
  static Future<bool> clearCustomStoragePath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_customStoragePathKey);
      _currentStoragePath = null;
      debugPrint('已清除自定义存储路径');
      return true;
    } catch (e) {
      debugPrint('清除自定义存储路径失败: $e');
      return false;
    }
  }
  
  // 检查路径是否是有效的存储目录
  static Future<bool> isValidStorageDirectory(String path) async {
    try {
      // 针对Android平台的特殊处理
      if (Platform.isAndroid) {
        // 使用Android特定的权限检查
        final dirPerms = await AndroidStorageHelper.checkDirectoryPermissions(path);
        final canAccess = dirPerms['canRead'] == true && dirPerms['exists'] == true;
        
        if (!canAccess) {
          debugPrint('目录权限检查失败: 无法读取或不存在');
          return false;
        }
        
        // 检查是否有写入权限
        if (dirPerms['canWrite'] != true) {
          // Android 11+可能需要特殊处理
          final sdkVersion = await AndroidStorageHelper.getAndroidSDKVersion();
          if (sdkVersion >= 30) { // Android 11+
            // 检查是否有管理所有文件权限
            final hasManageStorage = await AndroidStorageHelper.hasManageExternalStoragePermission();
            if (!hasManageStorage) {
              debugPrint('目录没有写入权限，且没有管理所有文件权限');
              return false;
            }
            
            // 即使有MANAGE_EXTERNAL_STORAGE权限，某些目录仍可能受限
            // 尝试创建测试文件来确认
            try {
              final testFile = File('$path/test_write_permission.tmp');
              await testFile.writeAsString('test');
              await testFile.delete();
              return true;
            } catch (e) {
              debugPrint('有MANAGE_EXTERNAL_STORAGE权限但仍无法写入: $e');
              return false;
            }
          } else {
            debugPrint('目录没有写入权限');
            return false;
          }
        }
        
        return true;
      }
    
      // 非Android平台或Android特殊检查失败时的通用检查
      final dir = Directory(path);
      // 检查路径是否存在
      if (!await dir.exists()) {
        try {
          // 尝试创建目录
          await dir.create(recursive: true);
        } catch (e) {
          debugPrint('无法创建目录: $e');
          return false;
        }
      }
      
      // 创建临时文件来测试写入权限
      final testFile = File('${dir.path}/test_write_permission.tmp');
      try {
        await testFile.writeAsString('test');
        await testFile.delete();
        return true;
      } catch (e) {
        debugPrint('无法写入目录: $e');
        return false;
      }
    } catch (e) {
      debugPrint('检查存储目录失败: $e');
      return false;
    }
  }

  // 主应用存储目录
  static Future<Directory> getAppStorageDirectory() async {
    // 首先检查是否有自定义路径
    final customPath = await getCustomStoragePath();
    if (customPath != null && customPath.isNotEmpty) {
      final customDir = Directory(customPath);
      
      // 检查自定义目录是否可访问
      if (Platform.isAndroid) {
        final dirPerms = await AndroidStorageHelper.checkDirectoryPermissions(customPath);
        final canAccess = dirPerms['exists'] == true && dirPerms['canRead'] == true;
        
        if (canAccess) {
          debugPrint('使用自定义存储目录: ${customDir.path}');
          return customDir;
        } else {
          debugPrint('自定义路径存在但无法访问: ${customDir.path}, 权限状态: $dirPerms');
          // 此处不清除自定义路径，因为它可能是用户选择的路径，而只是当前无法访问
        }
      } else if (await customDir.exists()) {
        debugPrint('使用自定义存储目录: ${customDir.path}');
        return customDir;
      } else {
        try {
          // 尝试创建目录
          await customDir.create(recursive: true);
          debugPrint('已创建自定义存储目录: ${customDir.path}');
          return customDir;
        } catch (e) {
          debugPrint('无法使用自定义存储目录，回退到默认路径: $e');
        }
      }
    }
  
    // iOS始终使用应用文档目录
    if (Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    } 
    // Android优先使用外部存储
    else if (Platform.isAndroid) {
      try {
        // 获取SDK版本
        final sdkVersion = await AndroidStorageHelper.getAndroidSDKVersion();
        
        // 获取外部存储目录，即使没有权限也尝试
        final dirs = await getExternalStorageDirectories();
        if (dirs != null && dirs.isNotEmpty) {
          // 创建自定义目录名
          final customDir = Directory('${dirs[0].path}/NipaPlay');
          
          // 检查目录是否可用
          bool isAccessible = false;
          if (await customDir.exists()) {
            // 存在时验证权限
            final dirPerms = await AndroidStorageHelper.checkDirectoryPermissions(customDir.path);
            isAccessible = dirPerms['canRead'] == true; 
            debugPrint('外部存储目录已存在，权限检查: $dirPerms');
          } else {
            // 尝试创建并验证权限
            try {
              await customDir.create(recursive: true);
              isAccessible = true;
              debugPrint('已创建外部存储目录: ${customDir.path}');
            } catch (e) {
              debugPrint('无法创建外部存储目录: $e');
              isAccessible = false;
            }
          }
          
          if (isAccessible) {
            return customDir;
          } else {
            debugPrint('无法访问外部存储目录，降级到内部存储');
          }
        } else {
          debugPrint('无法获取外部存储目录，降级到内部存储');
        }
      } catch (e) {
        debugPrint('访问外部存储失败: $e，降级到内部存储');
      }
      
      // 降级到应用文档目录
      final internalDir = await getApplicationDocumentsDirectory();
      debugPrint('使用内部存储目录: ${internalDir.path}');
      return internalDir;
    } else {
      // 其他平台使用应用文档目录
      return getApplicationDocumentsDirectory();
    }
  }
  
  // 获取临时目录
  static Future<Directory> getTempDirectory() async {
    final appDir = await getAppStorageDirectory();
    final tempDir = Directory('${appDir.path}/temp');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir;
  }
  
  // 获取缓存目录
  static Future<Directory> getCacheDirectory() async {
    final appDir = await getAppStorageDirectory();
    final cacheDir = Directory('${appDir.path}/cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }
  
  // 获取下载目录
  static Future<Directory> getDownloadsDirectory() async {
    final appDir = await getAppStorageDirectory();
    final downloadsDir = Directory('${appDir.path}/downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir;
  }
  
  // 获取视频目录
  static Future<Directory> getVideosDirectory() async {
    final appDir = await getAppStorageDirectory();
    final videosDir = Directory('${appDir.path}/videos');
    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }
    return videosDir;
  }
} 