import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'security_bookmark_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'dart:io' as io;

class FilePickerService {
  // 单例模式
  static final FilePickerService _instance = FilePickerService._internal();
  
  factory FilePickerService() {
    return _instance;
  }
  
  FilePickerService._internal();
  
  // 存储上次选择的目录路径
  static const String _lastVideoDirKey = 'last_video_dir';
  static const String _lastSubtitleDirKey = 'last_subtitle_dir';
  static const String _lastDirKey = 'last_dir';
  
  // 内部方法：规范化文件路径（处理iOS的/private前缀）
  String _normalizePath(String path) {
    // 移除可能的重复斜杠
    String normalizedPath = path.replaceAll('//', '/');
    
    // 处理iOS上的/private前缀
    if (io.Platform.isIOS) {
      // 如果路径不存在但添加/private后存在，则使用带前缀的路径
      if (!io.File(normalizedPath).existsSync() && 
          !io.Directory(normalizedPath).existsSync()) {
        
        String privatePrefix = normalizedPath.startsWith('/private') ? '' : '/private';
        String pathWithPrefix = '$privatePrefix$normalizedPath';
        
        if (io.File(pathWithPrefix).existsSync() || 
            io.Directory(pathWithPrefix).existsSync()) {
          return pathWithPrefix;
        }
      }
      
      // 检查是否是iOS临时文件路径，如果是则复制到持久存储
      if (_isIOSTemporaryPath(normalizedPath)) {
        final persistentPath = _copyToDocumentsIfNeeded(normalizedPath);
        if (persistentPath != null) {
          return persistentPath;
        }
      }
    }
    
    return normalizedPath;
  }
  
  // 检查是否是iOS临时文件路径
  bool _isIOSTemporaryPath(String path) {
    if (!io.Platform.isIOS) return false;
    
    // 检查是否包含常见的iOS临时目录或收件箱标记
    return path.contains('/tmp/') || 
           path.contains('-Inbox/') || 
           path.contains('/Inbox/') ||
           path.contains('/Containers/Data/Application/');
  }
  
  // 将文件从临时目录复制到文档目录以保持持久化
  String? _copyToDocumentsIfNeeded(String filePath) {
    try {
      if (!io.File(filePath).existsSync()) {
        // 尝试添加/private前缀
        final altPath = filePath.startsWith('/private') 
                         ? filePath 
                         : '/private$filePath';
        if (!io.File(altPath).existsSync()) {
          print('文件不存在: $filePath 或 $altPath');
          return null;
        }
        filePath = altPath;
      }
      
      final sourceFile = io.File(filePath);
      final fileName = p.basename(filePath);
      
      // 同步获取应用文档目录
      try {
        // 尝试直接创建视频目录
        io.Directory videosDir;
        
        // 在iOS上，我们知道文档目录的一般格式，可以尝试直接构建
        if (io.Platform.isIOS) {
          const String appDocPath = '/var/mobile/Containers/Data/Application/';
          // 获取源文件所在的应用容器ID
          final segments = filePath.split('/');
          String? containerId;
          
          for (int i = 0; i < segments.length; i++) {
            if (segments[i] == 'Application' && i + 1 < segments.length) {
              containerId = segments[i + 1];
              break;
            }
          }
          
          if (containerId != null) {
            final docsPath = '$appDocPath$containerId/Documents';
            if (io.Directory(docsPath).existsSync()) {
              videosDir = io.Directory('$docsPath/Videos');
              if (!videosDir.existsSync()) {
                videosDir.createSync();
              }
              
              final destinationPath = '${videosDir.path}/$fileName';
              final destinationFile = io.File(destinationPath);
              
              // 检查文件是否已存在，避免重复复制
              if (!destinationFile.existsSync() || 
                  destinationFile.lengthSync() != sourceFile.lengthSync()) {
                sourceFile.copySync(destinationPath);
                print('已复制文件到持久存储: $destinationPath');
              }
              
              return destinationPath;
            }
          }
        }
        
        // 回退方案：使用临时文件中的ID尝试构造文档目录
        final appId = filePath.split('/').firstWhere(
          (segment) => segment.contains('-') && segment.length > 8,
          orElse: () => '',
        );
        
        if (appId.isNotEmpty) {
          final possibleDocPath = '/var/mobile/Containers/Data/Application/$appId/Documents';
          if (io.Directory(possibleDocPath).existsSync()) {
            videosDir = io.Directory('$possibleDocPath/Videos');
            if (!videosDir.existsSync()) {
              videosDir.createSync();
            }
            
            final destinationPath = '${videosDir.path}/$fileName';
            final destinationFile = io.File(destinationPath);
            
            // 检查文件是否已存在，避免重复复制
            if (!destinationFile.existsSync() || 
                destinationFile.lengthSync() != sourceFile.lengthSync()) {
              sourceFile.copySync(destinationPath);
              print('已复制文件到持久存储: $destinationPath');
            }
            
            return destinationPath;
          }
        }
        
        // 如果上述方法都失败，使用异步方法但不等待结果
        StorageService.getAppStorageDirectory().then((docDir) {
          final vDir = io.Directory('${docDir.path}/Videos');
          if (!vDir.existsSync()) {
            vDir.createSync();
          }
          
          final destPath = '${vDir.path}/$fileName';
          final destFile = io.File(destPath);
          
          // 检查文件是否已存在，避免重复复制
          if (!destFile.existsSync() || 
              destFile.lengthSync() != sourceFile.lengthSync()) {
            sourceFile.copySync(destPath);
            print('已延迟复制文件到持久存储: $destPath');
          }
        });
        
        // 无法立即获取目标路径，返回原路径
        return filePath;
      } catch (e) {
        print('创建视频目录失败: $e');
        return filePath;
      }
    } catch (e) {
      print('复制文件到持久存储失败: $e');
      return filePath; // 出错时返回原路径，至少不会阻塞流程
    }
  }
  
