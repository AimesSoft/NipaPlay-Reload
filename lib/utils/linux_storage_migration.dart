import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LinuxStorageMigration {
  // 迁移标志键
  static const String _migrationCompletedKey = 'linux_storage_migration_completed';
  static const String _migrationVersionKey = 'linux_storage_migration_version';
  static const int _currentMigrationVersion = 1;
  
  // 新的Linux存储目录遵循XDG规范
  static String? _xdgDataHome;
  static String? _xdgCacheHome;
  
  /// 获取Linux XDG数据目录 (~/.local/share/NipaPlay)
  static Future<String> getXDGDataDirectory() async {
    if (_xdgDataHome != null) return _xdgDataHome!;
    
    // 优先使用环境变量 XDG_DATA_HOME
    final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
    if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
      _xdgDataHome = path.join(xdgDataHome, 'NipaPlay');
    } else {
      // 回退到 ~/.local/share/NipaPlay
      final homeDir = Platform.environment['HOME'];
      if (homeDir == null || homeDir.isEmpty) {
        throw Exception('无法获取用户主目录');
      }
      _xdgDataHome = path.join(homeDir, '.local', 'share', 'NipaPlay');
    }
    
    // 确保目录存在
    final dir = Directory(_xdgDataHome!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint('已创建XDG数据目录: $_xdgDataHome');
    }
    
    return _xdgDataHome!;
  }
  
  /// 获取Linux XDG缓存目录 (~/.cache/NipaPlay)
  static Future<String> getXDGCacheDirectory() async {
    if (_xdgCacheHome != null) return _xdgCacheHome!;
    
    // 优先使用环境变量 XDG_CACHE_HOME
    final xdgCacheHome = Platform.environment['XDG_CACHE_HOME'];
    if (xdgCacheHome != null && xdgCacheHome.isNotEmpty) {
      _xdgCacheHome = path.join(xdgCacheHome, 'NipaPlay');
    } else {
      // 回退到 ~/.cache/NipaPlay
      final homeDir = Platform.environment['HOME'];
      if (homeDir == null || homeDir.isEmpty) {
        throw Exception('无法获取用户主目录');
      }
      _xdgCacheHome = path.join(homeDir, '.cache', 'NipaPlay');
    }
    
    // 确保目录存在
    final dir = Directory(_xdgCacheHome!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint('已创建XDG缓存目录: $_xdgCacheHome');
    }
    
    return _xdgCacheHome!;
  }
  
  /// 检查是否需要迁移
  static Future<bool> needsMigration() async {
    if (!Platform.isLinux) return false;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(_migrationCompletedKey) ?? false;
      final version = prefs.getInt(_migrationVersionKey) ?? 0;
      
      // 如果已完成迁移且版本匹配，不需要迁移
      if (completed && version >= _currentMigrationVersion) {
        return false;
      }
      
      // 检查旧目录是否存在数据
      final documentsDir = await getApplicationDocumentsDirectory();
      final oldDataDir = Directory(documentsDir.path);
      
      if (!await oldDataDir.exists()) {
        // 旧目录不存在，标记迁移完成
        await _markMigrationCompleted();
        return false;
      }
      
      // 检查是否有需要迁移的文件
      final hasData = await _hasDataToMigrate(oldDataDir);
      if (!hasData) {
        // 没有数据需要迁移，标记迁移完成
        await _markMigrationCompleted();
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('检查迁移状态失败: $e');
      return false;
    }
  }
  
  /// 检查旧目录是否有数据需要迁移
  static Future<bool> _hasDataToMigrate(Directory oldDir) async {
    try {
      // 检查是否有应用相关的文件需要迁移
      final entities = await oldDir.list().toList();
      
      for (final entity in entities) {
        final name = path.basename(entity.path);
        if (_isAppRelatedItem(name)) {
          if (entity is Directory) {
            final hasContent = await entity.list().isEmpty;
            if (!hasContent) return true;
          } else if (entity is File) {
            final size = await entity.length();
            if (size > 0) return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('检查旧目录数据失败: $e');
      return false;
    }
  }
  
  /// 判断是否是应用相关的文件或目录
  static bool _isAppRelatedItem(String name) {
    // 应用相关的文件和目录名
    const appItems = [
      'nipaplay',
      'cache',
      'compressed_images',
      'danmaku_cache_139000001.json',
      'downloads',
      'temp',
      'thumbnails',
      'tmp',
      'videos',
      'watch_history.db',
      'watch_history.json',
      'backgrounds',
      'shared_preferences.json',
    ];
    
    return appItems.contains(name) || 
           name.endsWith('.jpg') && name.length == 68 || // 压缩图片文件
           name.endsWith('.png') && name.length == 32 || // 缩略图文件
           name.startsWith('danmaku_cache_') ||
           name.startsWith('custom_background_');
  }
  
  /// 执行迁移
  static Future<MigrationResult> performMigration() async {
    if (!Platform.isLinux) {
      return const MigrationResult(false, '非Linux平台，无需迁移');
    }
    
    debugPrint('开始Linux存储目录迁移...');
    
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final oldDataDir = Directory(documentsDir.path);
      final newDataDir = await getXDGDataDirectory();
      
      int totalItems = 0;
      int migratedItems = 0;
      int failedItems = 0;
      final List<String> errors = [];
      
      // 获取所有文件和目录
      final entities = await oldDataDir.list().toList();
      
      // 只迁移应用相关的内容
      for (final entity in entities) {
        final name = path.basename(entity.path);
        
        // 跳过非应用相关的文件
        if (!_isAppRelatedItem(name)) {
          debugPrint('跳过非应用文件: ${entity.path}');
          continue;
        }
        
        totalItems++;
        final targetPath = path.join(newDataDir, name);
        
        try {
          if (entity is Directory) {
            // 迁移目录
            await _migrateDirectory(entity, Directory(targetPath));
          } else if (entity is File) {
            // 迁移文件
            await _migrateFile(entity, File(targetPath));
          }
          
          migratedItems++;
          debugPrint('已迁移: ${entity.path} -> $targetPath');
          
        } catch (e) {
          failedItems++;
          final errorMsg = '迁移 ${entity.path} 失败: $e';
          errors.add(errorMsg);
          debugPrint(errorMsg);
        }
      }
      
      // 迁移完成后，只删除已迁移的应用相关文件
      if (failedItems == 0) {
        await _cleanupOldAppData(oldDataDir);
      }
      
      // 标记迁移完成
      await _markMigrationCompleted();
      
      final message = '迁移完成: 总数 $totalItems, 成功 $migratedItems, 失败 $failedItems';
      debugPrint(message);
      
      return MigrationResult(
        failedItems == 0,
        message,
        totalItems: totalItems,
        migratedItems: migratedItems,
        failedItems: failedItems,
        errors: errors,
      );
      
    } catch (e) {
      final errorMsg = '迁移过程出错: $e';
      debugPrint(errorMsg);
      return MigrationResult(false, errorMsg);
    }
  }
  
  /// 迁移目录
  static Future<void> _migrateDirectory(Directory source, Directory target) async {
    // 确保目标目录存在
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    
    // 递归复制目录内容
    await for (final entity in source.list(recursive: false)) {
      final name = path.basename(entity.path);
      final targetPath = path.join(target.path, name);
      
      if (entity is Directory) {
        await _migrateDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        await _migrateFile(entity, File(targetPath));
      }
    }
  }
  
  /// 迁移文件
  static Future<void> _migrateFile(File source, File target) async {
    // 确保目标目录存在
    final targetDir = Directory(path.dirname(target.path));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    
    // 复制文件
    await source.copy(target.path);
  }
  
  /// 清理旧的应用数据（只删除应用相关文件，保留用户个人文件）
  static Future<void> _cleanupOldAppData(Directory oldDataDir) async {
    try {
      final entities = await oldDataDir.list().toList();
      
      // 只删除应用相关的文件和目录
      for (final entity in entities) {
        final name = path.basename(entity.path);
        
        if (_isAppRelatedItem(name)) {
          if (entity is Directory) {
            await entity.delete(recursive: true);
          } else if (entity is File) {
            await entity.delete();
          }
          debugPrint('已删除旧的应用文件: ${entity.path}');
        }
      }
      
      debugPrint('应用相关的旧数据清理完成，用户个人文件已保留');
    } catch (e) {
      debugPrint('清理旧应用数据失败: $e');
      // 清理失败不影响迁移结果
    }
  }
  
  /// 标记迁移完成
  static Future<void> _markMigrationCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_migrationCompletedKey, true);
      await prefs.setInt(_migrationVersionKey, _currentMigrationVersion);
      debugPrint('已标记Linux存储迁移完成');
    } catch (e) {
      debugPrint('标记迁移完成失败: $e');
    }
  }
  
  /// 重置迁移状态（仅用于测试）
  static Future<void> resetMigrationStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_migrationCompletedKey);
      await prefs.remove(_migrationVersionKey);
      debugPrint('已重置Linux存储迁移状态');
    } catch (e) {
      debugPrint('重置迁移状态失败: $e');
    }
  }
  
  /// 紧急恢复功能：将个人文件从XDG目录移回Documents
  static Future<MigrationResult> emergencyRestorePersonalFiles() async {
    if (!Platform.isLinux) {
      return const MigrationResult(false, '非Linux平台，无需恢复');
    }
    
    debugPrint('开始紧急恢复个人文件...');
    
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final xdgDataDir = await getXDGDataDirectory();
      final xdgDir = Directory(xdgDataDir);
      
      if (!await xdgDir.exists()) {
        return const MigrationResult(false, 'XDG数据目录不存在');
      }
      
      int totalItems = 0;
      int restoredItems = 0;
      int failedItems = 0;
      final List<String> errors = [];
      
      // 获取XDG目录中的所有文件
      final entities = await xdgDir.list().toList();
      
      // 只恢复非应用相关的文件（即用户个人文件）
      for (final entity in entities) {
        final name = path.basename(entity.path);
        
        // 跳过应用相关的文件
        if (_isAppRelatedItem(name)) {
          debugPrint('保留应用文件: ${entity.path}');
          continue;
        }
        
        totalItems++;
        final targetPath = path.join(documentsDir.path, name);
        
        try {
          if (entity is Directory) {
            // 恢复目录
            await _migrateDirectory(entity, Directory(targetPath));
            await entity.delete(recursive: true);
          } else if (entity is File) {
            // 恢复文件
            await _migrateFile(entity, File(targetPath));
            await entity.delete();
          }
          
          restoredItems++;
          debugPrint('已恢复个人文件: ${entity.path} -> $targetPath');
          
        } catch (e) {
          failedItems++;
          final errorMsg = '恢复 ${entity.path} 失败: $e';
          errors.add(errorMsg);
          debugPrint(errorMsg);
        }
      }
      
      final message = '个人文件恢复完成: 总数 $totalItems, 成功 $restoredItems, 失败 $failedItems';
      debugPrint(message);
      
      return MigrationResult(
        failedItems == 0,
        message,
        totalItems: totalItems,
        migratedItems: restoredItems,
        failedItems: failedItems,
        errors: errors,
      );
      
    } catch (e) {
      final errorMsg = '恢复过程出错: $e';
      debugPrint(errorMsg);
      return MigrationResult(false, errorMsg);
    }
  }
}

/// 迁移结果类
class MigrationResult {
  final bool success;
  final String message;
  final int totalItems;
  final int migratedItems;
  final int failedItems;
  final List<String> errors;
  
  const MigrationResult(
    this.success,
    this.message, {
    this.totalItems = 0,
    this.migratedItems = 0,
    this.failedItems = 0,
    this.errors = const [],
  });
  
  @override
  String toString() {
    return 'MigrationResult(success: $success, message: $message, '
           'totalItems: $totalItems, migratedItems: $migratedItems, '
           'failedItems: $failedItems)';
  }
} 