import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:nipaplay/models/watch_history_model.dart';
import 'dart:async';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nipaplay/utils/android_storage_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

class FluentLibraryManagementTab extends StatefulWidget {
  final void Function(WatchHistoryItem item) onPlayEpisode;

  const FluentLibraryManagementTab({super.key, required this.onPlayEpisode});

  @override
  State<FluentLibraryManagementTab> createState() => _FluentLibraryManagementTabState();
}

class _FluentLibraryManagementTabState extends State<FluentLibraryManagementTab> {
  static const String _librarySortOptionKey = 'library_sort_option';

  final Map<String, List<io.FileSystemEntity>> _expandedFolderContents = {};
  final Set<String> _loadingFolders = {};
  final ScrollController _listScrollController = ScrollController();
  
  ScanService? _scanService;
  int _sortOption = 0; // 0: Name Asc, 1: Name Desc, 2: Date Asc, 3: Date Desc, etc.

  @override
  void initState() {
    super.initState();
    _initScanServiceListener();
    _loadSortOption();
  }

  void _initScanServiceListener() {
    Future.microtask(() {
      if (!mounted) return;
      try {
        final scanService = Provider.of<ScanService>(context, listen: false);
        _scanService = scanService;
        scanService.addListener(_onScanServiceUpdate);
      } catch (e) {
        debugPrint('Error initializing ScanService listener: $e');
      }
    });
  }
  