  // 检查文件是否存在，处理iOS路径问题
  bool checkFileExists(String path) {
    final io.File file = io.File(path);
    if (file.existsSync()) {
      return true;
    }
    
    // 处理iOS路径前缀问题
    if (io.Platform.isIOS) {
      String alternativePath;
      if (path.startsWith('/private')) {
        alternativePath = path.replaceFirst('/private', '');
      } else {
        alternativePath = '/private$path';
      }
      
      return io.File(alternativePath).existsSync();
    }
    
    return false;
  }

  // 内存优化：限制文件大小读取
  Future<List<int>?> _readFileSafely(String path, {int maxSizeInMb = 10}) async {
    try {
      final file = io.File(path);
      if (!file.existsSync()) return null;
      
      // 检查文件大小
      final fileSize = await file.length();
      final maxSize = maxSizeInMb * 1024 * 1024; // 转换为字节
      
      if (fileSize > maxSize) {
        print('文件过大，跳过元数据读取: ${fileSize ~/ (1024 * 1024)}MB > ${maxSizeInMb}MB');
        return null;
      }
      
      // 使用compute在隔离区(isolate)中读取文件以避免阻塞主线程
      return await compute(_isolatedReadFile, path);
    } catch (e) {
      print('读取文件失败: $e');
      return null;
    }
  }
  
  // 在隔离区中读取文件
  static List<int> _isolatedReadFile(String path) {
    return io.File(path).readAsBytesSync();
  }

  // 选择视频文件
  Future<String?> pickVideoFile({String? initialDirectory}) async {
    try {
      // 获取上次目录
      initialDirectory ??= await _getLastDirectory(_lastVideoDirKey);
      
      // iOS上初始目录处理
      if (io.Platform.isIOS && (initialDirectory == null || initialDirectory.isEmpty)) {
        try {
          final io.Directory appDocDir = await StorageService.getAppStorageDirectory();
          initialDirectory = appDocDir.path;
        } catch (e) {
          print("Error getting documents directory for iOS: $e");
        }
      }
      
      // macOS上尝试恢复之前的书签访问
      if (io.Platform.isMacOS && initialDirectory != null) {
        final resolvedPath = await SecurityBookmarkService.resolveBookmark(initialDirectory);
        if (resolvedPath != null) {
          initialDirectory = resolvedPath;
        }
      }
      
      // 定义视频文件类型组
      XTypeGroup videoGroup = XTypeGroup(
        label: '视频文件',
        extensions: const ['mp4', 'mkv', 'avi', 'wmv', 'mov'],
        uniformTypeIdentifiers: io.Platform.isIOS 
            ? ['public.movie', 'public.video', 'public.mpeg-4', 'com.apple.quicktime-movie'] 
            : null,
      );
      
      // OOM问题修复：Android平台使用不同的文件选择方式
      if (io.Platform.isAndroid) {
        // 使用自定义方法选择文件，避免file_selector插件的内存问题
        return await _pickVideoFileAndroid();
      }
      
      // 其他平台正常使用file_selector
      final XFile? file = await openFile(
        acceptedTypeGroups: [videoGroup],
        initialDirectory: initialDirectory,
        confirmButtonText: '选择视频文件',
      );
      
      if (file == null) {
        return null;
      }
      
      // 获取文件路径
      String filePath = file.path;

      // 内存优化：不读取文件元数据，只返回路径
      // 优化前：file.readAsBytes(); 这可能导致大文件内存溢出
      // 注：现在直接返回路径，由播放器处理文件读取
      
      // macOS沙盒下创建安全书签
      if (io.Platform.isMacOS) {
        await SecurityBookmarkService.createBookmark(filePath);
        // 同时为父目录创建书签，便于下次文件选择
        final parentDir = p.dirname(filePath);
        await SecurityBookmarkService.createBookmark(parentDir);
      }
      
      // 存储目录信息
      _saveLastDirectory(filePath, _lastVideoDirKey, _lastDirKey);
      
      return _normalizePath(filePath);
    } catch (e) {
      print('选择视频文件时出错: $e');
      return null;
    }
  }

