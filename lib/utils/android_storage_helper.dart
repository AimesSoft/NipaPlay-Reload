import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AndroidStorageHelper {
  static const MethodChannel _channel = MethodChannel('custom_storage_channel');
  
  /// 获取当前Android版本（SDK_INT）
  static Future<int> getAndroidSDKVersion() async {
    if (!Platform.isAndroid) return 0;
    
    try {
      final int sdkVersion = await _channel.invokeMethod('getAndroidSDKVersion');
      debugPrint('Android SDK版本: $sdkVersion');
      return sdkVersion;
    } catch (e) {
      debugPrint('获取Android SDK版本失败: $e');
      return 0;
    }
  }
  
  /// 检查是否拥有管理外部存储的权限（Android 11+）
  static Future<bool> hasManageExternalStoragePermission() async {
    if (!Platform.isAndroid) return true;
    
    try {
      final bool hasPermission = await _channel.invokeMethod('checkManageExternalStoragePermission');
      debugPrint('检查MANAGE_EXTERNAL_STORAGE权限: $hasPermission');
      return hasPermission;
    } catch (e) {
      debugPrint('检查MANAGE_EXTERNAL_STORAGE权限失败: $e');
      return false;
    }
  }
  
  /// 请求管理外部存储权限（会打开系统设置页面）
  static Future<bool> requestManageExternalStoragePermission() async {
    if (!Platform.isAndroid) return true;
    
    try {
      final bool result = await _channel.invokeMethod('requestManageExternalStoragePermission');
      debugPrint('请求MANAGE_EXTERNAL_STORAGE权限: $result');
      return result;
    } catch (e) {
      debugPrint('请求MANAGE_EXTERNAL_STORAGE权限失败: $e');
      return false;
    }
  }
  
  /// 获取所有存储权限状态
  static Future<Map<String, dynamic>> getAllStoragePermissionStatus() async {
    if (!Platform.isAndroid) {
      return {
        'storage': 'granted',
        'manageExternalStorage': 'granted',
        'mediaImages': 'granted',
        'mediaVideo': 'granted',
        'mediaAudio': 'granted',
        'androidVersion': 0
      };
    }

    final int sdkVersion = await getAndroidSDKVersion();
    final Map<String, dynamic> status = {
      'androidVersion': sdkVersion,
      'storage': (await Permission.storage.status).toString(),
    };
    
    // Android 10及以上检查MANAGE_EXTERNAL_STORAGE
    if (sdkVersion >= 30) { // Android 11+
      status['manageExternalStorage'] = 
          (await Permission.manageExternalStorage.status).toString();
      
      // 原生方法也验证一下
      status['manageExternalStorageNative'] = 
          await hasManageExternalStoragePermission() ? 'granted' : 'denied';
    }
    
    // Android 13及以上检查媒体权限
    if (sdkVersion >= 33) { // Android 13+
      status['mediaImages'] = (await Permission.photos.status).toString();
      status['mediaVideo'] = (await Permission.videos.status).toString();
      status['mediaAudio'] = (await Permission.audio.status).toString();
    }
    
    debugPrint('所有存储权限状态: $status');
    return status;
  }
  
  /// 请求所有必要的存储权限（基于Android版本）
  static Future<bool> requestAllRequiredPermissions() async {
    if (!Platform.isAndroid) return true;
    
    final int sdkVersion = await getAndroidSDKVersion();
    bool allGranted = true;
    
    // Android 13+版本使用分类媒体权限
    if (sdkVersion >= 33) {
      final photosStatus = await Permission.photos.request();
      final videosStatus = await Permission.videos.request();
      final audioStatus = await Permission.audio.request();
      
      allGranted = allGranted && 
                   photosStatus.isGranted && 
                   videosStatus.isGranted && 
                   audioStatus.isGranted;
      
      debugPrint('Android 13+媒体权限: 照片=$photosStatus, 视频=$videosStatus, 音频=$audioStatus');
    } else {
      // 旧版Android使用基本存储权限
      final storageStatus = await Permission.storage.request();
      allGranted = allGranted && storageStatus.isGranted;
      debugPrint('Android基本存储权限: $storageStatus');
    }
    
    // Android 11及以上可能需要特殊的全部文件访问权限
    if (sdkVersion >= 30) {
      final manageStorageStatus = await Permission.manageExternalStorage.status;
      if (!manageStorageStatus.isGranted) {
        // 这将打开系统设置页面
        await requestManageExternalStoragePermission();
        // 注意：此时可能权限尚未授予，需要用户手动操作
        debugPrint('已请求MANAGE_EXTERNAL_STORAGE权限，结果需要用户在设置中手动确认');
      }
    }
    
    return allGranted;
  }
  
  /// 检查指定路径的目录权限
  static Future<Map<String, dynamic>> checkDirectoryPermissions(String path) async {
    if (!Platform.isAndroid) {
      return {
        'canRead': true,
        'canWrite': true,
        'exists': true
      };
    }
    
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'checkExternalStorageDirectory',
        {'path': path}
      );
      
      debugPrint('检查目录权限 $path: $result');
      
      if (result == null) {
        return {
          'canRead': false,
          'canWrite': false,
          'exists': false
        };
      }
      
      return {
        'canRead': result['canRead'] ?? false,
        'canWrite': result['canWrite'] ?? false,
        'exists': result['exists'] ?? false
      };
    } catch (e) {
      debugPrint('检查目录权限失败: $e');
      return {
        'canRead': false,
        'canWrite': false,
        'exists': false,
        'error': e.toString()
      };
    }
  }
} 