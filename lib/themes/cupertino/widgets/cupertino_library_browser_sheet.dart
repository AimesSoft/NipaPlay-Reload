import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:path/path.dart' as p;

enum CupertinoLibraryBrowserSource { local, webdav, smb }

class CupertinoLibraryFolderBrowserSheet extends StatefulWidget {
  const CupertinoLibraryFolderBrowserSheet._({
    super.key,
    required this.source,
    required this.rootPath,
    required this.sourceLabel,
    this.webdavConnection,
    this.smbConnection,
  });

  factory CupertinoLibraryFolderBrowserSheet.local({
    Key? key,
    required String rootPath,
    required String sourceLabel,
  }) {
    return CupertinoLibraryFolderBrowserSheet._(
      key: key,
      source: CupertinoLibraryBrowserSource.local,
      rootPath: rootPath,
      sourceLabel: sourceLabel,
    );
  }

  factory CupertinoLibraryFolderBrowserSheet.webdav({
    Key? key,
    required WebDAVConnection connection,
  }) {
    return CupertinoLibraryFolderBrowserSheet._(
      key: key,
      source: CupertinoLibraryBrowserSource.webdav,
      rootPath: '/',
      sourceLabel: connection.name,
      webdavConnection: connection,
    );
  }

  factory CupertinoLibraryFolderBrowserSheet.smb({
    Key? key,
    required SMBConnection connection,
  }) {
    return CupertinoLibraryFolderBrowserSheet._(
      key: key,
      source: CupertinoLibraryBrowserSource.smb,
      rootPath: '/',
      sourceLabel: connection.name,
      smbConnection: connection,
    );
  }

  final CupertinoLibraryBrowserSource source;
  final String rootPath;
  final String sourceLabel;
  final WebDAVConnection? webdavConnection;
  final SMBConnection? smbConnection;

  @override
  State<CupertinoLibraryFolderBrowserSheet> createState() =>
      _CupertinoLibraryFolderBrowserSheetState();
}

