import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    if (Platform.isIOS) {
      // 如果路径不存在但添加/private后存在，则使用带前缀的路径
      if (!File(normalizedPath).existsSync() && 
          !Directory(normalizedPath).existsSync()) {
        
        String privatePrefix = normalizedPath.startsWith('/private') ? '' : '/private';
        String pathWithPrefix = '$privatePrefix$normalizedPath';
        
        if (File(pathWithPrefix).existsSync() || 
            Directory(pathWithPrefix).existsSync()) {
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
    if (!Platform.isIOS) return false;
    
    // 检查是否包含常见的iOS临时目录或收件箱标记
    return path.contains('/tmp/') || 
           path.contains('-Inbox/') || 
           path.contains('/Inbox/') ||
           path.contains('/Containers/Data/Application/');
  }
  
  // 将文件从临时目录复制到文档目录以保持持久化
  String? _copyToDocumentsIfNeeded(String filePath) {
    try {
      if (!File(filePath).existsSync()) {
        // 尝试添加/private前缀
        final altPath = filePath.startsWith('/private') 
                         ? filePath 
                         : '/private$filePath';
        if (!File(altPath).existsSync()) {
          print('文件不存在: $filePath 或 $altPath');
          return null;
        }
        filePath = altPath;
      }
      
      final sourceFile = File(filePath);
      final fileName = p.basename(filePath);
      
      // 同步获取应用文档目录
      try {
        // 尝试直接创建视频目录
        Directory videosDir;
        
        // 在iOS上，我们知道文档目录的一般格式，可以尝试直接构建
        if (Platform.isIOS) {
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
            if (Directory(docsPath).existsSync()) {
              videosDir = Directory('$docsPath/Videos');
              if (!videosDir.existsSync()) {
                videosDir.createSync();
              }
              
              final destinationPath = '${videosDir.path}/$fileName';
              final destinationFile = File(destinationPath);
              
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
          if (Directory(possibleDocPath).existsSync()) {
            videosDir = Directory('$possibleDocPath/Videos');
            if (!videosDir.existsSync()) {
              videosDir.createSync();
            }
            
            final destinationPath = '${videosDir.path}/$fileName';
            final destinationFile = File(destinationPath);
            
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
        getApplicationDocumentsDirectory().then((docDir) {
          final vDir = Directory('${docDir.path}/Videos');
          if (!vDir.existsSync()) {
            vDir.createSync();
          }
          
          final destPath = '${vDir.path}/$fileName';
          final destFile = File(destPath);
          
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
    final File file = File(path);
    if (file.existsSync()) {
      return true;
    }
    
    // 处理iOS路径前缀问题
    if (Platform.isIOS) {
      String alternativePath;
      if (path.startsWith('/private')) {
        alternativePath = path.replaceFirst('/private', '');
      } else {
        alternativePath = '/private$path';
      }
      
      return File(alternativePath).existsSync();
    }
    
    return false;
  }

  // 选择视频文件
  Future<String?> pickVideoFile({String? initialDirectory}) async {
    try {
      // 获取上次目录
      initialDirectory ??= await _getLastDirectory(_lastVideoDirKey);
      
      // iOS上初始目录处理
      if (Platform.isIOS && (initialDirectory == null || initialDirectory.isEmpty)) {
        try {
          final Directory appDocDir = await getApplicationDocumentsDirectory();
          initialDirectory = appDocDir.path;
        } catch (e) {
          print("Error getting documents directory for iOS: $e");
        }
      }
      
      // 定义视频文件类型组
      XTypeGroup videoGroup = XTypeGroup(
        label: '视频文件',
        extensions: const ['mp4', 'mkv', 'avi', 'wmv', 'mov'],
        uniformTypeIdentifiers: Platform.isIOS 
            ? ['public.movie', 'public.video', 'public.mpeg-4', 'com.apple.quicktime-movie'] 
            : null,
      );
      
      // 打开文件选择器
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
      
      // 在iOS上检测是否是临时文件，如果是则主动复制
      if (Platform.isIOS && _isIOSTemporaryPath(filePath)) {
        print('检测到iOS临时文件路径: $filePath');
        
        // 尝试直接复制文件到文档目录
        try {
          final Directory appDocDir = await getApplicationDocumentsDirectory();
          final videosDir = Directory('${appDocDir.path}/Videos');
          if (!videosDir.existsSync()) {
            videosDir.createSync(recursive: true);
          }
          
          final fileName = p.basename(filePath);
          final destinationPath = '${videosDir.path}/$fileName';
          
          // 确保源文件存在
          if (!File(filePath).existsSync() && !File('/private$filePath').existsSync()) {
            print('警告: 源文件不存在: $filePath');
            // 仍然保存路径，但返回原路径
          } else {
            // 确定正确的源文件路径
            final sourceFilePath = File(filePath).existsSync() ? filePath : '/private$filePath';
            final sourceFile = File(sourceFilePath);
            final destinationFile = File(destinationPath);
            
            // 检查文件是否已存在，避免重复复制
            if (!destinationFile.existsSync() || 
                destinationFile.lengthSync() != sourceFile.lengthSync()) {
              print('复制文件到持久存储中...');
              sourceFile.copySync(destinationPath);
              print('已复制文件到持久存储: $destinationPath');
              
              // 更新文件路径为持久化存储路径
              filePath = destinationPath;
            } else {
              print('文件已存在于持久存储中: $destinationPath');
              filePath = destinationPath;
            }
          }
        } catch (e) {
          print('复制文件到持久存储失败: $e');
          // 出错时仍使用原路径
        }
      }
      
      // 保存目录位置
      _saveLastDirectory(p.dirname(file.path), _lastVideoDirKey);
      _saveLastDirectory(p.dirname(file.path), _lastDirKey);
      
      return _normalizePath(filePath);
    } catch (e) {
      print('选择视频文件失败: $e');
      return null;
    }
  }

  // 选择字幕文件
  Future<String?> pickSubtitleFile({String? initialDirectory}) async {
    try {
      // 获取上次目录
      initialDirectory ??= await _getLastDirectory(_lastSubtitleDirKey);
      
      // 定义字幕文件类型组
      XTypeGroup subtitleGroup = XTypeGroup(
        label: '字幕文件',
        extensions: const ['srt', 'ass', 'ssa', 'sub'],
        uniformTypeIdentifiers: Platform.isIOS 
            ? ['public.text', 'public.plain-text'] 
            : null,
      );
      
      // 打开文件选择器
      final XFile? file = await openFile(
        acceptedTypeGroups: [subtitleGroup],
        initialDirectory: initialDirectory,
        confirmButtonText: '选择字幕文件',
      );
      
      if (file == null) {
        return null;
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
      
      // iOS上的特殊处理
      if (Platform.isIOS) {
        // iOS上目前file_selector的getDirectoryPath功能受限
        // 仅返回文档目录
        try {
          final Directory appDocDir = await getApplicationDocumentsDirectory();
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
        
        // 保存选择的目录
        _saveLastDirectory(selectedDirectory, _lastDirKey);
        
        return _normalizePath(selectedDirectory);
      }
    } catch (e) {
      print('选择文件夹失败: $e');
      return null;
    }
  }
  
  // 保存上次目录
  Future<void> _saveLastDirectory(String path, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, path);
    } catch (e) {
      print('保存上次目录失败: $e');
    }
  }
  
  // 获取上次目录
  Future<String?> _getLastDirectory(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (e) {
      print('获取上次目录失败: $e');
      return null;
    }
  }
  
  // 获取文件的有效路径(处理iOS路径问题)
  Future<String?> getValidFilePath(String originalPath) async {
    // 首先检查原始路径是否可访问
    if (File(originalPath).existsSync()) {
      return originalPath;
    }
    
    // 处理iOS的/private前缀
    if (Platform.isIOS) {
      String alternativePath;
      if (originalPath.startsWith('/private')) {
        alternativePath = originalPath.replaceFirst('/private', '');
      } else {
        alternativePath = '/private$originalPath';
      }
      
      if (File(alternativePath).existsSync()) {
        return alternativePath;
      }
      
      // 检查文件是否可能在文档目录中
      try {
        final Directory appDocDir = await getApplicationDocumentsDirectory();
        final fileName = p.basename(originalPath);
        final docPath = '${appDocDir.path}/Videos/$fileName';
        
        if (File(docPath).existsSync()) {
          return docPath;
        }
      } catch (e) {
        print("检查文档目录中的文件失败: $e");
      }
    }
    
    return null; // 找不到有效路径
  }
} 