  // Android平台特定的视频文件选择方法
  Future<String?> _pickVideoFileAndroid() async {
    try {
      // 使用Intent获取文件路径而不是内容
      final result = await const MethodChannel('plugins.flutter.io/file_selector')
          .invokeMethod<String>('pickFilePathOnly', {
        'acceptedTypeGroups': [
          {
            'label': '视频文件',
            'extensions': ['mp4', 'mkv', 'avi', 'wmv', 'mov'],
          }
        ],
        'confirmButtonText': '选择视频文件',
      });
      
      if (result == null || result.isEmpty) {
        return null;
      }
      
      // 存储目录信息
      _saveLastDirectory(result, _lastVideoDirKey, _lastDirKey);
      
      return _normalizePath(result);
    } catch (e) {
      print('Android选择视频文件时出错: $e');
      
      // 如果自定义方法失败，回退到默认方法
      final intent = await const MethodChannel('android/intent')
          .invokeMethod<Map<dynamic, dynamic>>('createChooser', {
        'action': 'android.intent.action.GET_CONTENT',
        'type': 'video/*',
        'title': '选择视频文件',
      });
      
      if (intent == null || intent['data'] == null) {
        return null;
      }
      
      return intent['data'].toString();
    }
  }

  // 选择字幕文件
  Future<String?> pickSubtitleFile({String? initialDirectory}) async {
    try {
      // 获取上次目录
      initialDirectory ??= await _getLastDirectory(_lastSubtitleDirKey);
      
      // macOS上尝试恢复之前的书签访问
      if (io.Platform.isMacOS && initialDirectory != null) {
        final resolvedPath = await SecurityBookmarkService.resolveBookmark(initialDirectory);
        if (resolvedPath != null) {
          initialDirectory = resolvedPath;
        }
      }
      
      // 定义字幕文件类型组
      XTypeGroup subtitleGroup = XTypeGroup(
        label: '字幕文件',
        extensions: const ['srt', 'ass', 'ssa', 'sub'],
        uniformTypeIdentifiers: io.Platform.isIOS 
            ? ['public.text', 'public.plain-text', 'public.subtitle', 'public.data', 'public.item'] 
            : null,
      );
      
      // Android平台特殊处理字幕文件选择
      if (io.Platform.isAndroid) {
        return await _pickSubtitleFileAndroid();
      }
      
      // 其他平台使用默认方法
      final XFile? file = await openFile(
        acceptedTypeGroups: [subtitleGroup],
        initialDirectory: initialDirectory,
        confirmButtonText: '选择字幕文件',
      );
      
      if (file == null) {
        return null;
      }
      
      // macOS沙盒下创建安全书签
      if (io.Platform.isMacOS) {
        await SecurityBookmarkService.createBookmark(file.path);
        // 同时为父目录创建书签
        final parentDir = p.dirname(file.path);
        await SecurityBookmarkService.createBookmark(parentDir);
      }
      
      // 保存目录位置
      _saveLastDirectory(p.dirname(file.path), _lastSubtitleDirKey);
      _saveLastDirectory(p.dirname(file.path), _lastDirKey);
      
      return _normalizePath(file.path);
    } catch (e) {
      print('选择字幕文件失败: $e');
      return null;
    }
  }

  // 选择文件夹
  Future<String?> pickDirectory({String? initialDirectory}) async {
    try {
      // 获取上次目录
      initialDirectory ??= await _getLastDirectory(_lastDirKey);
      
      // macOS上尝试恢复之前的书签访问
      if (io.Platform.isMacOS && initialDirectory != null) {
        final resolvedPath = await SecurityBookmarkService.resolveBookmark(initialDirectory);
        if (resolvedPath != null) {
          initialDirectory = resolvedPath;
        }
      }
      
      // iOS上的特殊处理
      if (io.Platform.isIOS) {
        // iOS上目前file_selector的getDirectoryPath功能受限
        // 仅返回文档目录
        try {
          final io.Directory appDocDir = await StorageService.getAppStorageDirectory();
          _saveLastDirectory(appDocDir.path, _lastDirKey);
          return _normalizePath(appDocDir.path);
        } catch (e) {
          print("Error getting documents directory for iOS: $e");
          return null;
        }
      } else {
        // 非iOS平台正常选择目录
        final String? selectedDirectory = await getDirectoryPath(
          initialDirectory: initialDirectory,
        );
        
        if (selectedDirectory == null) {
          return null;
        }
        
        // macOS沙盒下创建安全书签
        if (io.Platform.isMacOS) {
          await SecurityBookmarkService.createBookmark(selectedDirectory);
        }
        
        // 保存选择的目录
        _saveLastDirectory(selectedDirectory, _lastDirKey);
        
        return _normalizePath(selectedDirectory);
      }
    } catch (e) {
      print('选择文件夹失败: $e');
      return null;
    }
  }
  