class _CupertinoLibraryFolderBrowserSheetState
    extends State<CupertinoLibraryFolderBrowserSheet> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, Future<int>> _folderCountTasks = {};
  final List<String> _pathStack = [];

  bool _isLoading = false;
  String? _errorMessage;
  List<_BrowserEntry> _entries = [];

  String get _currentPath => _pathStack.isNotEmpty
      ? _pathStack.last
      : widget.rootPath;

  bool get _canGoBack => _pathStack.length > 1;

  @override
  void initState() {
    super.initState();
    _pathStack.add(widget.rootPath);
    _loadDirectory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _goBack() {
    if (!_canGoBack) return;
    setState(() {
      _pathStack.removeLast();
      _entries = [];
      _errorMessage = null;
    });
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final entries = await _listDirectories(_currentPath);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<List<_BrowserEntry>> _listDirectories(String path) async {
    switch (widget.source) {
      case CupertinoLibraryBrowserSource.local:
        if (kIsWeb) {
          throw Exception('Web 端暂不支持浏览本地文件夹');
        }
        final directory = Directory(path);
        if (!await directory.exists()) {
          throw Exception('文件夹不存在');
        }
        final result = <_BrowserEntry>[];
        await for (final entity
            in directory.list(recursive: false, followLinks: false)) {
          if (entity is Directory) {
            result.add(
              _BrowserEntry(
                name: p.basename(entity.path),
                path: entity.path,
              ),
            );
          }
        }
        result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return result;
      case CupertinoLibraryBrowserSource.webdav:
        final connection = widget.webdavConnection;
        if (connection == null) {
          throw Exception('WebDAV 连接不可用');
        }
        final entries = await WebDAVService.instance.listDirectory(
          connection,
          path,
        );
        final result = entries
            .where((entry) => entry.isDirectory)
            .map((entry) => _BrowserEntry(name: entry.name, path: entry.path))
            .toList();
        result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return result;
      case CupertinoLibraryBrowserSource.smb:
        final connection = widget.smbConnection;
        if (connection == null) {
          throw Exception('SMB 连接不可用');
        }
        final entries = await SMBService.instance.listDirectory(
          connection,
          path,
        );
        final result = entries
            .where((entry) => entry.isDirectory)
            .map((entry) => _BrowserEntry(name: entry.name, path: entry.path))
            .toList();
        result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return result;
    }
  }

  Future<int> _countFiles(String folderPath) async {
    try {
      switch (widget.source) {
        case CupertinoLibraryBrowserSource.local:
          if (kIsWeb) return -1;
          final directory = Directory(folderPath);
          if (!await directory.exists()) {
            return -1;
          }
          var count = 0;
          await for (final entity
              in directory.list(recursive: false, followLinks: false)) {
            if (entity is File &&
                SMBService.instance.isVideoFile(p.basename(entity.path))) {
              count += 1;
            }
          }
          return count;
        case CupertinoLibraryBrowserSource.webdav:
          final connection = widget.webdavConnection;
          if (connection == null) return -1;
          final entries = await WebDAVService.instance.listDirectory(
            connection,
            folderPath,
          );
          return entries.where((entry) => !entry.isDirectory).length;
        case CupertinoLibraryBrowserSource.smb:
          final connection = widget.smbConnection;
          if (connection == null) return -1;
          final entries = await SMBService.instance.listDirectory(
            connection,
            folderPath,
          );
          return entries
              .where((entry) =>
                  !entry.isDirectory &&
                  SMBService.instance.isVideoFile(entry.name))
              .length;
      }
    } catch (_) {
      return -1;
    }
  }

  Future<int> _folderCountFuture(String folderPath) {
    final key = '${widget.source.name}:${widget.sourceLabel}:$folderPath';
    return _folderCountTasks.putIfAbsent(key, () => _countFiles(folderPath));
  }

  void _openFolder(_BrowserEntry entry) {
    setState(() {
      _pathStack.add(entry.path);
      _entries = [];
      _errorMessage = null;
    });
    _loadDirectory();
  }

  String _currentTitle() {
    final name = p.basename(_currentPath);
    if (name.isEmpty || _currentPath == widget.rootPath) {
      return '根目录';
    }
    return name;
  }

  String _pathLabel() {
    if (widget.source == CupertinoLibraryBrowserSource.local) {
      return _currentPath;
    }
    return _currentPath;
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return CupertinoBottomSheetContentLayout(
      controller: _scrollController,
      backgroundColor: backgroundColor,
      sliversBuilder: (context, topSpacing) {
        final slivers = <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, topSpacing + 8, 20, 12),
              child: Row(
                children: [
                  if (_canGoBack)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 0,
                      onPressed: _goBack,
                      child: const Icon(
                        CupertinoIcons.chevron_back,
                        size: 20,
                      ),
                    ),
                  if (_canGoBack) const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.sourceLabel} · ${_currentTitle()}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _pathLabel(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryLabelColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    onPressed: _loadDirectory,
                    child: const Icon(CupertinoIcons.refresh_thin, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ];

        if (_isLoading && _entries.isEmpty) {
          slivers.add(
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CupertinoActivityIndicator(),
                    SizedBox(height: 12),
                    Text('正在加载文件夹...'),
                  ],
                ),
              ),
            ),
          );
          return slivers;
        }

        if (_errorMessage != null) {
          slivers.add(
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        size: 40,
                        color: secondaryLabelColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: secondaryLabelColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      CupertinoButton.filled(
                        onPressed: _loadDirectory,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          return slivers;
        }

        if (_entries.isEmpty) {
          slivers.add(
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.folder,
                      size: 44,
                      color: secondaryLabelColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '当前文件夹为空',
                      style: TextStyle(
                        fontSize: 14,
                        color: secondaryLabelColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          return slivers;
        }

        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = _entries[index];
                  return _FolderGridTile(
                    entry: entry,
                    labelColor: labelColor,
                    secondaryLabelColor: secondaryLabelColor,
                    countFuture: _folderCountFuture(entry.path),
                    onTap: () => _openFolder(entry),
                  );
                },
                childCount: _entries.length,
              ),
            ),
          ),
        );

        return slivers;
      },
    );
  }
}

class _BrowserEntry {
  const _BrowserEntry({
    required this.name,
    required this.path,
  });

  final String name;
  final String path;
}

class _FolderGridTile extends StatelessWidget {
  const _FolderGridTile({
    required this.entry,
    required this.labelColor,
    required this.secondaryLabelColor,
    required this.countFuture,
    required this.onTap,
  });

  final _BrowserEntry entry;
  final Color labelColor;
  final Color secondaryLabelColor;
  final Future<int> countFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final iconColor = CupertinoDynamicColor.resolve(
      CupertinoColors.activeBlue,
      context,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.systemGrey6,
                  context,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                CupertinoIcons.folder_fill,
                size: 30,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              entry.name.isNotEmpty ? entry.name : entry.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: labelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            FutureBuilder<int>(
              future: countFuture,
              builder: (context, snapshot) {
                final count = snapshot.data;
                String label;
                if (snapshot.connectionState == ConnectionState.waiting) {
                  label = '计算中…';
                } else if (count == null || count < 0) {
                  label = '文件数未知';
                } else {
                  label = '$count 个文件';
                }
                return Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: secondaryLabelColor),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
