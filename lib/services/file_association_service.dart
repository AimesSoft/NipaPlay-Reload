import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FileAssociationService {
  static const MethodChannel _channel = MethodChannel('file_association_channel');

  /// 获取从系统传入的文件路径（仅Android）
  static Future<String?> getOpenFileUri() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod('getOpenFileUri');
      return result as String?;
    } on PlatformException catch (e) {
      debugPrint("获取打开文件URI失败: '${e.message}'.");
      return null;
    }
  }

  /// 检查文件是否为支持的视频格式
  static bool isSupportedVideoFile(String filePath) {
    final supportedExtensions = [
      '.mp4', '.mkv', '.avi', '.mov', '.webm', '.wmv', 
      '.m4v', '.3gp', '.flv', '.ts', '.m2ts'
    ];
    
    final extension = filePath.toLowerCase().split('.').last;
    return supportedExtensions.any((ext) => ext.endsWith(extension));
  }

  /// 验证文件路径是否有效
  static Future<bool> validateFilePath(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists() && isSupportedVideoFile(filePath);
    } catch (e) {
      debugPrint("验证文件路径失败: $e");
      return false;
    }
  }
} 