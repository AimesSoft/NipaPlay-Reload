import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui';
import 'package:path/path.dart' as p;
import 'package:nipaplay/models/watch_history_model.dart';
import 'dart:async';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:nipaplay/widgets/blur_dialog.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart'; // Import Ionicons
import '../services/file_picker_service.dart';
import '../utils/storage_service.dart'; // 导入StorageService
import 'package:permission_handler/permission_handler.dart'; // 导入权限处理库
import '../utils/android_storage_helper.dart'; // 导入Android存储辅助类
// Import MethodChannel
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences

class LibraryManagementTab extends StatefulWidget {
  final void Function(WatchHistoryItem item) onPlayEpisode;

  const LibraryManagementTab({super.key, required this.onPlayEpisode});

  @override
  State<LibraryManagementTab> createState() => _LibraryManagementTabState();
}

class _LibraryManagementTabState extends State<LibraryManagementTab> {
  static const String _lastScannedDirectoryPickerPathKey = 'last_scanned_dir_picker_path';
  static const String _librarySortOptionKey = 'library_sort_option'; // 新增键用于保存排序选项

  final Map<String, List<FileSystemEntity>> _expandedFolderContents = {};
  final Set<String> _loadingFolders = {};
  final ScrollController _listScrollController = ScrollController();
  
  // 存储ScanService引用
  ScanService? _scanService;

  // 排序相关状态
  int _sortOption = 0; // 0: 文件名升序, 1: 文件名降序, 2: 修改时间升序, 3: 修改时间降序, 4: 大小升序, 5: 大小降序

  @override
  void initState() {
    super.initState();
    
    // 延迟初始化，确保挂载完成
    _initScanServiceListener();
    
    // 加载保存的排序选项
    _loadSortOption();
  }
  
  // 提取为单独的方法，方便管理生命周期
  void _initScanServiceListener() {
    // 使用微任务确保在当前渲染帧结束后执行
    Future.microtask(() {
      // 确保组件仍然挂载
      if (!mounted) return;
      
      try {
        final scanService = Provider.of<ScanService>(context, listen: false);
        _scanService = scanService; // 保存引用
        print('初始化ScanService监听器开始');
        scanService.addListener(_checkScanResults);
        print('ScanService监听器添加成功');
      } catch (e) {
        print('初始化ScanService监听器失败: $e');
      }
    });
  }

