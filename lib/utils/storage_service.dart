import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:path_provider/path_provider.dart' if (dart.library.html) 'package:nipaplay/utils/mock_path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'android_storage_helper.dart'; // 导入Android存储帮助类
import 'linux_storage_migration.dart'; // 导入Linux存储迁移
import 'macos_storage_migration.dart'; // 导入macOS存储迁移

class StorageService {
  // 用户自定义存储路径的SharedPreferences键
  static const String _customStoragePathKey = 'custom_storage_path';
  
  // 当前使用的存储目录路径
  static String? _currentStoragePath;
  
  // 保存自定义存储路径
  static Future<bool> saveCustomStoragePath(String path) async {
    if (kIsWeb) return false;
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
    if (kIsWeb) return null;
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
    if (kIsWeb) return false;
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
    if (kIsWeb) return false;
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
    if (kIsWeb) return Directory('web');
    // Linux平台特殊处理 - 使用XDG规范目录并处理迁移
    if (Platform.isLinux) {
      return _getLinuxStorageDirectory();
    }
    
    // 其他所有平台（iOS、Android、macOS、Windows）使用统一逻辑
    return _getUniversalStorageDirectory();
  }
  
  // 通用存储目录处理（除Linux外的所有平台）
  static Future<Directory> _getUniversalStorageDirectory() async {
    if (kIsWeb) return Directory('web');
    try {
      // macOS平台需要处理数据迁移
      if (Platform.isMacOS) {
        // 清除任何现有的自定义存储路径设置
    final customPath = await getCustomStoragePath();
    if (customPath != null && customPath.isNotEmpty) {
          debugPrint('检测到自定义存储路径: $customPath，将清除并使用默认路径');
          await clearCustomStoragePath();
        }
      
        // 检查是否需要迁移
        if (await MacOSStorageMigration.needsMigration()) {
          debugPrint('检测到macOS平台需要数据迁移，开始迁移...');
          final result = await MacOSStorageMigration.performMigration();
          if (result.success) {
            debugPrint('macOS数据迁移成功: ${result.message}');
          } else {
            debugPrint('macOS数据迁移失败: ${result.message}');
          }
        }
      }
      
      // Android平台先检查自定义路径和外部存储
      if (Platform.isAndroid) {
        // 检查是否有自定义路径
        final customPath = await getCustomStoragePath();
        if (customPath != null && customPath.isNotEmpty) {
          final customDir = Directory(customPath);
        final dirPerms = await AndroidStorageHelper.checkDirectoryPermissions(customPath);
        final canAccess = dirPerms['exists'] == true && dirPerms['canRead'] == true;
        
        if (canAccess) {
          debugPrint('使用自定义存储目录: ${customDir.path}');
          return customDir;
        } else {
          debugPrint('自定义路径存在但无法访问: ${customDir.path}, 权限状态: $dirPerms');
        }
        }
        
        // 尝试外部存储
        try {
        final dirs = await getExternalStorageDirectories();
        if (dirs != null && dirs.isNotEmpty) {
          final customDir = Directory('${dirs[0].path}/NipaPlay');
          
          bool isAccessible = false;
          if (await customDir.exists()) {
            final dirPerms = await AndroidStorageHelper.checkDirectoryPermissions(customDir.path);
            isAccessible = dirPerms['canRead'] == true; 
            debugPrint('外部存储目录已存在，权限检查: $dirPerms');
          } else {
            try {
              await customDir.create(recursive: true);
              isAccessible = true;
              debugPrint('已创建外部存储目录: ${customDir.path}');
            } catch (e) {
              debugPrint('无法创建外部存储目录: $e');
            }
          }
          
          if (isAccessible) {
            return customDir;
            }
          }
        } catch (e) {
          debugPrint('访问外部存储失败: $e');
          }
      }
      
      // 所有平台的最终默认路径：Documents/nipaplay
      final documentsDir = await getApplicationDocumentsDirectory();
      
      // iOS直接使用Documents目录
      if (Platform.isIOS) {
        return documentsDir;
      }
      
      // 其他平台使用Documents/nipaplay子目录
      final nipaplayDir = Directory('${documentsDir.path}/nipaplay');
      if (!await nipaplayDir.exists()) {
        await nipaplayDir.create(recursive: true);
        debugPrint('已创建应用子目录: ${nipaplayDir.path}');
      }
      
      return nipaplayDir;
      
    } catch (e) {
      debugPrint('通用存储目录处理出错: $e');
      // 最后的回退
      return getApplicationDocumentsDirectory();
    }
  }
  
  // Linux平台存储目录处理
  static Future<Directory> _getLinuxStorageDirectory() async {
    if (kIsWeb) return Directory('web');
    try {
      // 先检查是否需要迁移
      if (await LinuxStorageMigration.needsMigration()) {
        debugPrint('检测到Linux平台需要数据迁移，开始迁移...');
        final result = await LinuxStorageMigration.performMigration();
        if (result.success) {
          debugPrint('Linux数据迁移成功: ${result.message}');
        } else {
          debugPrint('Linux数据迁移失败: ${result.message}');
          // 即使迁移失败，也继续使用新目录，不要回退到Documents
        }
      }
      
      // 强制使用XDG规范的数据目录，确保目录存在
      final xdgDataDir = await LinuxStorageMigration.getXDGDataDirectory();
      final dir = Directory(xdgDataDir);
      
      // 确保目录存在
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        debugPrint('已创建XDG数据目录: $xdgDataDir');
      }
      
      return dir;
    } catch (e) {
      debugPrint('Linux存储目录处理出错: $e');
      
      // 即使出错也不回退到Documents，强制使用XDG目录
      try {
        final homeDir = Platform.environment['HOME'];
        if (homeDir != null && homeDir.isNotEmpty) {
          final fallbackDir = Directory('$homeDir/.local/share/NipaPlay');
          if (!await fallbackDir.exists()) {
            await fallbackDir.create(recursive: true);
          }
          debugPrint('使用回退XDG目录: ${fallbackDir.path}');
          return fallbackDir;
        }
      } catch (e2) {
        debugPrint('创建回退XDG目录也失败: $e2');
      }
      
      // 最后的最后才考虑Documents，但要警告
      debugPrint('⚠️ 警告：无法创建XDG目录，临时使用Documents目录');
      return getApplicationDocumentsDirectory();
    }
  }
  
  // 获取临时目录
  static Future<Directory> getTempDirectory() async {
    if (kIsWeb) return Directory('web/temp');
    final appDir = await getAppStorageDirectory();
    final tempDir = Directory('${appDir.path}/temp');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir;
  }
  
  // 获取缓存目录
  static Future<Directory> getCacheDirectory() async {
    if (kIsWeb) return Directory('web/cache');
    final appDir = await getAppStorageDirectory();
    final cacheDir = Directory('${appDir.path}/cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }
  
  // 获取下载目录
  static Future<Directory> getDownloadsDirectory() async {
    if (kIsWeb) return Directory('web/downloads');
    final appDir = await getAppStorageDirectory();
    final downloadsDir = Directory('${appDir.path}/downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir;
  }
  
  // 获取视频目录
  static Future<Directory> getVideosDirectory() async {
    if (kIsWeb) return Directory('web/videos');
    final appDir = await getAppStorageDirectory();
    final videosDir = Directory('${appDir.path}/videos');
    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }
    return videosDir;
  }
} 