  // 存储上次选择的目录
  Future<void> _saveLastDirectory(String filePath, String primaryKey, [String? secondaryKey]) async {
    try {
      final directory = p.dirname(filePath);
      final prefs = await SharedPreferences.getInstance();
      
      // 保存主键
      await prefs.setString(primaryKey, directory);
      
      // 如果提供了次键，也保存
      if (secondaryKey != null) {
        await prefs.setString(secondaryKey, directory);
      }
    } catch (e) {
      print('保存目录失败: $e');
    }
  }
  
  // 获取上次选择的目录
  Future<String?> _getLastDirectory(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (e) {
      print('获取目录失败: $e');
      return null;
    }
  }
  
  // 获取文件的有效路径(处理iOS路径问题)
  Future<String?> getValidFilePath(String originalPath) async {
    // macOS沙盒下首先尝试恢复书签访问
    if (io.Platform.isMacOS) {
      final resolvedPath = await SecurityBookmarkService.resolveBookmark(originalPath);
      if (resolvedPath != null && io.File(resolvedPath).existsSync()) {
        return resolvedPath;
      }
    }
    
    // 首先检查原始路径是否可访问
    if (io.File(originalPath).existsSync()) {
      return originalPath;
    }
    
    // 处理iOS的/private前缀
    if (io.Platform.isIOS) {
      String alternativePath;
      if (originalPath.startsWith('/private')) {
        alternativePath = originalPath.replaceFirst('/private', '');
      } else {
        alternativePath = '/private$originalPath';
      }
      
      if (io.File(alternativePath).existsSync()) {
        return alternativePath;
      }
      
      // 检查文件是否可能在文档目录中
      try {
        final io.Directory appDocDir = await StorageService.getAppStorageDirectory();
        final fileName = p.basename(originalPath);
        final docPath = '${appDocDir.path}/Videos/$fileName';
        
        if (io.File(docPath).existsSync()) {
          return docPath;
        }
      } catch (e) {
        print("检查文档目录中的文件失败: $e");
      }
    }
    
    return null; // 找不到有效路径
  }

  // Android平台特定的字幕文件选择方法
  Future<String?> _pickSubtitleFileAndroid() async {
    try {
      // 使用通用文件选择Intent，支持所有文本文件
      final result = await const MethodChannel('android/intent')
          .invokeMethod<Map<dynamic, dynamic>>('createChooser', {
        'action': 'android.intent.action.GET_CONTENT',
        'type': 'text/*', // 使用text/*类型，涵盖所有文本文件包括srt、ass等
        'title': '选择字幕文件',
        'extra_mime_types': [
          'text/plain',
          'text/srt',
          'text/ass',
          'text/ssa',
          'text/sub',
          'application/x-subrip',
          'application/x-ass',
          '*/*' // 允许所有文件类型作为备选
        ],
      });
      
      if (result == null || result['data'] == null) {
        return null;
      }
      
      final filePath = result['data'].toString();
      
      // 存储目录信息
      _saveLastDirectory(filePath, _lastSubtitleDirKey, _lastDirKey);
      
      return _normalizePath(filePath);
    } catch (e) {
      print('Android选择字幕文件时出错: $e');
      
      // 如果Intent方法失败，尝试使用更宽泛的文件选择
      try {
        final fallbackResult = await const MethodChannel('android/intent')
            .invokeMethod<Map<dynamic, dynamic>>('createChooser', {
          'action': 'android.intent.action.GET_CONTENT',
          'type': '*/*', // 允许选择任何文件
          'title': '选择字幕文件',
        });
        
        if (fallbackResult == null || fallbackResult['data'] == null) {
          return null;
        }
        
        final filePath = fallbackResult['data'].toString();
        _saveLastDirectory(filePath, _lastSubtitleDirKey, _lastDirKey);
        return _normalizePath(filePath);
      } catch (fallbackError) {
        print('Android字幕文件选择备用方法也失败: $fallbackError');
        return null;
      }
    }
  }
} 