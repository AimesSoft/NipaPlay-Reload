import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:nipaplay/models/watch_history_model.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:nipaplay/widgets/blur_dialog.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart'; // Import Ionicons
import '../services/file_picker_service.dart';
import '../utils/globals.dart' as globals;

class LibraryManagementTab extends StatefulWidget {
  final void Function(WatchHistoryItem item) onPlayEpisode;

  const LibraryManagementTab({super.key, required this.onPlayEpisode});

  @override
  State<LibraryManagementTab> createState() => _LibraryManagementTabState();
}

class _LibraryManagementTabState extends State<LibraryManagementTab> {
  static const String _lastScannedDirectoryPickerPathKey = 'last_scanned_dir_picker_path';

  final Map<String, List<FileSystemEntity>> _expandedFolderContents = {};
  final Set<String> _loadingFolders = {};
  final ScrollController _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    
    // 在initState中保存ScanService引用，避免在dispose中不安全访问Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scanService = Provider.of<ScanService>(context, listen: false);
      _scanService = scanService; // 保存引用
      scanService.addListener(_checkScanResults);
    });
  }

  // 存储ScanService引用
  ScanService? _scanService;

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

    // --- Mobile Platform Logic (iOS & Android) ---
    if (globals.isPhone) {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      await scanService.startDirectoryScan(appDocDir.path, skipPreviouslyMatchedUnwatched: false); // Ensure full scan for new folder
      return; 
    }
    // --- End Mobile Platform Logic ---

    // 使用FilePickerService选择目录（桌面平台）
    final filePickerService = FilePickerService();
    final selectedDirectory = await filePickerService.pickDirectory();

    if (selectedDirectory == null) {
      if (mounted) {
        BlurSnackBar.show(context, "未选择文件夹。");
      }
      return;
    }

    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String appDocPath = appDocDir.path;

    // Normalize paths to handle potential '/private' prefix discrepancy on iOS
    String effectiveSelectedDir = selectedDirectory;
    if (selectedDirectory.startsWith('/private') && !appDocPath.startsWith('/private')) {
      // If selected has /private but appDocPath doesn't, selected might be /private/var... and appDocPath /var...
      // No change needed for selectedDirectory here, comparison logic will handle it.
    } else if (!selectedDirectory.startsWith('/private') && appDocPath.startsWith('/private')) {
      // If selected doesn't have /private but appDocPath does, this is unusual, but we adapt.
      // This case is less likely if appDocDir.path is from path_provider.
    }

    // The core comparison: selected path must start with appDocPath OR /private + appDocPath
    bool isInternalPath = selectedDirectory.startsWith(appDocPath) || 
                          (appDocPath.startsWith('/var') && selectedDirectory.startsWith('/private$appDocPath'));

    if (globals.isPhone && !isInternalPath) {
      if (mounted) {
        String dialogContent = "您选择的文件夹位于应用外部。\n\n";
        dialogContent += "为了正常扫描和管理媒体文件，请将文件或文件夹拷贝到应用的专属文件夹中。\n\n";
        
        if (Platform.isIOS) {
          dialogContent += "您可以在\"文件\"应用中，导航至\"我的 iPhone / iPad\" > \"NipaPlay\"找到此文件夹。\n\n";
        } else if (Platform.isAndroid) {
          dialogContent += "您可以将文件复制到 Android/data/com.aimessoft.nipaplay 文件夹中。\n\n";
        }
        
        dialogContent += "这是由于移动平台的安全和权限机制，确保应用仅能访问您明确置于其管理区域内的数据。";

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
    contents.sort((a, b) {
      if (a is Directory && b is File) return -1;
      if (a is File && b is Directory) return 1;
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });
    return contents;
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

  // 检查扫描结果，如果没有找到视频文件，显示指导弹窗
  void _checkScanResults() {
    final scanService = Provider.of<ScanService>(context, listen: false);
    
    // 只在扫描刚结束时检查
    if (!scanService.isScanning && scanService.justFinishedScanning) {
      // 重置标志
      scanService.resetJustFinishedScanning();
      
      // 如果没有文件，或者扫描文件夹为空，显示指导弹窗
      if ((scanService.totalFilesFound == 0 || scanService.scannedFolders.isEmpty) && mounted) {
        _showFileImportGuideDialog();
      }
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
      dialogContent += "1. 使用文件管理器应用\n";
      dialogContent += "2. 浏览到您的视频文件所在位置\n";
      dialogContent += "3. 复制视频文件\n";
      dialogContent += "4. 导航到「内部存储 > Android > data > com.aimessoft.nipaplay > files」\n";
      dialogContent += "5. 粘贴文件到此文件夹中\n\n";
      dialogContent += "或者：\n";
      dialogContent += "1. 将手机连接到电脑\n";
      dialogContent += "2. 通过USB传输模式复制视频到应用文件夹\n";
    }
    
    dialogContent += "\n添加完文件后，点击上方的「扫描NipaPlay文件夹」按钮刷新媒体库。";
    
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
              IconButton(
                icon: const Icon(Ionicons.refresh_outline),
                tooltip: '刷新所有媒体库',
                color: Colors.white70,
                onPressed: scanService.isScanning 
                    ? null 
                    : () async {
                        final confirm = await BlurDialog.show<bool>(
                          context: context,
                          title: '确认刷新',
                          content: '将重新扫描所有已添加的媒体文件夹（跳过已匹配且未观看的），这可能需要一些时间。',
                          actions: <Widget>[
                            TextButton(
                              child: const Text('取消', style: TextStyle(color: Colors.white70)),
                              onPressed: () => Navigator.of(context).pop(false),
                            ),
                            TextButton(
                              child: const Text('全部刷新', style: TextStyle(color: Colors.lightBlueAccent)),
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
                  child: Text(
                    globals.isPhone ? '扫描NipaPlay文件夹' : '添加并扫描文件夹',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
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
                                        content: '将对文件夹 "${p.basename(folderPath)}" 进行全面扫描，这可能需要一些时间。',
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
                                          BlurSnackBar.show(context, '已开始全面扫描: ${p.basename(folderPath)}');
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
                                          content: '将对文件夹 "${p.basename(folderPath)}" 进行全面扫描，这可能需要一些时间。',
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
                                            BlurSnackBar.show(context, '已开始全面扫描: ${p.basename(folderPath)}');
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
} 