  void _onScanServiceUpdate() {
    // Just rebuild to reflect the latest state from ScanService
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _scanService?.removeListener(_onScanServiceUpdate);
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSortOption() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _sortOption = prefs.getInt(_librarySortOptionKey) ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Failed to load sort option: $e');
    }
  }

  Future<void> _saveSortOption(int option) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_librarySortOptionKey, option);
    } catch (e) {
      debugPrint('Failed to save sort option: $e');
    }
  }

  Future<void> _pickAndScanDirectory() async {
    final scanService = Provider.of<ScanService>(context, listen: false);
    if (scanService.isScanning) {
      _showInfoBar('已有扫描任务在进行中，请稍后。', severity: InfoBarSeverity.warning);
      return;
    }

    if (io.Platform.isIOS) {
      final io.Directory appDir = await StorageService.getAppStorageDirectory();
      await scanService.startDirectoryScan(appDir.path, skipPreviouslyMatchedUnwatched: false);
      return;
    }

    if (io.Platform.isAndroid) {
      final int sdkVersion = await AndroidStorageHelper.getAndroidSDKVersion();
      if (sdkVersion >= 33) {
        await _scanAndroidMediaFolders();
        return;
      }
    }

    String? selectedDirectory;
    try {
      final filePickerService = FilePickerService();
      selectedDirectory = await filePickerService.pickDirectory();
      
      if (selectedDirectory == null) {
        _showInfoBar("未选择文件夹。", severity: InfoBarSeverity.info);
        return;
      }
      
      await StorageService.saveCustomStoragePath(selectedDirectory);
      await scanService.startDirectoryScan(selectedDirectory, skipPreviouslyMatchedUnwatched: false);

    } catch (e) {
      _showInfoBar("选择文件夹时出错: $e", severity: InfoBarSeverity.error);
    }
  }
  
  Future<void> _scanAndroidMediaFolders() async {
      // This is a simplified version. A full implementation would require more UI/UX for permissions.
      final scanService = Provider.of<ScanService>(context, listen: false);
      _showInfoBar('正在扫描视频文件夹...', severity: InfoBarSeverity.info);
      try {
        final moviesDir = await getExternalStorageDirectories(type: StorageDirectory.movies);
        if (moviesDir != null && moviesDir.isNotEmpty) {
            await scanService.startDirectoryScan(moviesDir.first.path, skipPreviouslyMatchedUnwatched: false);
        } else {
            _showInfoBar('未找到系统视频文件夹。', severity: InfoBarSeverity.warning);
        }
      } catch (e) {
         _showInfoBar('扫描视频文件夹失败: $e', severity: InfoBarSeverity.error);
      }
  }

  Future<void> _handleRemoveFolder(String folderPath) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('确认移除'),
        content: Text('确定要从列表中移除文件夹 "$folderPath" 吗？\n相关的媒体记录也会被清理。'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            style: ButtonStyle(backgroundColor: ButtonState.all(Colors.red)),
            child: const Text('移除'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      await _scanService?.removeScannedFolder(folderPath);
      _showInfoBar('请求已提交: $folderPath 将被移除并清理相关记录。', severity: InfoBarSeverity.success);
    }
  }

  void _sortContents(List<io.FileSystemEntity> contents) {
    contents.sort((a, b) {
      if (a is io.Directory && b is io.File) return -1;
      if (a is io.File && b is io.Directory) return 1;
      
      int result = 0;
      switch (_sortOption) {
        case 0: result = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()); break;
        case 1: result = p.basename(b.path).toLowerCase().compareTo(p.basename(a.path).toLowerCase()); break;
        case 2: result = a.statSync().modified.compareTo(b.statSync().modified); break;
        case 3: result = b.statSync().modified.compareTo(a.statSync().modified); break;
        case 4: result = (a is io.File ? a.lengthSync() : 0).compareTo(b is io.File ? b.lengthSync() : 0); break;
        case 5: result = (b is io.File ? b.lengthSync() : 0).compareTo(a is io.File ? a.lengthSync() : 0); break;
      }
      return result;
    });
  }

  Future<void> _loadFolderChildren(String folderPath) async {
    if (mounted) setState(() => _loadingFolders.add(folderPath));
    
    final List<io.FileSystemEntity> contents = [];
    try {
        final dir = io.Directory(folderPath);
        if (await dir.exists()) {
            await for (var entity in dir.list(recursive: false, followLinks: false)) {
                if (entity is io.Directory || (entity is io.File && (p.extension(entity.path).toLowerCase() == '.mp4' || p.extension(entity.path).toLowerCase() == '.mkv'))) {
                    contents.add(entity);
                }
            }
        }
    } catch (e) {
        debugPrint("Error listing directory $folderPath: $e");
    }

    _sortContents(contents);

    if (mounted) {
      setState(() {
        _expandedFolderContents[folderPath] = contents;
        _loadingFolders.remove(folderPath);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Center(
        child: Text('媒体文件夹管理功能在Web浏览器中不可用。'),
      );
    }

    final scanService = Provider.of<ScanService>(context);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('媒体文件夹'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.sort),
              label: const Text('排序'),
              onPressed: _showSortOptionsDialog,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('智能刷新'),
              onPressed: scanService.isScanning ? null : () async {
                await scanService.rescanAllFolders();
              },
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('添加文件夹'),
              onPressed: scanService.isScanning ? null : _pickAndScanDirectory,
            ),
          ],
        ),
      ),
      content: Column(
        children: [
          if (scanService.isScanning || scanService.scanMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: InfoBar(
                title: Text(scanService.isScanning ? '正在扫描...' : '扫描信息'),
                content: Text(scanService.scanMessage),
                severity: scanService.isScanning ? InfoBarSeverity.info : InfoBarSeverity.success,
                action: scanService.isScanning && scanService.scanProgress > 0
                    ? ProgressBar(value: scanService.scanProgress * 100)
                    : null,
              ),
            ),
          Expanded(
            child: _buildFolderList(scanService),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderList(ScanService scanService) {
    if (scanService.scannedFolders.isEmpty && !scanService.isScanning) {
      return const Center(child: Text('尚未添加任何扫描文件夹。\n点击上方按钮添加。', textAlign: TextAlign.center));
    }

    // 检测是否为桌面或平板设备
    if (isDesktopOrTablet) {
      // 桌面和平板设备使用真正的瀑布流布局
      return SingleChildScrollView(
        controller: _listScrollController,
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 计算每行可以容纳的项目数（最小宽度300px）
            const minItemWidth = 300.0;
            final crossAxisCount = (constraints.maxWidth / minItemWidth).floor().clamp(1, 3);

            return _buildWaterfallLayout(
              scanService,
              constraints.maxWidth,
              300.0,
              16.0,
            );
          },
        ),
      );
    } else {
      // 移动设备使用单列ListView
      return ListView.builder(
        controller: _listScrollController,
        itemCount: scanService.scannedFolders.length,
        itemBuilder: (context, index) {
          final folderPath = scanService.scannedFolders[index];
          return _buildFolderExpander(folderPath, scanService);
        },
      );
    }
  }

  // 真正的瀑布流布局组件
  Widget _buildWaterfallLayout(ScanService scanService, double maxWidth, double minItemWidth, double spacing) {
    // 预留边距防止溢出
    final availableWidth = maxWidth - 16.0; // 留出16px的安全边距

    // 计算列数
    final crossAxisCount = (availableWidth / minItemWidth).floor().clamp(1, 3);

    // 重新计算间距和项目宽度
    final totalSpacing = spacing * (crossAxisCount - 1);
    final itemWidth = (availableWidth - totalSpacing) / crossAxisCount;

    // 创建列的文件夹列表
    final columnFolders = <List<String>>[];
    for (var i = 0; i < crossAxisCount; i++) {
      columnFolders.add([]);
    }

    // 按列分配文件夹
    for (var i = 0; i < scanService.scannedFolders.length; i++) {
      final columnIndex = i % crossAxisCount;
      columnFolders[columnIndex].add(scanService.scannedFolders[i]);
    }

    // 创建列组件
    final columnWidgets = <Widget>[];
    for (var i = 0; i < crossAxisCount; i++) {
      if (columnFolders[i].isNotEmpty) {
        columnWidgets.add(
          SizedBox(
            width: itemWidth,
            child: Column(
              children: columnFolders[i].map((folderPath) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _buildFolderExpander(folderPath, scanService),
                );
              }).toList(),
            ),
          ),
        );
      }
    }

    // 使用Row排列列，添加间距
    final rowChildren = <Widget>[];
    for (var i = 0; i < columnWidgets.length; i++) {
      if (i > 0) {
        rowChildren.add(SizedBox(width: spacing)); // 添加列间距
      }
      rowChildren.add(columnWidgets[i]);
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowChildren,
        ),
      ),
    );
  }

  // 统一的文件夹Expander构建方法
  Widget _buildFolderExpander(String folderPath, ScanService scanService) {

    return Expander(
          key: PageStorageKey<String>(folderPath),
          header: Row(
            children: [
              const Icon(FluentIcons.folder_open),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.basename(folderPath), style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(folderPath, style: FluentTheme.of(context).typography.caption, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.delete),
                onPressed: scanService.isScanning ? null : () => _handleRemoveFolder(folderPath),
              ),
              IconButton(
                icon: const Icon(FluentIcons.sync),
                onPressed: scanService.isScanning ? null : () async {
                  await scanService.startDirectoryScan(folderPath, skipPreviouslyMatchedUnwatched: false);
                  _showInfoBar('已开始智能扫描: ${p.basename(folderPath)}', severity: InfoBarSeverity.info);
                },
              ),
            ],
          ),
          content: _loadingFolders.contains(folderPath)
              ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: ProgressRing()))
              : Column(children: _buildFileSystemNodes(_expandedFolderContents[folderPath] ?? [], 1)),
          onStateChanged: (isExpanded) {
            if (isExpanded && !_expandedFolderContents.containsKey(folderPath)) {
              _loadFolderChildren(folderPath);
            }
          },
        );
  }

  List<Widget> _buildFileSystemNodes(List<io.FileSystemEntity> entities, int depth) {
    if (entities.isEmpty) {
      return [const ListTile(title: Text("文件夹为空"))];
    }
    
    return entities.map<Widget>((entity) {
      if (entity is io.Directory) {
        return Expander(
          key: PageStorageKey<String>(entity.path),
          header: Row(
            children: [
              const Icon(FluentIcons.folder),
              const SizedBox(width: 8.0),
              Text(p.basename(entity.path)),
            ],
          ),
          content: _loadingFolders.contains(entity.path)
              ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: ProgressRing()))
              : Column(children: _buildFileSystemNodes(_expandedFolderContents[entity.path] ?? [], depth + 1)),
          onStateChanged: (isExpanded) {
            if (isExpanded && !_expandedFolderContents.containsKey(entity.path)) {
              _loadFolderChildren(entity.path);
            }
          },
        );
      } else if (entity is io.File) {
        return ListTile(
          leading: const Icon(FluentIcons.video),
          title: Text(p.basename(entity.path)),
          onPressed: () {
            final tempItem = WatchHistoryItem(
              filePath: entity.path,
              animeName: p.basenameWithoutExtension(entity.path),
              episodeTitle: '',
              duration: 0,
              lastPosition: 0,
              watchProgress: 0.0,
              lastWatchTime: DateTime.now(),
            );
            widget.onPlayEpisode(tempItem);
          },
        );
      }
      return const SizedBox.shrink();
    }).toList();
  }

  Future<void> _showSortOptionsDialog() async {
    // Implementation for Fluent UI sort dialog
    // This would typically be a ContentDialog with a list of RadioButtons
    // For brevity, we'll just cycle through options here.
    final newSortOption = (_sortOption + 1) % 6;
    setState(() {
      _sortOption = newSortOption;
      _expandedFolderContents.clear(); // Force reload and sort
    });
    await _saveSortOption(newSortOption);
    _showInfoBar('排序方式已更改。', severity: InfoBarSeverity.success);
  }

  void _showInfoBar(String content, {InfoBarSeverity severity = InfoBarSeverity.info}) {
    if (!mounted) return;
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: Text(severity == InfoBarSeverity.error ? '错误' : '提示'),
          content: Text(content),
          severity: severity,
          onClose: close,
        );
      },
      duration: const Duration(seconds: 3),
    );
  }
}