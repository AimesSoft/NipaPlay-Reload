import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// macOS 沙盒安全书签服务
/// 用于在应用重启后恢复文件访问权限
class SecurityBookmarkService {
  static const MethodChannel _channel = MethodChannel('security_bookmark');
  
  // 存储书签数据的前缀
  static const String _bookmarkPrefix = 'security_bookmark_';
  static const String _activeResourcesKey = 'active_security_resources';
  
  // 当前活跃的安全作用域资源
  static final Set<String> _activeResources = <String>{};
  
  /// 创建文件或文件夹的安全书签
  static Future<bool> createBookmark(String path) async {
    if (!Platform.isMacOS) {
      return true; // 非macOS平台直接返回成功
    }
    
    try {
      final result = await _channel.invokeMethod('createBookmark', {
        'path': path,
      });
      
      if (result is Uint8List) {
        // 保存书签数据到SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final bookmarkKey = _getBookmarkKey(path);
        final bookmarkBase64 = base64Encode(result);
        await prefs.setString(bookmarkKey, bookmarkBase64);
        
        print('[SecurityBookmark] 创建书签成功: $path');
        return true;
      }
      
      return false;
    } catch (e) {
      print('[SecurityBookmark] 创建书签失败: $e');
      return false;
    }
  }
  
  /// 解析书签并恢复文件访问权限
  static Future<String?> resolveBookmark(String originalPath) async {
    if (!Platform.isMacOS) {
      return originalPath; // 非macOS平台直接返回原路径
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookmarkKey = _getBookmarkKey(originalPath);
      final bookmarkBase64 = prefs.getString(bookmarkKey);
      
      if (bookmarkBase64 == null || bookmarkBase64.isEmpty) {
        print('[SecurityBookmark] 未找到书签数据: $originalPath');
        return null;
      }
      
      final bookmarkData = base64Decode(bookmarkBase64);
      final result = await _channel.invokeMethod('resolveBookmark', {
        'bookmarkData': Uint8List.fromList(bookmarkData),
      });
      
      if (result is Map) {
        final resolvedPath = result['path'] as String?;
        final didStartAccessing = result['didStartAccessing'] as bool? ?? false;
        final isStale = result['isStale'] as bool? ?? false;
        
        if (resolvedPath != null && didStartAccessing) {
          // 记录活跃的安全作用域资源
          _activeResources.add(resolvedPath);
          await _saveActiveResources();
          
          print('[SecurityBookmark] 解析书签成功: $resolvedPath (stale: $isStale)');
          
          // 如果书签过时，尝试重新创建
          if (isStale) {
            print('[SecurityBookmark] 书签已过时，尝试重新创建');
            await createBookmark(resolvedPath);
          }
          
          return resolvedPath;
        }
      }
      
      return null;
    } catch (e) {
      print('[SecurityBookmark] 解析书签失败: $e');
      return null;
    }
  }
  
  /// 停止访问安全作用域资源
  static Future<void> stopAccessingResource(String path) async {
    if (!Platform.isMacOS) {
      return;
    }
    
    try {
      await _channel.invokeMethod('stopAccessingSecurityScopedResource', {
        'path': path,
      });
      
      _activeResources.remove(path);
      await _saveActiveResources();
      
      print('[SecurityBookmark] 停止访问安全作用域资源: $path');
    } catch (e) {
      print('[SecurityBookmark] 停止访问安全作用域资源失败: $e');
    }
  }
  
  /// 应用启动时恢复所有已保存的书签
  static Future<void> restoreAllBookmarks() async {
    if (!Platform.isMacOS) {
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_bookmarkPrefix)) {
          final originalPath = _getPathFromKey(key);
          if (originalPath.isNotEmpty) {
            final resolvedPath = await resolveBookmark(originalPath);
            if (resolvedPath != null) {
              print('[SecurityBookmark] 恢复书签: $originalPath -> $resolvedPath');
            }
          }
        }
      }
    } catch (e) {
      print('[SecurityBookmark] 恢复书签失败: $e');
    }
  }
  
  /// 清理所有活跃的安全作用域资源（应用退出时调用）
  static Future<void> cleanup() async {
    if (!Platform.isMacOS) {
      return;
    }
    
    for (final path in _activeResources.toList()) {
      await stopAccessingResource(path);
    }
    
    _activeResources.clear();
    await _saveActiveResources();
  }
  
  /// 检查文件是否有有效的书签
  static Future<bool> hasBookmark(String path) async {
    if (!Platform.isMacOS) {
      return true;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final bookmarkKey = _getBookmarkKey(path);
    return prefs.containsKey(bookmarkKey);
  }
  
  /// 删除指定路径的书签
  static Future<void> removeBookmark(String path) async {
    if (!Platform.isMacOS) {
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookmarkKey = _getBookmarkKey(path);
      await prefs.remove(bookmarkKey);
      
      // 如果正在访问这个资源，停止访问
      if (_activeResources.contains(path)) {
        await stopAccessingResource(path);
      }
      
      print('[SecurityBookmark] 删除书签: $path');
    } catch (e) {
      print('[SecurityBookmark] 删除书签失败: $e');
    }
  }
  
  /// 获取书签存储键
  static String _getBookmarkKey(String path) {
    // 使用路径的base64编码作为键，避免特殊字符问题
    final pathBytes = utf8.encode(path);
    final pathBase64 = base64Encode(pathBytes);
    return '$_bookmarkPrefix$pathBase64';
  }
  
  /// 从存储键获取原始路径
  static String _getPathFromKey(String key) {
    try {
      if (!key.startsWith(_bookmarkPrefix)) {
        return '';
      }
      
      final pathBase64 = key.substring(_bookmarkPrefix.length);
      final pathBytes = base64Decode(pathBase64);
      return utf8.decode(pathBytes);
    } catch (e) {
      return '';
    }
  }
  
  /// 保存活跃资源列表
  static Future<void> _saveActiveResources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeList = _activeResources.toList();
      await prefs.setStringList(_activeResourcesKey, activeList);
    } catch (e) {
      print('[SecurityBookmark] 保存活跃资源列表失败: $e');
    }
  }
  
  /// 加载活跃资源列表
  static Future<void> _loadActiveResources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeList = prefs.getStringList(_activeResourcesKey) ?? [];
      _activeResources.addAll(activeList);
    } catch (e) {
      print('[SecurityBookmark] 加载活跃资源列表失败: $e');
    }
  }
}
