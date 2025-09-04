import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/storage_service.dart';

/// iOS容器路径修复工具类
/// 
/// 解决iOS沙盒机制下，应用重新构建时容器ID变化导致的路径失效问题
class iOSContainerPathFixer {
  static String? _currentContainerId;
  
  /// 获取当前容器ID
  static Future<String?> getCurrentContainerId() async {
    if (!Platform.isIOS) return null;
    
    if (_currentContainerId != null) return _currentContainerId;
    
    try {
      final currentAppDir = await StorageService.getAppStorageDirectory();
      final currentContainerPath = currentAppDir.path;
      
      final match = RegExp(r'/var/mobile/Containers/Data/Application/([^/]+)')
          .firstMatch(currentContainerPath);
      
      if (match != null) {
        _currentContainerId = match.group(1);
        debugPrint('iOSContainerPathFixer: 当前容器ID = $_currentContainerId');
      }
      
      return _currentContainerId;
    } catch (e) {
      debugPrint('iOSContainerPathFixer: 获取容器ID失败: $e');
      return null;
    }
  }
  
  /// 修复iOS容器路径
  static Future<String?> fixContainerPath(String originalPath) async {
    if (!Platform.isIOS) return null;
    
    try {
      final currentContainerId = await getCurrentContainerId();
      if (currentContainerId == null) return null;
      
      // 检查原路径是否包含不同的容器ID
      final originalContainerMatch = RegExp(r'/var/mobile/Containers/Data/Application/([^/]+)')
          .firstMatch(originalPath);
      
      if (originalContainerMatch == null) return null;
      
      final originalContainerId = originalContainerMatch.group(1);
      
      // 如果容器ID相同，不需要修复
      if (currentContainerId == originalContainerId) return null;
      
      // 替换容器ID生成新路径
      final newPath = originalPath.replaceFirst(
        '/var/mobile/Containers/Data/Application/$originalContainerId',
        '/var/mobile/Containers/Data/Application/$currentContainerId'
      );
      
      debugPrint('iOSContainerPathFixer: 路径修复 $originalContainerId -> $currentContainerId');
      
      return newPath;
    } catch (e) {
      debugPrint('iOSContainerPathFixer: 修复路径失败: $e');
      return null;
    }
  }
  
  /// 批量修复路径列表
  static Future<List<String>> fixPathList(List<String> originalPaths) async {
    if (!Platform.isIOS || originalPaths.isEmpty) return originalPaths;
    
    final currentContainerId = await getCurrentContainerId();
    if (currentContainerId == null) return originalPaths;
    
    List<String> fixedPaths = [];
    
    for (String originalPath in originalPaths) {
      final fixedPath = await fixContainerPath(originalPath);
      fixedPaths.add(fixedPath ?? originalPath);
    }
    
    return fixedPaths;
  }
  
  /// 验证并修复文件路径
  static Future<String?> validateAndFixFilePath(String originalPath) async {
    if (!Platform.isIOS) {
      return File(originalPath).existsSync() ? originalPath : null;
    }
    
    // 先检查原路径
    if (File(originalPath).existsSync()) {
      return originalPath;
    }
    
    // 尝试修复容器路径
    final fixedPath = await fixContainerPath(originalPath);
    if (fixedPath != null && File(fixedPath).existsSync()) {
      return fixedPath;
    }
    
    return null;
  }
  
  /// 验证并修复目录路径
  static Future<String?> validateAndFixDirectoryPath(String originalPath) async {
    if (!Platform.isIOS) {
      return Directory(originalPath).existsSync() ? originalPath : null;
    }
    
    // 先检查原路径
    if (Directory(originalPath).existsSync()) {
      return originalPath;
    }
    
    // 尝试修复容器路径
    final fixedPath = await fixContainerPath(originalPath);
    if (fixedPath != null && Directory(fixedPath).existsSync()) {
      return fixedPath;
    }
    
    return null;
  }
  
  /// 重置缓存的容器ID（用于测试或强制刷新）
  static void resetCache() {
    _currentContainerId = null;
  }
}