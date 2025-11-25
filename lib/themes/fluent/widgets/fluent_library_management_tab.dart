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
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/webdav_connection_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/smb_connection_dialog.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';

enum _LibrarySource { local, webdav, smb }

class FluentLibraryManagementTab extends StatefulWidget {
  final void Function(WatchHistoryItem item) onPlayEpisode;

  const FluentLibraryManagementTab({super.key, required this.onPlayEpisode});

  @override
  State<FluentLibraryManagementTab> createState() =>
      _FluentLibraryManagementTabState();
}

class _FluentLibraryManagementTabState
    extends State<FluentLibraryManagementTab> {
  static const String _librarySortOptionKey = 'library_sort_option';

  final Map<String, List<io.FileSystemEntity>> _expandedFolderContents = {};
  final Set<String> _loadingFolders = {};
  final ScrollController _listScrollController = ScrollController();

  ScanService? _scanService;
  int _sortOption =
      0; // 0: Name Asc, 1: Name Desc, 2: Date Asc, 3: Date Desc, etc.
  _LibrarySource _selectedSource = _LibrarySource.local;

  List<WebDAVConnection> _webdavConnections = [];
  final Map<String, List<WebDAVFile>> _webdavFolderContents = {};
  final Set<String> _expandedWebDAVConnections = {};
  final Set<String> _expandedWebDAVFolders = {};
  final Set<String> _loadingWebDAVFolders = {};
  bool _isLoadingWebDAV = false;
  bool _webdavInitialized = false;
  String? _webdavErrorMessage;

  List<SMBConnection> _smbConnections = [];
  final Map<String, List<SMBFileEntry>> _smbFolderContents = {};
  final Set<String> _expandedSMBConnections = {};
  final Set<String> _expandedSMBFolders = {};
  final Set<String> _loadingSMBFolders = {};
  bool _isLoadingSMB = false;
  bool _smbInitialized = false;
  String? _smbErrorMessage;

  @override
  void initState() {
    super.initState();
    _initScanServiceListener();
    _loadSortOption();
    _initWebDAVService();
    _initSMBService();
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
      await scanService.startDirectoryScan(appDir.path,
          skipPreviouslyMatchedUnwatched: false);
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

      // [修改] 自定义目录会影响安卓缓存，先注释
      //await StorageService.saveCustomStoragePath(selectedDirectory);
      await scanService.startDirectoryScan(selectedDirectory,
          skipPreviouslyMatchedUnwatched: false);
    } catch (e) {
      _showInfoBar("选择文件夹时出错: $e", severity: InfoBarSeverity.error);
    }
  }

  Future<void> _scanAndroidMediaFolders() async {
    // This is a simplified version. A full implementation would require more UI/UX for permissions.
    final scanService = Provider.of<ScanService>(context, listen: false);
    _showInfoBar('正在扫描视频文件夹...', severity: InfoBarSeverity.info);
    try {
      final moviesDir =
          await getExternalStorageDirectories(type: StorageDirectory.movies);
      if (moviesDir != null && moviesDir.isNotEmpty) {
        await scanService.startDirectoryScan(moviesDir.first.path,
            skipPreviouslyMatchedUnwatched: false);
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
      _showInfoBar('请求已提交: $folderPath 将被移除并清理相关记录。',
          severity: InfoBarSeverity.success);
    }
  }

  void _sortContents(List<io.FileSystemEntity> contents) {
    contents.sort((a, b) {
      if (a is io.Directory && b is io.File) return -1;
      if (a is io.File && b is io.Directory) return 1;

      int result = 0;
      switch (_sortOption) {
        case 0:
          result = p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase());
          break;
        case 1:
          result = p
              .basename(b.path)
              .toLowerCase()
              .compareTo(p.basename(a.path).toLowerCase());
          break;
        case 2:
          result = a.statSync().modified.compareTo(b.statSync().modified);
          break;
        case 3:
          result = b.statSync().modified.compareTo(a.statSync().modified);
          break;
        case 4:
          result = (a is io.File ? a.lengthSync() : 0)
              .compareTo(b is io.File ? b.lengthSync() : 0);
          break;
        case 5:
          result = (b is io.File ? b.lengthSync() : 0)
              .compareTo(a is io.File ? a.lengthSync() : 0);
          break;
      }
      return result;
    });
  }

  // 对文件夹路径列表进行排序
  List<String> _sortFolderPaths(List<String> folderPaths) {
    final sortedPaths = List<String>.from(folderPaths);
    sortedPaths.sort((a, b) {
      int result = 0;
      switch (_sortOption) {
        case 0:
          result = p
              .basename(a)
              .toLowerCase()
              .compareTo(p.basename(b).toLowerCase());
          break;
        case 1:
          result = p
              .basename(b)
              .toLowerCase()
              .compareTo(p.basename(a).toLowerCase());
          break;
        case 2:
          result = io.File(a)
              .statSync()
              .modified
              .compareTo(io.File(b).statSync().modified);
          break;
        case 3:
          result = io.File(b)
              .statSync()
              .modified
              .compareTo(io.File(a).statSync().modified);
          break;
        case 4:
          result = 0.compareTo(0);
          break; // 文件夹大小排序对路径无效
        case 5:
          result = 0.compareTo(0);
          break; // 文件夹大小排序对路径无效
      }
      return result;
    });
    return sortedPaths;
  }

  Future<void> _loadFolderChildren(String folderPath) async {
    if (mounted) setState(() => _loadingFolders.add(folderPath));

    final List<io.FileSystemEntity> contents = [];
    try {
      final dir = io.Directory(folderPath);
      if (await dir.exists()) {
        await for (var entity
            in dir.list(recursive: false, followLinks: false)) {
          if (entity is io.Directory ||
              (entity is io.File &&
                  (p.extension(entity.path).toLowerCase() == '.mp4' ||
                      p.extension(entity.path).toLowerCase() == '.mkv'))) {
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
            if (_selectedSource == _LibrarySource.local) ...[
              CommandBarButton(
                icon: const Icon(FluentIcons.sort),
                label: const Text('排序'),
                onPressed: _showSortOptionsDialog,
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.refresh),
                label: const Text('智能刷新'),
                onPressed: scanService.isScanning
                    ? null
                    : () async {
                        await scanService.rescanAllFolders();
                      },
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.add),
                label: const Text('添加文件夹'),
                onPressed:
                    scanService.isScanning ? null : _pickAndScanDirectory,
              ),
            ] else if (_selectedSource == _LibrarySource.webdav) ...[
              CommandBarButton(
                icon: const Icon(FluentIcons.refresh),
                label: const Text('刷新状态'),
                onPressed: _refreshWebDAVConnections,
              ),
              CommandBarButton(
                icon: const Icon(FluentIcons.cloud_add),
                label: const Text('添加 WebDAV'),
                onPressed: () => _showWebDAVConnectionDialog(),
              ),
            ],
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
                severity: scanService.isScanning
                    ? InfoBarSeverity.info
                    : InfoBarSeverity.success,
                action: scanService.isScanning && scanService.scanProgress > 0
                    ? ProgressBar(value: scanService.scanProgress * 100)
                    : null,
              ),
            ),
          _buildSourceSelector(),
          const SizedBox(height: 8),
          Expanded(
            child: _buildCurrentSourceView(scanService),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          const Text('查看内容：'),
          const SizedBox(width: 12),
          ComboBox<_LibrarySource>(
            value: _selectedSource,
            items: const [
              ComboBoxItem(
                value: _LibrarySource.local,
                child: Text('本地媒体'),
              ),
              ComboBoxItem(
                value: _LibrarySource.webdav,
                child: Text('WebDAV'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedSource = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentSourceView(ScanService scanService) {
    switch (_selectedSource) {
      case _LibrarySource.local:
        return _buildFolderList(scanService);
      case _LibrarySource.webdav:
        return _buildRemoteSection<WebDAVConnection, WebDAVFile>(
          _webdavDescriptor(),
        );
      case _LibrarySource.smb:
        return _buildRemoteSection<SMBConnection, SMBFileEntry>(
          _smbDescriptor(),
        );
    }
  }

  Widget _buildFolderList(ScanService scanService) {
    if (scanService.scannedFolders.isEmpty && !scanService.isScanning) {
      return const Center(
          child: Text('尚未添加任何扫描文件夹。\n点击上方按钮添加。', textAlign: TextAlign.center));
    }

    // 对根文件夹进行排序
    final sortedFolders = _sortFolderPaths(scanService.scannedFolders);

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
            final crossAxisCount =
                (constraints.maxWidth / minItemWidth).floor().clamp(1, 3);

            return _buildWaterfallLayout(
              scanService,
              sortedFolders,
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
        itemCount: sortedFolders.length,
        itemBuilder: (context, index) {
          final folderPath = sortedFolders[index];
          return _buildFolderExpander(folderPath, scanService);
        },
      );
    }
  }

  // 真正的瀑布流布局组件
  Widget _buildWaterfallLayout(
      ScanService scanService,
      List<String> sortedFolders,
      double maxWidth,
      double minItemWidth,
      double spacing) {
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

    // 按列分配已排序的文件夹
    for (var i = 0; i < sortedFolders.length; i++) {
      final columnIndex = i % crossAxisCount;
      columnFolders[columnIndex].add(sortedFolders[i]);
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
                Text(
                  p.basename(folderPath),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(folderPath,
                    style: FluentTheme.of(context).typography.caption,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(FluentIcons.delete),
            onPressed: scanService.isScanning
                ? null
                : () => _handleRemoveFolder(folderPath),
          ),
          IconButton(
            icon: const Icon(FluentIcons.sync),
            onPressed: scanService.isScanning
                ? null
                : () async {
                    await scanService.startDirectoryScan(folderPath,
                        skipPreviouslyMatchedUnwatched: false);
                    _showInfoBar('已开始智能扫描: ${p.basename(folderPath)}',
                        severity: InfoBarSeverity.info);
                  },
          ),
        ],
      ),
      content: _loadingFolders.contains(folderPath)
          ? const Center(
              child:
                  Padding(padding: EdgeInsets.all(16.0), child: ProgressRing()))
          : Column(
              children: _buildFileSystemNodes(
                  _expandedFolderContents[folderPath] ?? [], 1)),
      onStateChanged: (isExpanded) {
        if (isExpanded && !_expandedFolderContents.containsKey(folderPath)) {
          _loadFolderChildren(folderPath);
        }
      },
    );
  }

  List<Widget> _buildFileSystemNodes(
      List<io.FileSystemEntity> entities, int depth) {
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
              Expanded(
                child: Text(
                  p.basename(entity.path),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          content: _loadingFolders.contains(entity.path)
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16.0), child: ProgressRing()))
              : Column(
                  children: _buildFileSystemNodes(
                      _expandedFolderContents[entity.path] ?? [], depth + 1)),
          onStateChanged: (isExpanded) {
            if (isExpanded &&
                !_expandedFolderContents.containsKey(entity.path)) {
              _loadFolderChildren(entity.path);
            }
          },
        );
      } else if (entity is io.File) {
        return ListTile(
          leading: const Icon(FluentIcons.video),
          title: Text(
            p.basename(entity.path),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
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

  _RemoteSectionDescriptor<WebDAVConnection, WebDAVFile> _webdavDescriptor() {
    return _RemoteSectionDescriptor<WebDAVConnection, WebDAVFile>(
      title: 'WebDAV 服务器',
      description: '连接远程 WebDAV 服务器，浏览目录并选择需要挂载的媒体文件夹。',
      emptySubtitle: '点击“添加 WebDAV”按钮添加服务器，即可开始浏览远程媒体。',
      icon: FluentIcons.cloud,
      connections: _webdavConnections,
      folderContents: _webdavFolderContents,
      expandedConnections: _expandedWebDAVConnections,
      expandedFolders: _expandedWebDAVFolders,
      loadingFolders: _loadingWebDAVFolders,
      isLoading: _isLoadingWebDAV,
      initialized: _webdavInitialized,
      errorMessage: _webdavErrorMessage,
      nameBuilder: (c) => c.name,
      subtitleBuilder: (c) => c.url,
      extraSubtitleBuilder: (c) =>
          c.username.isNotEmpty ? '用户：${c.username}' : null,
      isConnected: (c) => c.isConnected,
      showDialog: ({editConnection}) =>
          _showWebDAVConnectionDialog(editConnection: editConnection),
      removeConnection: _removeWebDAVConnection,
      testConnection: _testWebDAVConnection,
      toggleConnection: _toggleWebDAVConnection,
      toggleFolder: _toggleWebDAVFolder,
      scanFolder: _scanWebDAVFolder,
      playFile: _playWebDAVFile,
      isDirectory: (file) => file.isDirectory,
      fileName: (file) => file.name,
      fileSize: (file) => file.size,
      filePath: (file) => file.path,
      keyBuilder: _webdavKey,
    );
  }

  _RemoteSectionDescriptor<SMBConnection, SMBFileEntry> _smbDescriptor() {
    return _RemoteSectionDescriptor<SMBConnection, SMBFileEntry>(
      title: 'SMB 服务器',
      description: '连接局域网中的 SMB/NAS 共享，浏览并挂载视频文件夹。',
      emptySubtitle: '点击“添加 SMB”按钮添加服务器，浏览局域网中的共享目录。',
      icon: FluentIcons.devices2,
      connections: _smbConnections,
      folderContents: _smbFolderContents,
      expandedConnections: _expandedSMBConnections,
      expandedFolders: _expandedSMBFolders,
      loadingFolders: _loadingSMBFolders,
      isLoading: _isLoadingSMB,
      initialized: _smbInitialized,
      errorMessage: _smbErrorMessage,
      nameBuilder: (c) => c.name,
      subtitleBuilder: (c) => c.host,
      extraSubtitleBuilder: (c) => c.username.isNotEmpty
          ? '用户：${c.username}${c.domain.isNotEmpty ? " @${c.domain}" : ''}'
          : null,
      isConnected: (c) => c.isConnected,
      showDialog: ({editConnection}) =>
          _showSMBConnectionDialog(editConnection: editConnection),
      removeConnection: _removeSMBConnection,
      testConnection: _testSMBConnection,
      toggleConnection: _toggleSMBConnection,
      toggleFolder: _toggleSMBFolder,
      scanFolder: _scanSMBFolder,
      playFile: _playSMBFile,
      isDirectory: (file) => file.isDirectory,
      fileName: (file) => file.name,
      fileSize: (file) => file.size,
      filePath: (file) => file.path,
      keyBuilder: _smbKey,
    );
  }

  Widget _buildRemoteSection<C, F>(
    _RemoteSectionDescriptor<C, F> descriptor,
  ) {
    final children = <Widget>[
      _buildRemoteHeader(descriptor.title, descriptor.description),
      const SizedBox(height: 12),
    ];

    if (descriptor.isLoading && !descriptor.initialized) {
      children.add(_buildRemotePlaceholder(
        title: '正在加载连接',
        subtitle: '正在读取已保存的服务器配置…',
      ));
    } else if (descriptor.errorMessage != null) {
      children.add(_buildRemotePlaceholder(
        title: '加载失败',
        subtitle: descriptor.errorMessage!,
        isError: true,
      ));
    } else if (descriptor.connections.isEmpty) {
      children.add(_buildRemotePlaceholder(
        title: '尚未添加服务器',
        subtitle: descriptor.emptySubtitle,
      ));
    } else {
      children.addAll(
        descriptor.connections
            .map((connection) =>
                _buildRemoteConnectionCard(descriptor, connection))
            .toList(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildRemoteHeader(String title, String description) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.typography.title,
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.typography.body,
        ),
      ],
    );
  }

  Widget _buildRemotePlaceholder({
    required String title,
    required String subtitle,
    bool isError = false,
  }) {
    final theme = FluentTheme.of(context);
    final errorColor = theme.resources.systemFillColorCritical;
    final Color borderColor =
        isError ? errorColor : theme.resources.controlStrokeColorDefault;
    final Color textColor =
        isError ? errorColor : theme.typography.body!.color ?? Colors.white;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.typography.subtitle!
                .copyWith(color: textColor, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.typography.body!.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteConnectionCard<C, F>(
    _RemoteSectionDescriptor<C, F> descriptor,
    C connection,
  ) {
    final theme = FluentTheme.of(context);
    final accentColor = theme.accentColor.defaultBrushFor(theme.brightness);
    final errorColor = theme.resources.systemFillColorCritical;
    final connectionKey = descriptor.nameBuilder(connection);
    final isExpanded = descriptor.expandedConnections.contains(connectionKey);
    final Color statusColor =
        descriptor.isConnected(connection) ? accentColor : errorColor;
    final extraText = descriptor.extraSubtitleBuilder?.call(connection);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(descriptor.icon, color: statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: descriptor.isConnected(connection)
                        ? () => descriptor.toggleConnection(connection)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          descriptor.nameBuilder(connection),
                          style: theme.typography.subtitle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          descriptor.subtitleBuilder(connection),
                          style: theme.typography.body,
                        ),
                        if (extraText != null && extraText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              extraText,
                              style: theme.typography.body!,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                descriptor.isConnected(connection)
                                    ? '已连接'
                                    : '未连接',
                                style: theme.typography.caption!
                                    .copyWith(color: statusColor),
                              ),
                            ),
                            if (descriptor.isConnected(connection))
                              Padding(
                                padding: const EdgeInsets.only(left: 6.0),
                                child: Icon(
                                  isExpanded
                                      ? FluentIcons.chevron_down
                                      : FluentIcons.chevron_right,
                                  size: 14,
                                  color: theme.typography.body!.color,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(FluentIcons.edit),
                      onPressed: () =>
                          descriptor.showDialog(editConnection: connection),
                    ),
                    IconButton(
                      icon: const Icon(FluentIcons.delete),
                      onPressed: () => descriptor.removeConnection(connection),
                    ),
                    IconButton(
                      icon: const Icon(FluentIcons.refresh),
                      onPressed: () => descriptor.testConnection(connection),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!descriptor.isConnected(connection))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '点击刷新测试连接，成功后即可展开查看目录。',
                  style: theme.typography.caption,
                ),
              ),
            ),
          if (descriptor.isConnected(connection) && isExpanded) const Divider(),
          if (descriptor.isConnected(connection) && isExpanded)
            _buildRemoteFileList(descriptor, connection, '/', 0),
        ],
      ),
    );
  }

  Widget _buildRemoteFileList<C, F>(
    _RemoteSectionDescriptor<C, F> descriptor,
    C connection,
    String path,
    int depth,
  ) {
    final key = descriptor.keyBuilder(connection, path);
    final files = descriptor.folderContents[key];
    final isLoading = descriptor.loadingFolders.contains(key);
    final theme = FluentTheme.of(context);

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16.0 + depth * 20, 12, 16, 12),
        child: const ProgressRing(),
      );
    }

    if (files == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16.0 + depth * 20, 12, 16, 12),
        child: Text(
          '尚未加载内容',
          style: theme.typography.body,
        ),
      );
    }

    if (files.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16.0 + depth * 20, 12, 16, 12),
        child: Text(
          '文件夹为空',
          style: theme.typography.body,
        ),
      );
    }

    return Column(
      children: files
          .map((file) => _buildRemoteNode(descriptor, connection, file, depth))
          .toList(),
    );
  }

  Widget _buildRemoteNode<C, F>(
    _RemoteSectionDescriptor<C, F> descriptor,
    C connection,
    F file,
    int depth,
  ) {
    final theme = FluentTheme.of(context);
    final accentColor = theme.accentColor.defaultBrushFor(theme.brightness);
    final isDirectory = descriptor.isDirectory(file);
    final path = descriptor.filePath(file);
    final folderKey = descriptor.keyBuilder(connection, path);
    final isExpanded = descriptor.expandedFolders.contains(folderKey);
    final size = descriptor.fileSize(file);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.0 + depth * 20, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                isDirectory ? FluentIcons.folder : FluentIcons.play,
                color: isDirectory ? accentColor : theme.typography.body!.color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      descriptor.fileName(file),
                      style: theme.typography.body?.copyWith(
                        fontWeight:
                            isDirectory ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    if (!isDirectory && size != null)
                      Text(
                        _formatFileSize(size),
                        style: theme.typography.caption,
                      ),
                  ],
                ),
              ),
              if (isDirectory)
                Row(
                  children: [
                    Button(
                      child: const Text('扫描'),
                      onPressed: () => descriptor.scanFolder(
                        connection,
                        path,
                        descriptor.fileName(file),
                      ),
                    ),
                    IconButton(
                      icon: Icon(isExpanded
                          ? FluentIcons.chevron_down
                          : FluentIcons.chevron_right),
                      onPressed: () =>
                          descriptor.toggleFolder(connection, path),
                    ),
                  ],
                )
              else
                Button(
                  child: const Text('播放'),
                  onPressed: () => descriptor.playFile(connection, file),
                ),
            ],
          ),
        ),
        if (isDirectory && isExpanded)
          _buildRemoteFileList(descriptor, connection, path, depth + 1),
      ],
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  Future<void> _initWebDAVService() async {
    setState(() {
      _isLoadingWebDAV = true;
      _webdavErrorMessage = null;
    });

    try {
      await WebDAVService.instance.initialize();
      if (!mounted) return;
      setState(() {
        _webdavConnections = WebDAVService.instance.connections;
        _webdavInitialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _webdavErrorMessage = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingWebDAV = false;
      });
    }
  }

  void _refreshWebDAVConnections() {
    if (!mounted) return;
    setState(() {
      _webdavConnections = WebDAVService.instance.connections;
    });
  }

  Future<void> _showWebDAVConnectionDialog({
    WebDAVConnection? editConnection,
  }) async {
    final result = await WebDAVConnectionDialog.show(
      context,
      editConnection: editConnection,
    );

    if (result == true) {
      _refreshWebDAVConnections();
      _showInfoBar(
        editConnection == null ? '已添加 WebDAV 连接' : 'WebDAV 连接已更新',
        severity: InfoBarSeverity.success,
      );
    }
  }

  Future<void> _removeWebDAVConnection(WebDAVConnection connection) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('删除 WebDAV 连接'),
        content: Text('确定要删除“${connection.name}”吗？'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: ButtonState.all(Colors.red),
            ),
            child: const Text('删除'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await WebDAVService.instance.removeConnection(connection.name);
      if (!mounted) return;
      setState(() {
        _webdavConnections = WebDAVService.instance.connections;
        _expandedWebDAVConnections.remove(connection.name);
        _webdavFolderContents
            .removeWhere((key, value) => key.startsWith('${connection.name}:'));
        _expandedWebDAVFolders
            .removeWhere((key) => key.startsWith('${connection.name}:'));
      });
      _showInfoBar('已删除 ${connection.name}', severity: InfoBarSeverity.success);
    }
  }

  Future<void> _testWebDAVConnection(WebDAVConnection connection) async {
    _showInfoBar('正在测试连接…');
    await WebDAVService.instance.updateConnectionStatus(connection.name);
    if (!mounted) return;
    _refreshWebDAVConnections();
    final updated = WebDAVService.instance.getConnection(connection.name);
    if (updated?.isConnected == true) {
      _showInfoBar('连接成功，可以展开浏览目录', severity: InfoBarSeverity.success);
    } else {
      _showInfoBar('连接失败，请检查配置', severity: InfoBarSeverity.error);
    }
  }

  void _toggleWebDAVConnection(WebDAVConnection connection) {
    if (!connection.isConnected) {
      _showInfoBar('请先测试并建立连接', severity: InfoBarSeverity.warning);
      return;
    }

    final alreadyExpanded =
        _expandedWebDAVConnections.contains(connection.name);
    setState(() {
      if (alreadyExpanded) {
        _expandedWebDAVConnections.remove(connection.name);
      } else {
        _expandedWebDAVConnections.add(connection.name);
      }
    });

    if (!alreadyExpanded) {
      _loadWebDAVFolderChildren(connection, '/');
    }
  }

  void _toggleWebDAVFolder(WebDAVConnection connection, String path) {
    final key = _webdavKey(connection, path);
    final alreadyExpanded = _expandedWebDAVFolders.contains(key);
    setState(() {
      if (alreadyExpanded) {
        _expandedWebDAVFolders.remove(key);
      } else {
        _expandedWebDAVFolders.add(key);
      }
    });

    if (!alreadyExpanded) {
      _loadWebDAVFolderChildren(connection, path);
    }
  }

  Future<void> _loadWebDAVFolderChildren(
    WebDAVConnection connection,
    String path,
  ) async {
    final normalizedPath = path.isEmpty ? '/' : path;
    final key = _webdavKey(connection, normalizedPath);

    if (_loadingWebDAVFolders.contains(key)) {
      return;
    }

    setState(() {
      _loadingWebDAVFolders.add(key);
    });

    try {
      final files = await WebDAVService.instance.listDirectory(
        connection,
        normalizedPath,
      );
      if (!mounted) return;
      setState(() {
        _webdavFolderContents[key] = files;
      });
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('加载目录失败：$e', severity: InfoBarSeverity.error);
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingWebDAVFolders.remove(key);
      });
    }
  }

  Future<void> _scanWebDAVFolder(
    WebDAVConnection connection,
    String folderPath,
    String folderName,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('扫描 WebDAV 文件夹'),
        content: Text('确定要扫描“$folderName”吗？\n扫描后将把其中的视频文件添加到本地媒体库。'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            child: const Text('扫描'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      _showInfoBar('正在扫描 $folderName…');
      final files = await _getWebDAVVideoFiles(connection, folderPath);
      if (files.isEmpty) {
        _showInfoBar('未找到可导入的视频文件', severity: InfoBarSeverity.warning);
        return;
      }

      for (final file in files) {
        final fileUrl =
            WebDAVService.instance.getFileUrl(connection, file.path);
        final historyItem = WatchHistoryItem(
          filePath: fileUrl,
          animeName: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
          episodeTitle: '',
          duration: 0,
          lastPosition: 0,
          watchProgress: 0.0,
          lastWatchTime: DateTime.now(),
          isFromScan: true,
        );
        await WatchHistoryManager.addOrUpdateHistory(historyItem);
      }

      await context.read<WatchHistoryProvider>().refresh();
      _showInfoBar('已添加 ${files.length} 个视频文件',
          severity: InfoBarSeverity.success);
    } catch (e) {
      _showInfoBar('扫描失败：$e', severity: InfoBarSeverity.error);
    }
  }

  Future<List<WebDAVFile>> _getWebDAVVideoFiles(
    WebDAVConnection connection,
    String folderPath,
  ) async {
    final List<WebDAVFile> videoFiles = [];
    try {
      final files = await WebDAVService.instance.listDirectory(
        connection,
        folderPath,
      );
      for (final file in files) {
        if (file.isDirectory) {
          final subFiles = await _getWebDAVVideoFiles(connection, file.path);
          videoFiles.addAll(subFiles);
        } else if (WebDAVService.instance.isVideoFile(file.name)) {
          videoFiles.add(file);
        }
      }
    } catch (e) {
      debugPrint('获取WebDAV视频文件失败: $e');
    }
    return videoFiles;
  }

  Future<void> _playWebDAVFile(
    WebDAVConnection connection,
    WebDAVFile file,
  ) async {
    try {
      final fileUrl = WebDAVService.instance.getFileUrl(connection, file.path);
      final historyItem = WatchHistoryItem(
        filePath: fileUrl,
        animeName: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
        episodeTitle: '',
        duration: 0,
        lastPosition: 0,
        watchProgress: 0.0,
        lastWatchTime: DateTime.now(),
      );
      await WatchHistoryManager.addOrUpdateHistory(historyItem);

      final playable = PlayableItem(
        videoPath: fileUrl,
        title: historyItem.animeName,
        historyItem: historyItem,
      );
      await PlaybackService().play(playable);
    } catch (e) {
      _showInfoBar('播放失败：$e', severity: InfoBarSeverity.error);
    }
  }

  String _webdavKey(WebDAVConnection connection, String path) {
    return '${connection.name}:$path';
  }

  Future<void> _initSMBService() async {
    setState(() {
      _isLoadingSMB = true;
      _smbErrorMessage = null;
    });

    try {
      await SMBService.instance.initialize();
      if (!mounted) return;
      setState(() {
        _smbConnections = SMBService.instance.connections;
        _smbInitialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _smbErrorMessage = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingSMB = false;
      });
    }
  }

  void _refreshSMBConnections() {
    if (!mounted) return;
    setState(() {
      _smbConnections = SMBService.instance.connections;
    });
  }

  Future<void> _showSMBConnectionDialog({
    SMBConnection? editConnection,
  }) async {
    final result = await SMBConnectionDialog.show(
      context,
      editConnection: editConnection,
    );

    if (result == true) {
      _refreshSMBConnections();
      _showInfoBar(
        editConnection == null ? '已添加 SMB 连接' : 'SMB 连接已更新',
        severity: InfoBarSeverity.success,
      );
    }
  }

  Future<void> _removeSMBConnection(SMBConnection connection) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('删除 SMB 连接'),
        content: Text('确定要删除“${connection.name}”吗？'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: ButtonState.all(Colors.red),
            ),
            child: const Text('删除'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SMBService.instance.removeConnection(connection.name);
      if (!mounted) return;
      setState(() {
        _smbConnections = SMBService.instance.connections;
        _expandedSMBConnections.remove(connection.name);
        _smbFolderContents
            .removeWhere((key, value) => key.startsWith('${connection.name}:'));
        _expandedSMBFolders
            .removeWhere((key) => key.startsWith('${connection.name}:'));
      });
      _showInfoBar('已删除 ${connection.name}', severity: InfoBarSeverity.success);
    }
  }

  Future<void> _testSMBConnection(SMBConnection connection) async {
    _showInfoBar('正在测试连接…');
    await SMBService.instance.updateConnectionStatus(connection.name);
    if (!mounted) return;
    _refreshSMBConnections();
    final updated = SMBService.instance.getConnection(connection.name);
    if (updated?.isConnected == true) {
      _showInfoBar('连接成功，可以展开浏览目录', severity: InfoBarSeverity.success);
    } else {
      _showInfoBar('连接失败，请检查配置', severity: InfoBarSeverity.error);
    }
  }

  void _toggleSMBConnection(SMBConnection connection) {
    if (!connection.isConnected) {
      _showInfoBar('请先测试并建立连接', severity: InfoBarSeverity.warning);
      return;
    }

    final alreadyExpanded = _expandedSMBConnections.contains(connection.name);
    setState(() {
      if (alreadyExpanded) {
        _expandedSMBConnections.remove(connection.name);
      } else {
        _expandedSMBConnections.add(connection.name);
      }
    });

    if (!alreadyExpanded) {
      _loadSMBFolderChildren(connection, '/');
    }
  }

  void _toggleSMBFolder(SMBConnection connection, String path) {
    final key = _smbKey(connection, path);
    final alreadyExpanded = _expandedSMBFolders.contains(key);
    setState(() {
      if (alreadyExpanded) {
        _expandedSMBFolders.remove(key);
      } else {
        _expandedSMBFolders.add(key);
      }
    });

    if (!alreadyExpanded) {
      _loadSMBFolderChildren(connection, path);
    }
  }

  Future<void> _loadSMBFolderChildren(
    SMBConnection connection,
    String path,
  ) async {
    final normalizedPath = path.isEmpty ? '/' : path;
    final key = _smbKey(connection, normalizedPath);

    if (_loadingSMBFolders.contains(key)) {
      return;
    }

    setState(() {
      _loadingSMBFolders.add(key);
    });

    try {
      final files = await SMBService.instance.listDirectory(
        connection,
        normalizedPath,
      );
      if (!mounted) return;
      setState(() {
        _smbFolderContents[key] = files;
      });
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('加载目录失败：$e', severity: InfoBarSeverity.error);
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingSMBFolders.remove(key);
      });
    }
  }

  Future<void> _scanSMBFolder(
    SMBConnection connection,
    String folderPath,
    String folderName,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('扫描 SMB 文件夹'),
        content: Text('确定要扫描“$folderName”吗？\n扫描后将把其中的视频文件添加到本地媒体库。'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            child: const Text('扫描'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      _showInfoBar('正在扫描 $folderName…');
      final files = await _getSMBVideoFiles(connection, folderPath);
      if (files.isEmpty) {
        _showInfoBar('未找到可导入的视频文件', severity: InfoBarSeverity.warning);
        return;
      }

      for (final file in files) {
        final fileUrl = SMBService.instance.buildFileUrl(connection, file.path);
        final historyItem = WatchHistoryItem(
          filePath: fileUrl,
          animeName: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
          episodeTitle: '',
          duration: 0,
          lastPosition: 0,
          watchProgress: 0.0,
          lastWatchTime: DateTime.now(),
          isFromScan: true,
        );
        await WatchHistoryManager.addOrUpdateHistory(historyItem);
      }

      await context.read<WatchHistoryProvider>().refresh();
      _showInfoBar('已添加 ${files.length} 个视频文件',
          severity: InfoBarSeverity.success);
    } catch (e) {
      _showInfoBar('扫描失败：$e', severity: InfoBarSeverity.error);
    }
  }

  Future<List<SMBFileEntry>> _getSMBVideoFiles(
    SMBConnection connection,
    String folderPath,
  ) async {
    final List<SMBFileEntry> videoFiles = [];
    try {
      final files = await SMBService.instance.listDirectory(
        connection,
        folderPath,
      );
      for (final file in files) {
        if (file.isDirectory) {
          final nested = await _getSMBVideoFiles(connection, file.path);
          videoFiles.addAll(nested);
        } else if (SMBService.instance.isVideoFile(file.name)) {
          videoFiles.add(file);
        }
      }
    } catch (e) {
      debugPrint('获取SMB视频文件失败: $e');
    }
    return videoFiles;
  }

  Future<void> _playSMBFile(
    SMBConnection connection,
    SMBFileEntry file,
  ) async {
    try {
      final fileUrl = SMBService.instance.buildFileUrl(connection, file.path);
      final historyItem = WatchHistoryItem(
        filePath: fileUrl,
        animeName: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
        episodeTitle: '',
        duration: 0,
        lastPosition: 0,
        watchProgress: 0.0,
        lastWatchTime: DateTime.now(),
      );
      await WatchHistoryManager.addOrUpdateHistory(historyItem);

      final playable = PlayableItem(
        videoPath: fileUrl,
        title: historyItem.animeName,
        historyItem: historyItem,
      );
      await PlaybackService().play(playable);
    } catch (e) {
      _showInfoBar('播放失败：$e', severity: InfoBarSeverity.error);
    }
  }

  String _smbKey(SMBConnection connection, String path) {
    return '${connection.name}:$path';
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

  void _showInfoBar(String content,
      {InfoBarSeverity severity = InfoBarSeverity.info}) {
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

class _RemoteSectionDescriptor<C, F> {
  const _RemoteSectionDescriptor({
    required this.title,
    required this.description,
    required this.emptySubtitle,
    required this.icon,
    required this.connections,
    required this.folderContents,
    required this.expandedConnections,
    required this.expandedFolders,
    required this.loadingFolders,
    required this.isLoading,
    required this.initialized,
    required this.errorMessage,
    required this.nameBuilder,
    required this.subtitleBuilder,
    this.extraSubtitleBuilder,
    required this.isConnected,
    required this.showDialog,
    required this.removeConnection,
    required this.testConnection,
    required this.toggleConnection,
    required this.toggleFolder,
    required this.scanFolder,
    required this.playFile,
    required this.isDirectory,
    required this.fileName,
    required this.fileSize,
    required this.filePath,
    required this.keyBuilder,
  });

  final String title;
  final String description;
  final String emptySubtitle;
  final IconData icon;
  final List<C> connections;
  final Map<String, List<F>> folderContents;
  final Set<String> expandedConnections;
  final Set<String> expandedFolders;
  final Set<String> loadingFolders;
  final bool isLoading;
  final bool initialized;
  final String? errorMessage;
  final String Function(C) nameBuilder;
  final String Function(C) subtitleBuilder;
  final String? Function(C)? extraSubtitleBuilder;
  final bool Function(C) isConnected;
  final Future<void> Function({C? editConnection}) showDialog;
  final Future<void> Function(C) removeConnection;
  final Future<void> Function(C) testConnection;
  final void Function(C) toggleConnection;
  final void Function(C, String path) toggleFolder;
  final Future<void> Function(C, String path, String folderName) scanFolder;
  final Future<void> Function(C, F) playFile;
  final bool Function(F) isDirectory;
  final String Function(F) fileName;
  final int? Function(F) fileSize;
  final String Function(F) filePath;
  final String Function(C, String path) keyBuilder;
}