  @override
  void dispose() {
    // 安全移除监听器，使用保存的引用
    if (_scanService != null) {
      _scanService!.removeListener(_checkScanResults);
    }
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickAndScanDirectory() async {
    final scanService = Provider.of<ScanService>(context, listen: false);
    if (scanService.isScanning) {
      BlurSnackBar.show(context, '已有扫描任务在进行中，请稍后。');
      return;
    }

    // --- iOS平台逻辑 ---
    if (Platform.isIOS) {
      // 使用StorageService获取应用存储目录
      final Directory appDir = await StorageService.getAppStorageDirectory();
      await scanService.startDirectoryScan(appDir.path, skipPreviouslyMatchedUnwatched: false); // Ensure full scan for new folder
      return; 
    }
    // --- End iOS平台逻辑 ---
    
    // Android和桌面平台分开处理
    if (Platform.isAndroid) {
      // 获取Android版本
      final int sdkVersion = await AndroidStorageHelper.getAndroidSDKVersion();
      
      // Android 13+：使用媒体API扫描视频文件
      if (sdkVersion >= 33) {
        await _scanAndroidMediaFolders();
        return;
      }
      
      // Android 13以下：允许自由选择文件夹
      // 检查并请求所有必要的权限...
      // 保留原来的权限请求代码
    }
    
    // Android 13以下和桌面平台继续使用原来的文件选择器逻辑
    // 使用FilePickerService选择目录（适用于Android和桌面平台）
    String? selectedDirectory;
    try {
      final filePickerService = FilePickerService();
      selectedDirectory = await filePickerService.pickDirectory();
      
      if (selectedDirectory == null) {
        if (mounted) {
          BlurSnackBar.show(context, "未选择文件夹。");
        }
        return;
      }
      
             // 验证选择的目录是否可访问
      bool accessCheck = false;
      if (Platform.isAndroid) {
        // 使用原生方法检查目录权限
        final dirCheck = await AndroidStorageHelper.checkDirectoryPermissions(selectedDirectory);
        accessCheck = dirCheck['canRead'] == true && dirCheck['canWrite'] == true;
        debugPrint('Android目录权限检查结果: $dirCheck');
      } else {
        // 非Android平台使用Flutter方法检查
        accessCheck = await StorageService.isValidStorageDirectory(selectedDirectory);
      }
      if (!accessCheck && mounted) {
        BlurDialog.show<void>(
          context: context,
          title: "文件夹访问受限",
          content: "无法访问您选择的文件夹，可能是权限问题。\n\n如果您使用的是Android 11或更高版本，请考虑在设置中开启「管理所有文件」权限。",
          actions: <Widget>[
            TextButton(
              child: const Text("知道了", style: TextStyle(color: Colors.white70)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("打开设置", style: TextStyle(color: Colors.lightBlueAccent)),
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
            ),
          ],
        );
        return;
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, "选择文件夹时出错: $e");
      }
      return;
    }

    // 仅iOS平台需要检查是否为内部路径
    if (Platform.isIOS) {
      final Directory appDir = await StorageService.getAppStorageDirectory();
      final String appPath = appDir.path;
  
      // Normalize paths to handle potential '/private' prefix discrepancy on iOS
      String effectiveSelectedDir = selectedDirectory;
      if (selectedDirectory.startsWith('/private') && !appPath.startsWith('/private')) {
        // If selected has /private but appPath doesn't, selected might be /private/var... and appPath /var...
        // No change needed for selectedDirectory here, comparison logic will handle it.
      } else if (!selectedDirectory.startsWith('/private') && appPath.startsWith('/private')) {
        // If selected doesn't have /private but appPath does, this is unusual, but we adapt.
        // This case is less likely if appDir.path is from StorageService.
      }
  
      // The core comparison: selected path must start with appPath OR /private + appPath
      bool isInternalPath = selectedDirectory.startsWith(appPath) || 
                            (appPath.startsWith('/var') && selectedDirectory.startsWith('/private$appPath'));
  
      if (!isInternalPath) {
        if (mounted) {
          String dialogContent = "您选择的文件夹位于应用外部。\n\n";
          dialogContent += "为了正常扫描和管理媒体文件，请将文件或文件夹拷贝到应用的专属文件夹中。\n\n";
          dialogContent += "您可以在\"文件\"应用中，导航至\"我的 iPhone / iPad\" > \"NipaPlay\"找到此文件夹。\n\n";
          dialogContent += "这是由于iOS的安全和权限机制，确保应用仅能访问您明确置于其管理区域内的数据。";
  
          BlurDialog.show<void>(
            context: context,
            title: "访问提示 ",
            content: dialogContent,
            actions: <Widget>[
              TextButton(
                child: const Text("知道了", style: TextStyle(color: Colors.lightBlueAccent)),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        }
        return;
      }
    }
    
    // Android平台检查是否有访问所选文件夹的权限
    if (Platform.isAndroid) {
      try {
        // 尝试读取文件夹内容以检查权限
        final dir = Directory(selectedDirectory);
        await dir.list().first.timeout(const Duration(seconds: 2), onTimeout: () {
          throw TimeoutException('无法访问文件夹');
        });
      } catch (e) {
        if (mounted) {
          BlurDialog.show<void>(
            context: context,
            title: "访问错误",
            content: "无法访问所选文件夹，可能是权限问题。\n\n建议选择您的个人文件夹或媒体文件夹，如Pictures、Download或Movies。\n\n错误: ${e.toString().substring(0, min(e.toString().length, 100))}",
            actions: <Widget>[
              TextButton(
                child: const Text("知道了", style: TextStyle(color: Colors.lightBlueAccent)),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        }
        return;
      }
    }

    // 保存用户选择的自定义路径
    await StorageService.saveCustomStoragePath(selectedDirectory);
    // 开始扫描目录
    await scanService.startDirectoryScan(selectedDirectory, skipPreviouslyMatchedUnwatched: false); // Ensure full scan for new folder
  }

  Future<void> _handleRemoveFolder(String folderPathToRemove) async {
    final scanService = Provider.of<ScanService>(context, listen: false);

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '确认移除',
      content: '确定要从列表中移除文件夹 "$folderPathToRemove" 吗？\n相关的媒体记录也会被清理。',
      actions: <Widget>[
        TextButton(
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        TextButton(
          child: const Text('移除', style: TextStyle(color: Colors.redAccent)),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );

    if (confirm == true && mounted) {
      //debugPrint("User confirmed removal of: $folderPathToRemove");
      await scanService.removeScannedFolder(folderPathToRemove);
      // ScanService.removeScannedFolder will handle:
      // - Removing from its internal list and saving
      // - Cleaning WatchHistoryManager entries (once fully implemented there)
      // - Notifying listeners (which AnimePage uses to refresh WatchHistoryProvider and MediaLibraryPage)

      if (mounted) {
        BlurSnackBar.show(context, '请求已提交: $folderPathToRemove 将被移除并清理相关记录。');
      }
    }
  }

  Future<List<FileSystemEntity>> _getDirectoryContents(String path) async {
    final List<FileSystemEntity> contents = [];
    final directory = Directory(path);
    if (await directory.exists()) {
      try {
        await for (var entity in directory.list(recursive: false, followLinks: false)) {
          if (entity is Directory) {
            contents.add(entity);
          } else if (entity is File) {
            String extension = p.extension(entity.path).toLowerCase();
            if (extension == '.mp4' || extension == '.mkv') {
              contents.add(entity);
            }
          }
        }
      } catch (e) {
        //debugPrint("Error listing directory contents for $path: $e");
        if (mounted) {
          setState(() {
            // _scanMessage = "加载文件夹内容失败: $path ($e)";
          });
        }
      }
    }
    // 应用选择的排序方式
    _sortContents(contents);
    return contents;
  }

  // 排序内容的方法
  void _sortContents(List<FileSystemEntity> contents) {
    contents.sort((a, b) {
      // 总是优先显示文件夹
      if (a is Directory && b is File) return -1;
      if (a is File && b is Directory) return 1;
      
      // 同种类型文件按选择的排序方式排序
      int result = 0;
      
      switch (_sortOption) {
        case 0: // 文件名升序
          result = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          break;
        case 1: // 文件名降序
          result = p.basename(b.path).toLowerCase().compareTo(p.basename(a.path).toLowerCase());
          break;
        case 2: // 修改时间升序（旧到新）
          try {
            final aModified = a.statSync().modified;
            final bModified = b.statSync().modified;
            result = aModified.compareTo(bModified);
          } catch (e) {
            // 如果获取修改时间失败，回退到文件名排序
            result = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          }
          break;
        case 3: // 修改时间降序（新到旧）
          try {
            final aModified = a.statSync().modified;
            final bModified = b.statSync().modified;
            result = bModified.compareTo(aModified);
          } catch (e) {
            // 如果获取修改时间失败，回退到文件名排序
            result = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          }
          break;
        case 4: // 大小升序（小到大）
          try {
            final aSize = a is File ? a.lengthSync() : 0;
            final bSize = b is File ? b.lengthSync() : 0;
            result = aSize.compareTo(bSize);
          } catch (e) {
            // 如果获取大小失败，回退到文件名排序
            result = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          }
          break;
        case 5: // 大小降序（大到小）
          try {
            final aSize = a is File ? a.lengthSync() : 0;
            final bSize = b is File ? b.lengthSync() : 0;
            result = bSize.compareTo(aSize);
          } catch (e) {
            // 如果获取大小失败，回退到文件名排序
            result = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          }
          break;
        default:
          result = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      }
      
      return result;
    });
  }

  Future<void> _loadFolderChildren(String folderPath) async {
    if (mounted) {
      setState(() {
        _loadingFolders.add(folderPath);
      });
    }

    final children = await _getDirectoryContents(folderPath);

    if (mounted) {
      setState(() {
        _expandedFolderContents[folderPath] = children;
        _loadingFolders.remove(folderPath);
      });
    }
  }

  List<Widget> _buildFileSystemNodes(List<FileSystemEntity> entities, String parentPath, int depth) {
    if (entities.isEmpty && !_loadingFolders.contains(parentPath)) {
      return [Padding(
        padding: EdgeInsets.only(left: depth * 16.0 + 16.0, top: 8.0, bottom: 8.0),
        child: const Text("文件夹为空", style: TextStyle(color: Colors.white54)),
      )];
    }
    
    return entities.map<Widget>((entity) {
      final indent = EdgeInsets.only(left: depth * 16.0);
      if (entity is Directory) {
        final dirPath = entity.path;
        return Padding(
          padding: indent,
          child: ExpansionTile(
            key: PageStorageKey<String>(dirPath),
            leading: const Icon(Icons.folder_outlined, color: Colors.white70),
            title: Text(p.basename(dirPath), style: const TextStyle(color: Colors.white)),
            onExpansionChanged: (isExpanded) {
              if (isExpanded && _expandedFolderContents[dirPath] == null && !_loadingFolders.contains(dirPath)) {
                _loadFolderChildren(dirPath);
              }
            },
            children: _loadingFolders.contains(dirPath)
                ? [const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))]
                : _buildFileSystemNodes(_expandedFolderContents[dirPath] ?? [], dirPath, depth + 1),
          ),
        );
      } else if (entity is File) {
        return Padding(
          padding: indent,
          child: ListTile(
            leading: const Icon(Icons.videocam_outlined, color: Colors.tealAccent),
            title: Text(p.basename(entity.path), style: const TextStyle(color: Colors.white)),
            onTap: () {
              // Create a minimal WatchHistoryItem to initiate playback
              final WatchHistoryItem tempItem = WatchHistoryItem(
                filePath: entity.path,
                animeName: p.basenameWithoutExtension(entity.path), // Use filename as a basic anime name
                episodeTitle: '', // Can be empty, VideoPlayerState might fill it later
                duration: 0, // Will be updated by VideoPlayerState
                lastPosition: 0, // Will be updated by VideoPlayerState
                watchProgress: 0.0, // Will be updated by VideoPlayerState
                lastWatchTime: DateTime.now(), // Current time, or can be a default
                // thumbnailPath, episodeId, animeId can be null/default initially
              );
              widget.onPlayEpisode(tempItem);
              //debugPrint("Tapped on file: ${entity.path}, attempting to play.");
            },
          ),
        );
      }
      return const SizedBox.shrink();
    }).toList();
  }

  // 显示排序选择对话框
  Future<void> _showSortOptionsDialog() async {
    final List<String> sortOptions = [
      '文件名 (A→Z)',
      '文件名 (Z→A)',
      '修改时间 (旧→新)',
      '修改时间 (新→旧)',
      '文件大小 (小→大)',
      '文件大小 (大→小)',
    ];

    final result = await BlurDialog.show<int>(
      context: context,
      title: '选择排序方式',
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '选择文件夹中文件和子文件夹的排序方式：',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200, // 减少高度
            child: SingleChildScrollView(
              child: Column(
                children: sortOptions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final option = entry.value;
                  final isSelected = _sortOption == index;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    child: Material(
                      color: isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => Navigator.of(context).pop(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              if (isSelected) ...[
                                const Icon(
                                  Icons.check,
                                  color: Colors.lightBlueAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                              ] else ...[
                                const SizedBox(width: 28),
                              ],
                              Expanded(
                                child: Text(
                                  option,
                                  style: TextStyle(
                                    color: isSelected ? Colors.lightBlueAccent : Colors.white70,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );

    if (result != null && result != _sortOption && mounted) {
      setState(() {
        _sortOption = result;
        // 清空已展开的文件夹内容，强制重新加载和排序
        _expandedFolderContents.clear();
      });
      
      // 保存排序选项
      _saveSortOption(result);
      
      BlurSnackBar.show(context, '排序方式已更改为：${sortOptions[result]}');
    }
  }

  // 检查扫描结果，如果没有找到视频文件，显示指导弹窗
  void _checkScanResults() {
    // 首先检查 mounted 状态
    if (!mounted) return;
    
    try {
      final scanService = Provider.of<ScanService>(context, listen: false);
      
      print('检查扫描结果: isScanning=${scanService.isScanning}, justFinishedScanning=${scanService.justFinishedScanning}, totalFilesFound=${scanService.totalFilesFound}, scannedFolders.isEmpty=${scanService.scannedFolders.isEmpty}');
      
      // 只在扫描刚结束时检查
      if (!scanService.isScanning && scanService.justFinishedScanning) {
        print('扫描刚结束，准备检查是否显示指导弹窗');
        
        // 如果没有文件，或者扫描文件夹为空，显示指导弹窗
        if ((scanService.totalFilesFound == 0 || scanService.scannedFolders.isEmpty) && mounted) {
          print('符合条件，即将显示文件导入指导弹窗');
          _showFileImportGuideDialog();
        } else {
          print('不符合显示条件: totalFilesFound=${scanService.totalFilesFound}, scannedFolders.isEmpty=${scanService.scannedFolders.isEmpty}');
        }
        
        // 重置标志
        scanService.resetJustFinishedScanning();
      }
    } catch (e) {
      print('检查扫描结果时出错: $e');
    }
  }
  
  // 显示文件导入指导弹窗
  void _showFileImportGuideDialog() {
    if (!mounted) return;
    
    String dialogContent = "未发现任何视频文件。以下是向NipaPlay添加视频的方法：\n\n";
    
    if (Platform.isIOS) {
      dialogContent += "1. 打开iOS「文件」应用\n";
      dialogContent += "2. 浏览到包含您视频的文件夹\n";
      dialogContent += "3. 长按视频文件，选择「分享」\n";
      dialogContent += "4. 在分享菜单中选择「拷贝到NipaPlay」\n\n";
      dialogContent += "或者：\n";
      dialogContent += "1. 通过iTunes文件共享功能\n";
      dialogContent += "2. 从电脑直接拷贝视频到NipaPlay文件夹\n";
    } else if (Platform.isAndroid) {
      dialogContent += "1. 确保将视频文件存放在易于访问的文件夹中\n";
      dialogContent += "2. 您可以创建专门的文件夹，如「Movies」或「Anime」\n";
      dialogContent += "3. 确保文件夹权限设置正确，应用可以访问\n";
      dialogContent += "4. 点击上方「添加并扫描文件夹」选择您的视频文件夹\n\n";
      dialogContent += "常见问题：\n";
      dialogContent += "- 如果无法选择某个文件夹，可能是权限问题\n";
      dialogContent += "- 建议使用标准的媒体文件夹如Pictures、Movies或Documents\n";
    }
    
    if (Platform.isIOS) {
      dialogContent += "\n添加完文件后，点击上方的「扫描NipaPlay文件夹」按钮刷新媒体库。";
    } else {
      dialogContent += "\n添加完文件后，点击上方的「添加并扫描文件夹」按钮选择您存放视频的文件夹。";
    }
    
    BlurDialog.show<void>(
      context: context,
      title: "如何添加视频文件",
      content: dialogContent,
      actions: <Widget>[
        TextButton(
          child: const Text("知道了", style: TextStyle(color: Colors.lightBlueAccent)),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  // 清除自定义存储路径
  Future<void> _clearCustomStoragePath() async {
    final scanService = Provider.of<ScanService>(context, listen: false);
    if (scanService.isScanning) {
      BlurSnackBar.show(context, '已有扫描任务在进行中，请稍后操作。');
      return;
    }

    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '重置存储路径',
      content: '确定要重置存储路径吗？这将清除您之前设置的自定义路径，并使用系统默认位置。\n\n注意：这不会删除您已添加到媒体库的视频文件。',
      actions: <Widget>[
        TextButton(
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        TextButton(
          child: const Text('重置', style: TextStyle(color: Colors.redAccent)),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );

    if (confirm == true && mounted) {
      final success = await StorageService.clearCustomStoragePath();
      if (success && mounted) {
        BlurSnackBar.show(context, '存储路径已重置为默认设置');
      } else if (mounted) {
        BlurSnackBar.show(context, '重置存储路径失败');
      }
    }
  }

  // 检查并显示权限状态
  Future<void> _checkAndShowPermissionStatus() async {
    if (!Platform.isAndroid) return;
    
    // 显示加载提示
    if (mounted) {
      BlurSnackBar.show(context, '正在检查权限状态...');
    }
    
    try {
      // 获取权限状态
      final status = await AndroidStorageHelper.getAllStoragePermissionStatus();
      final int sdkVersion = status['androidVersion'] as int;
      
      // 构建状态信息
      final StringBuffer content = StringBuffer();
      content.writeln('Android 版本: $sdkVersion');
      content.writeln('基本存储权限: ${status['storage']}');
      
      if (sdkVersion >= 30) { // Android 11+
        content.writeln('\n管理所有文件权限:');
        content.writeln('- 系统API: ${status['manageExternalStorageNative']}');
        content.writeln('- permission_handler: ${status['manageExternalStorage']}');
      }
      
      if (sdkVersion >= 33) { // Android 13+
        content.writeln('\nAndroid 13+ 分类媒体权限:');
        content.writeln('- 照片访问: ${status['mediaImages']}');
        content.writeln('- 视频访问: ${status['mediaVideo']}');
        content.writeln('- 音频访问: ${status['mediaAudio']}');
      }
      
      // 显示权限状态对话框
      if (mounted) {
        BlurDialog.show<void>(
          context: context,
          title: 'Android存储权限状态',
          content: content.toString(),
          actions: <Widget>[
            TextButton(
              child: const Text('关闭', style: TextStyle(color: Colors.white70)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('申请权限', style: TextStyle(color: Colors.lightBlueAccent)),
              onPressed: () async {
                Navigator.of(context).pop();
                await AndroidStorageHelper.requestAllRequiredPermissions();
                // 延迟后再次检查权限状态
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    _checkAndShowPermissionStatus();
                  }
                });
              },
            ),
          ],
        );
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '检查权限状态失败: $e');
      }
    }
  }

  // 新增：用于Android 13+扫描媒体文件夹的方法
  Future<void> _scanAndroidMediaFolders() async {
    try {
      // 请求媒体权限
      await Permission.photos.request();
      await Permission.videos.request();
      await Permission.audio.request();
      
      bool hasMediaPermissions = 
          await Permission.photos.isGranted && 
          await Permission.videos.isGranted && 
          await Permission.audio.isGranted;
      
      if (!hasMediaPermissions && mounted) {
        BlurDialog.show<void>(
          context: context,
          title: "需要媒体权限",
          content: "NipaPlay需要访问媒体文件权限才能扫描视频文件。\n\n请在系统设置中允许NipaPlay访问照片、视频和音频权限。",
          actions: <Widget>[
            TextButton(
              child: const Text("稍后再说", style: TextStyle(color: Colors.white70)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("打开设置", style: TextStyle(color: Colors.lightBlueAccent)),
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
            ),
          ],
        );
        return;
      }
      
      // 显示加载提示
      if (mounted) {
        BlurSnackBar.show(context, '正在扫描视频文件夹，请稍候...');
      }
      
      // 获取系统媒体文件夹
      final scanService = Provider.of<ScanService>(context, listen: false);
      String? moviesPath;
      
      // 尝试获取Movies目录路径
      try {
        final externalDirs = await getExternalStorageDirectories();
        if (externalDirs != null && externalDirs.isNotEmpty) {
          String baseDir = externalDirs[0].path;
          baseDir = baseDir.substring(0, baseDir.indexOf('Android'));
          final moviesDir = Directory('${baseDir}Movies');
          
          if (await moviesDir.exists()) {
            moviesPath = moviesDir.path;
            debugPrint('找到Movies目录: $moviesPath');
          }
        }
      } catch (e) {
        debugPrint('无法获取Movies目录: $e');
      }
      
      // 如果没有找到Movies目录，尝试其他常用媒体目录
      if (moviesPath == null) {
        try {
          final externalDirs = await getExternalStorageDirectories();
          if (externalDirs != null && externalDirs.isNotEmpty) {
            String baseDir = externalDirs[0].path;
            baseDir = baseDir.substring(0, baseDir.indexOf('Android'));
            
            // 检查DCIM目录
            final dcimDir = Directory('${baseDir}DCIM');
            if (await dcimDir.exists()) {
              moviesPath = dcimDir.path;
              debugPrint('找到DCIM目录: $moviesPath');
            } else {
              // 尝试Download目录
              final downloadDir = Directory('${baseDir}Download');
              if (await downloadDir.exists()) {
                moviesPath = downloadDir.path;
                debugPrint('找到Download目录: $moviesPath');
              }
            }
          }
        } catch (e) {
          debugPrint('无法获取备选媒体目录: $e');
        }
      }
      
      // 如果仍然没有找到任何媒体目录，提示用户
      if (moviesPath == null && mounted) {
        BlurDialog.show<void>(
          context: context,
          title: "未找到视频文件夹",
          content: "无法找到系统视频文件夹。建议使用\"管理所有文件\"权限或手动选择文件夹。",
          actions: <Widget>[
            TextButton(
              child: const Text("取消", style: TextStyle(color: Colors.white70)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("开启完整权限", style: TextStyle(color: Colors.lightBlueAccent)),
              onPressed: () {
                Navigator.of(context).pop();
                AndroidStorageHelper.requestManageExternalStoragePermission();
              },
            ),
          ],
        );
        return;
      }
      
      // 扫描找到的文件夹
      if (moviesPath != null) {
        try {
          // 检查目录权限
          final dirPerms = await AndroidStorageHelper.checkDirectoryPermissions(moviesPath);
          if (dirPerms['canRead'] == true) {
            await scanService.startDirectoryScan(moviesPath, skipPreviouslyMatchedUnwatched: false);
            if (mounted) {
              BlurSnackBar.show(context, '已扫描视频文件夹: ${p.basename(moviesPath)}');
            }
          } else {
            if (mounted) {
              BlurSnackBar.show(context, '无法读取视频文件夹，请检查权限设置');
            }
          }
        } catch (e) {
          if (mounted) {
            BlurSnackBar.show(context, '扫描视频文件夹失败: ${e.toString().substring(0, min(e.toString().length, 50))}');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '扫描视频文件夹时出错: ${e.toString().substring(0, min(e.toString().length, 50))}');
      }
    }
  }

  // 加载保存的排序选项
  Future<void> _loadSortOption() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSortOption = prefs.getInt(_librarySortOptionKey) ?? 0;
      if (mounted) {
        setState(() {
          _sortOption = savedSortOption;
        });
      }
    } catch (e) {
      debugPrint('加载排序选项失败: $e');
    }
  }
  
  // 保存排序选项
  Future<void> _saveSortOption(int sortOption) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_librarySortOptionKey, sortOption);
    } catch (e) {
      debugPrint('保存排序选项失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanService = Provider.of<ScanService>(context);
    // final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false); // Keep if needed for other actions

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text("媒体文件夹", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  // 重置存储路径按钮 - 只在Android平台显示，macOS平台不支持自定义存储路径
                  if (Platform.isAndroid)
                    IconButton(
                      icon: const Icon(Icons.settings_backup_restore),
                      tooltip: '重置存储路径',
                      color: Colors.white70,
                      onPressed: scanService.isScanning ? null : _clearCustomStoragePath,
                    ),
                  if (Platform.isAndroid)
                    IconButton(
                      icon: const Icon(Icons.security),
                      tooltip: '检查权限状态',
                      color: Colors.white70,
                      onPressed: scanService.isScanning ? null : _checkAndShowPermissionStatus,
                    ),
                  IconButton(
                    icon: const Icon(Icons.cleaning_services),
                    color: Colors.white70,
                    onPressed: scanService.isScanning ? null : () async {
                      final confirm = await BlurDialog.show<bool>(
                        context: context,
                        title: '清理智能扫描缓存',
                        content: '这将清理所有文件夹的变化检测缓存，下次扫描时将重新检查所有文件夹。\n\n适用于：\n• 怀疑智能扫描遗漏了某些变化\n• 想要强制重新扫描所有文件夹\n\n确定要清理缓存吗？',
                        actions: <Widget>[
                          TextButton(
                            child: const Text('取消', style: TextStyle(color: Colors.white70)),
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                          TextButton(
                            child: const Text('清理', style: TextStyle(color: Colors.orangeAccent)),
                            onPressed: () => Navigator.of(context).pop(true),
                          ),
                        ],
                      );
                      if (confirm == true) {
                        await scanService.clearAllFolderHashCache();
                        if (mounted) {
                          BlurSnackBar.show(context, '智能扫描缓存已清理');
                        }
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Ionicons.refresh_outline),
                    color: Colors.white70,
                    onPressed: scanService.isScanning 
                        ? null 
                        : () async {
                            final confirm = await BlurDialog.show<bool>(
                              context: context,
                              title: '智能刷新确认',
                              content: '将使用智能扫描技术重新检查所有已添加的媒体文件夹：\n\n• 自动检测文件夹内容变化\n• 只扫描有新增、删除或修改文件的文件夹\n• 跳过无变化的文件夹，大幅提升扫描速度\n• 可选择跳过已匹配且未观看的文件\n\n这可能需要一些时间，但比传统全量扫描快很多。',
                              actions: <Widget>[
                                TextButton(
                                  child: const Text('取消', style: TextStyle(color: Colors.white70)),
                                  onPressed: () => Navigator.of(context).pop(false),
                                ),
                                TextButton(
                                  child: const Text('智能刷新', style: TextStyle(color: Colors.lightBlueAccent)),
                                  onPressed: () => Navigator.of(context).pop(true),
                                ),
                              ],
                            );
                            if (confirm == true) {
                              await scanService.rescanAllFolders(); // skipPreviouslyMatchedUnwatched defaults to true
                            }
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: GlassmorphicContainer(
            width: double.infinity,
            height: 50,
            borderRadius: 12,
            blur: 10,
            alignment: Alignment.center,
            border: 1,
            linearGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.05),
              ],
            ),
            borderGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.3),
                Colors.white.withOpacity(0.1),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: scanService.isScanning ? null : _pickAndScanDirectory,
                borderRadius: BorderRadius.circular(12),
                child: Center(
                  child: FutureBuilder<bool>(
                    future: Platform.isAndroid ? _isAndroid13Plus() : Future.value(false),
                    builder: (context, snapshot) {
                      String buttonText = '添加并扫描文件夹'; // 默认文本
                      
                      if (Platform.isIOS) {
                        buttonText = '扫描NipaPlay文件夹';
                      } else if (Platform.isAndroid) {
                        // 如果future完成且为true，说明是Android 13+
                        if (snapshot.hasData && snapshot.data == true) {
                          buttonText = '扫描视频文件夹';
                        } else {
                          buttonText = '添加并扫描文件夹';
                        }
                      }
                      
                      return Text(
                        buttonText,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (scanService.isScanning || scanService.scanMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scanService.scanMessage, style: const TextStyle(color: Colors.white70)),
                if (scanService.isScanning && scanService.scanProgress > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: LinearProgressIndicator(
                      value: scanService.scanProgress,
                      backgroundColor: Colors.grey[700],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.lightBlueAccent),
                    ),
                  ),
              ],
            ),
          ),
        // 显示启动时检测到的变化
        if (scanService.detectedChanges.isNotEmpty && !scanService.isScanning)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: GlassmorphicContainer(
              width: double.infinity,
              height: 50,
              borderRadius: 12,
              blur: 10,
              alignment: Alignment.centerLeft,
              border: 1,
              linearGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.orange.withOpacity(0.15),
                  Colors.orange.withOpacity(0.05),
                ],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.orange.withOpacity(0.3),
                  Colors.orange.withOpacity(0.1),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notification_important, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          "检测到文件夹变化",
                          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => scanService.clearDetectedChanges(),
                          child: const Text("忽略", style: TextStyle(color: Colors.white70)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      scanService.getChangeDetectionSummary(),
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    ...scanService.detectedChanges.map((change) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  change.displayName,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  change.changeDescription,
                                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              // 扫描这个有变化的文件夹
                              await scanService.startDirectoryScan(change.folderPath, skipPreviouslyMatchedUnwatched: false);
                              if (mounted) {
                                BlurSnackBar.show(context, '已开始扫描: ${change.displayName}');
                              }
                            },
                            child: const Text("扫描", style: TextStyle(color: Colors.lightBlueAccent)),
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              // 扫描所有有变化的文件夹
                              for (final change in scanService.detectedChanges) {
                                if (change.changeType != 'deleted') {
                                  await scanService.startDirectoryScan(change.folderPath, skipPreviouslyMatchedUnwatched: false);
                                }
                              }
                              scanService.clearDetectedChanges();
                              if (mounted) {
                                BlurSnackBar.show(context, '已开始扫描所有有变化的文件夹');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.lightBlueAccent.withOpacity(0.2),
                              foregroundColor: Colors.lightBlueAccent,
                            ),
                            child: const Text("扫描所有变化"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        // 排序选项按钮
        if (scanService.scannedFolders.isNotEmpty || scanService.isScanning)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                const Text('排序方式：', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _showSortOptionsDialog,
                  icon: const Icon(Icons.sort, color: Colors.white, size: 18),
                  label: Text(
                    [
                      '文件名 (A→Z)',
                      '文件名 (Z→A)',
                      '修改时间 (旧→新)',
                      '修改时间 (新→旧)',
                      '文件大小 (小→大)',
                      '文件大小 (大→小)',
                    ][_sortOption],
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: scanService.scannedFolders.isEmpty && !scanService.isScanning
              ? const Center(child: Text('尚未添加任何扫描文件夹。\n点击上方按钮添加。', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)))
              : Platform.isAndroid || Platform.isIOS
                ? ListView.builder(
                    controller: _listScrollController,
                    itemCount: scanService.scannedFolders.length,
                    itemBuilder: (context, index) {
                      final folderPath = scanService.scannedFolders[index];
                      return ExpansionTile(
                        key: PageStorageKey<String>(folderPath),
                        leading: const Icon(Icons.folder_open_outlined, color: Colors.white70),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.basename(folderPath),
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            folderPath,
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              constraints: const BoxConstraints(),
                              onPressed: scanService.isScanning ? null : () => _handleRemoveFolder(folderPath),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              constraints: const BoxConstraints(),
                              onPressed: scanService.isScanning 
                                  ? null 
                                  : () async {
                                      if (scanService.isScanning) {
                                        BlurSnackBar.show(context, '已有扫描任务在进行中。');
                                        return;
                                      }
                                      final confirm = await BlurDialog.show<bool>(
                                        context: context,
                                        title: '确认扫描',
                                        content: '将对文件夹 "${p.basename(folderPath)}" 进行智能扫描：\n\n• 检测文件夹内容是否有变化\n• 如无变化将快速跳过\n• 如有变化将进行全面扫描\n\n开始扫描？',
                                        actions: <Widget>[
                                          TextButton(
                                            child: const Text('取消', style: TextStyle(color: Colors.white70)),
                                            onPressed: () => Navigator.of(context).pop(false),
                                          ),
                                          TextButton(
                                            child: const Text('扫描', style: TextStyle(color: Colors.lightBlueAccent)),
                                            onPressed: () => Navigator.of(context).pop(true),
                                          ),
                                        ],
                                      );
                                      if (confirm == true) {
                                        await scanService.startDirectoryScan(folderPath, skipPreviouslyMatchedUnwatched: false);
                                        if (mounted) {
                                          BlurSnackBar.show(context, '已开始智能扫描: ${p.basename(folderPath)}');
                                        }
                                      }
                                    },
                            ),
                          ],
                        ),
                        onExpansionChanged: (isExpanded) {
                          if (isExpanded && _expandedFolderContents[folderPath] == null && !_loadingFolders.contains(folderPath)) {
                            _loadFolderChildren(folderPath);
                          }
                        },
                        children: _loadingFolders.contains(folderPath)
                            ? [const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))]
                            : _buildFileSystemNodes(_expandedFolderContents[folderPath] ?? [], folderPath, 1),
                      );
                    },
                  )
                : Scrollbar(
                    controller: _listScrollController,
                    radius: const Radius.circular(2),
                    thickness: 4,
                    child: ListView.builder(
                      controller: _listScrollController,
                      itemCount: scanService.scannedFolders.length,
                      itemBuilder: (context, index) {
                        final folderPath = scanService.scannedFolders[index];
                        return ExpansionTile(
                          key: PageStorageKey<String>(folderPath),
                          leading: const Icon(Icons.folder_open_outlined, color: Colors.white70),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.basename(folderPath),
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              folderPath,
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
                                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                constraints: const BoxConstraints(),
                                onPressed: scanService.isScanning ? null : () => _handleRemoveFolder(folderPath),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
                                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                constraints: const BoxConstraints(),
                                onPressed: scanService.isScanning 
                                    ? null 
                                    : () async {
                                        if (scanService.isScanning) {
                                          BlurSnackBar.show(context, '已有扫描任务在进行中。');
                                          return;
                                        }
                                        final confirm = await BlurDialog.show<bool>(
                                          context: context,
                                          title: '确认扫描',
                                          content: '将对文件夹 "${p.basename(folderPath)}" 进行智能扫描：\n\n• 检测文件夹内容是否有变化\n• 如无变化将快速跳过\n• 如有变化将进行全面扫描\n\n开始扫描？',
                                          actions: <Widget>[
                                            TextButton(
                                              child: const Text('取消', style: TextStyle(color: Colors.white70)),
                                              onPressed: () => Navigator.of(context).pop(false),
                                            ),
                                            TextButton(
                                              child: const Text('扫描', style: TextStyle(color: Colors.lightBlueAccent)),
                                              onPressed: () => Navigator.of(context).pop(true),
                                            ),
                                          ],
                                        );
                                        if (confirm == true) {
                                          await scanService.startDirectoryScan(folderPath, skipPreviouslyMatchedUnwatched: false);
                                          if (mounted) {
                                            BlurSnackBar.show(context, '已开始智能扫描: ${p.basename(folderPath)}');
                                          }
                                        }
                                      },
                              ),
                            ],
                          ),
                          onExpansionChanged: (isExpanded) {
                            if (isExpanded && _expandedFolderContents[folderPath] == null && !_loadingFolders.contains(folderPath)) {
                              _loadFolderChildren(folderPath);
                            }
                          },
                          children: _loadingFolders.contains(folderPath)
                              ? [const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))]
                              : _buildFileSystemNodes(_expandedFolderContents[folderPath] ?? [], folderPath, 1),
                        );
                      },
                    ),
                  ),
        ),
      ],
    );
  }

  // 辅助方法：检查是否为Android 13+
  Future<bool> _isAndroid13Plus() async {
    if (!Platform.isAndroid) return false;
    final int sdkVersion = await AndroidStorageHelper.getAndroidSDKVersion();
    return sdkVersion >= 33;
  }
} 