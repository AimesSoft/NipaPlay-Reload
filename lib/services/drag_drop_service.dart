import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DragDropService {
  static const MethodChannel _channel = MethodChannel('drag_drop_channel');

  /// 初始化拖拽功能
  static Future<void> initialize() async {
    if (!_isDesktop) return;

    try {
      await _channel.invokeMethod('initialize');
      debugPrint('[DragDrop] 拖拽功能初始化成功');
    } catch (e) {
      debugPrint('[DragDrop] 拖拽功能初始化失败: $e');
    }
  }

  /// 设置拖拽回调
  static void setDropCallback(Function(List<String>) onFilesDropped) {
    if (!_isDesktop) return;

    debugPrint('[DragDrop] 设置拖拽回调');
    
    _channel.setMethodCallHandler((call) async {
      debugPrint('[DragDrop] 收到方法调用: ${call.method}');
      
      if (call.method == 'onFilesDropped') {
        final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
        final List<dynamic> files = args['files'] ?? [];
        final List<String> filePaths = files.cast<String>();
        
        debugPrint('[DragDrop] 解析到文件路径: $filePaths');
        onFilesDropped(filePaths);
      }
    });
  }

  /// 检查是否为桌面平台
  static bool get _isDesktop => 
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 验证拖拽的文件是否为支持的视频格式
  static List<String> filterSupportedVideoFiles(List<String> filePaths) {
    final supportedExtensions = [
      '.mp4', '.mkv', '.avi', '.mov', '.webm', '.wmv', 
      '.m4v', '.3gp', '.flv', '.ts', '.m2ts'
    ];

    return filePaths.where((filePath) {
      final extension = filePath.toLowerCase().split('.').last;
      return supportedExtensions.any((ext) => ext.endsWith(extension));
    }).toList();
  }

  /// 处理拖拽的文件
  static Future<String?> handleDroppedFiles(List<String> filePaths) async {
    if (filePaths.isEmpty) return null;

    // 过滤出支持的视频文件
    final videoFiles = filterSupportedVideoFiles(filePaths);
    
    if (videoFiles.isEmpty) {
      debugPrint('[DragDrop] 没有找到支持的视频文件');
      return null;
    }

    // 返回第一个视频文件
    final selectedFile = videoFiles.first;
    debugPrint('[DragDrop] 选择播放文件: $selectedFile');
    
    return selectedFile;
  }

  /// 启用/禁用拖拽功能
  static Future<void> setEnabled(bool enabled) async {
    if (!_isDesktop) return;

    try {
      await _channel.invokeMethod('setEnabled', {'enabled': enabled});
      debugPrint('[DragDrop] 拖拽功能${enabled ? "启用" : "禁用"}');
    } catch (e) {
      debugPrint('[DragDrop] 设置拖拽功能状态失败: $e');
    }
  }

  /// 获取拖拽功能状态
  static Future<bool> isEnabled() async {
    if (!_isDesktop) return false;

    try {
      final result = await _channel.invokeMethod('isEnabled');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('[DragDrop] 获取拖拽功能状态失败: $e');
      return false;
    }
  }
} 