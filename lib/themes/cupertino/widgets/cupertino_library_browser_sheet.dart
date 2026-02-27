import 'dart:async';
import 'dart:io';

import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_modal_popup.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
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
  // Reserved for future: folder counts (disabled for accuracy).
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

  List<_BrowserEntry> _sortEntries(List<_BrowserEntry> entries) {
    entries.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
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
                isDirectory: true,
              ),
            );
          } else if (entity is File) {
            final fileName = p.basename(entity.path);
            if (SMBService.instance.isVideoFile(fileName)) {
              result.add(
                _BrowserEntry(
                  name: fileName,
                  path: entity.path,
                  isDirectory: false,
                ),
              );
            }
          }
        }
        return _sortEntries(result);
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
            .map((entry) => _BrowserEntry(
                  name: entry.name,
                  path: entry.path,
                  isDirectory: entry.isDirectory,
                ))
            .toList();
        return _sortEntries(result);
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
            .map((entry) => _BrowserEntry(
                  name: entry.name,
                  path: entry.path,
                  isDirectory: entry.isDirectory,
                ))
            .toList();
        return _sortEntries(result);
    }
  }


  void _openFolder(_BrowserEntry entry) {
    if (!entry.isDirectory) {
      return;
    }
    setState(() {
      _pathStack.add(entry.path);
      _entries = [];
      _errorMessage = null;
    });
    _loadDirectory();
  }

  String? _historyKeyForEntry(_BrowserEntry entry) {
    if (entry.isDirectory) return null;
    switch (widget.source) {
      case CupertinoLibraryBrowserSource.local:
        return entry.path;
      case CupertinoLibraryBrowserSource.webdav:
        final connection = widget.webdavConnection;
        if (connection == null) return null;
        return WebDAVService.instance.getFileUrl(connection, entry.path);
      case CupertinoLibraryBrowserSource.smb:
        final connection = widget.smbConnection;
        if (connection == null) return null;
        return SMBProxyService.instance.buildStreamUrl(connection, entry.path);
    }
  }

  String? _videoInfoPathForEntry(_BrowserEntry entry) {
    if (entry.isDirectory) return null;
    return _historyKeyForEntry(entry);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: AdaptiveSnackBarType.info,
    );
  }

  Future<void> _playLocalFile(_BrowserEntry entry) async {
    try {
      final fileName = entry.name;
      final historyItem = WatchHistoryItem(
        filePath: entry.path,
        animeName: p.basenameWithoutExtension(fileName),
        episodeTitle: '',
        duration: 0,
        lastPosition: 0,
        watchProgress: 0.0,
        lastWatchTime: DateTime.now(),
      );
      await WatchHistoryManager.addOrUpdateHistory(historyItem);

      final playable = PlayableItem(
        videoPath: entry.path,
        title: historyItem.animeName,
        historyItem: historyItem,
      );
      await PlaybackService().play(playable);
    } catch (e) {
      _showSnack('播放失败：$e');
    }
  }

  Future<void> _playWebDAVFile(_BrowserEntry entry) async {
    final connection = widget.webdavConnection;
    if (connection == null) {
      _showSnack('WebDAV 连接不可用');
      return;
    }
    try {
      final fileUrl = WebDAVService.instance.getFileUrl(connection, entry.path);
      final historyItem = WatchHistoryItem(
        filePath: fileUrl,
        animeName: p.basenameWithoutExtension(entry.name),
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
      _showSnack('播放失败：$e');
    }
  }

  Future<void> _playSMBFile(_BrowserEntry entry) async {
    final connection = widget.smbConnection;
    if (connection == null) {
      _showSnack('SMB 连接不可用');
      return;
    }
    try {
      final fileUrl =
          SMBProxyService.instance.buildStreamUrl(connection, entry.path);
      final historyItem = WatchHistoryItem(
        filePath: fileUrl,
        animeName: p.basenameWithoutExtension(entry.name),
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
      _showSnack('播放失败：$e');
    }
  }

  Future<void> _handleEntryTap(_BrowserEntry entry) async {
    if (entry.isDirectory) {
      _openFolder(entry);
      return;
    }
    switch (widget.source) {
      case CupertinoLibraryBrowserSource.local:
        await _playLocalFile(entry);
        return;
      case CupertinoLibraryBrowserSource.webdav:
        await _playWebDAVFile(entry);
        return;
      case CupertinoLibraryBrowserSource.smb:
        await _playSMBFile(entry);
        return;
    }
  }

  Future<void> _scanEntry(_BrowserEntry entry) async {
    if (entry.isDirectory) return;
    if (kIsWeb) {
      _showSnack('Web 端暂不支持扫描');
      return;
    }
    final targetPath = _videoInfoPathForEntry(entry);
    if (targetPath == null || targetPath.isEmpty) {
      _showSnack('无法读取文件路径');
      return;
    }

    final bool useNativeOverlay = PlatformInfo.isIOS26OrHigher();
    NavigatorState? navigator;
    ValueNotifier<_ScanProgressState>? progressNotifier;

    if (useNativeOverlay) {
      await AdaptiveNativeOverlay.showScanProgress(
        title: '正在扫描',
        message: entry.name,
        progress: 0.08,
      );
    } else {
      navigator = Navigator.of(context, rootNavigator: true);
      progressNotifier = ValueNotifier<_ScanProgressState>(
        const _ScanProgressState(progress: 0.08, message: '准备扫描'),
      );
      NipaplayWindow.show<void>(
        context: context,
        barrierDismissible: false,
        child: _ScanProgressWindow(
          fileName: entry.name,
          progressListenable: progressNotifier,
        ),
      );
    }

    void updateProgress(double progress, String message) {
      if (useNativeOverlay) {
        AdaptiveNativeOverlay.updateScanProgress(
          progress: progress,
          message: message,
        );
        return;
      }
      progressNotifier?.value = _ScanProgressState(
        progress: progress.clamp(0.0, 1.0),
        message: message,
      );
    }

    try {
      updateProgress(0.2, '读取文件信息');
      final videoInfo = await DandanplayService.getVideoInfo(targetPath)
          .timeout(const Duration(seconds: 20));
      updateProgress(0.75, '解析匹配结果');

      if (videoInfo['isMatched'] == true &&
          videoInfo['matches'] != null &&
          (videoInfo['matches'] as List).isNotEmpty) {
        final match = videoInfo['matches'][0];
        final animeId = match['animeId'] as int?;
        final episodeId = match['episodeId'] as int?;
        final animeTitle = (match['animeTitle'] as String?)?.isNotEmpty == true
            ? match['animeTitle'] as String
            : p.basenameWithoutExtension(entry.name);
        final episodeTitle = match['episodeTitle'] as String?;

        if (animeId != null && episodeId != null) {
          final existing = await WatchHistoryManager.getHistoryItem(targetPath);
          final int durationFromMatch = (videoInfo['duration'] is int)
              ? videoInfo['duration'] as int
              : (existing?.duration ?? 0);

          final WatchHistoryItem itemToSave;
          if (existing != null &&
              existing.watchProgress > 0.01 &&
              !existing.isFromScan) {
            itemToSave = WatchHistoryItem(
              filePath: existing.filePath,
              animeName: animeTitle,
              episodeTitle: episodeTitle,
              episodeId: episodeId,
              animeId: animeId,
              watchProgress: existing.watchProgress,
              lastPosition: existing.lastPosition,
              duration: durationFromMatch,
              lastWatchTime: DateTime.now(),
              thumbnailPath: existing.thumbnailPath,
              isFromScan: false,
            );
          } else {
            itemToSave = WatchHistoryItem(
              filePath: targetPath,
              animeName: animeTitle,
              episodeTitle: episodeTitle,
              episodeId: episodeId,
              animeId: animeId,
              watchProgress: existing?.watchProgress ?? 0.0,
              lastPosition: existing?.lastPosition ?? 0,
              duration: durationFromMatch,
              lastWatchTime: DateTime.now(),
              thumbnailPath: existing?.thumbnailPath,
              isFromScan: true,
            );
          }

          updateProgress(0.9, '保存匹配结果');
          await WatchHistoryManager.addOrUpdateHistory(itemToSave);
          if (mounted) {
            setState(() {});
          }
          updateProgress(1.0, '扫描完成');
          await Future.delayed(const Duration(milliseconds: 200));
          if (useNativeOverlay) {
            await AdaptiveNativeOverlay.showToast(
              message: '扫描完成：$animeTitle',
            );
          } else {
            _showSnack('扫描完成：$animeTitle');
          }
          return;
        }
      }

      updateProgress(1.0, '未匹配到番剧信息');
      await Future.delayed(const Duration(milliseconds: 200));
      if (useNativeOverlay) {
        await AdaptiveNativeOverlay.showToast(message: '未匹配到番剧信息');
      } else {
        _showSnack('未匹配到番剧信息');
      }
    } on TimeoutException {
      updateProgress(1.0, '扫描超时');
      await Future.delayed(const Duration(milliseconds: 200));
      if (useNativeOverlay) {
        await AdaptiveNativeOverlay.showToast(message: '扫描超时，请重试');
      } else {
        _showSnack('扫描超时，请重试');
      }
    } catch (e) {
      updateProgress(1.0, '扫描失败');
      await Future.delayed(const Duration(milliseconds: 200));
      if (useNativeOverlay) {
        await AdaptiveNativeOverlay.showToast(message: '扫描失败：$e');
      } else {
        _showSnack('扫描失败：$e');
      }
    } finally {
      if (useNativeOverlay) {
        await AdaptiveNativeOverlay.dismissScanProgress();
      } else {
        if (navigator?.canPop() ?? false) {
          navigator?.pop();
        }
        progressNotifier?.dispose();
      }
    }
  }

  Future<void> _showEntryActionSheet(_BrowserEntry entry) async {
    if (entry.isDirectory) return;
    await showCupertinoModalPopupWithBottomBar<void>(
      context: context,
      builder: (context) {
        final Color surfaceColor = CupertinoDynamicColor.resolve(
          CupertinoColors.systemBackground,
          context,
        );
        final Color separatorColor = CupertinoDynamicColor.resolve(
          CupertinoColors.separator,
          context,
        );
        final Color labelColor =
            CupertinoDynamicColor.resolve(CupertinoColors.label, context);
        final Color destructiveColor = CupertinoDynamicColor.resolve(
          CupertinoColors.systemRed,
          context,
        );

        Widget buildAction({
          required String title,
          required VoidCallback onPressed,
          Color? textColor,
          bool isLast = false,
        }) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  onPressed: onPressed,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: textColor ?? labelColor,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  height: 0.5,
                  width: double.infinity,
                  color: separatorColor,
                ),
            ],
          );
        }

        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoPopupSurface(
                    isSurfacePainted: true,
                    child: Container(
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Text(
                              entry.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.secondaryLabel,
                                  context,
                                ),
                              ),
                            ),
                          ),
                          Container(height: 0.5, color: separatorColor),
                          buildAction(
                            title: '扫描',
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await _scanEntry(entry);
                            },
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CupertinoPopupSurface(
                    isSurfacePainted: true,
                    child: Container(
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: buildAction(
                        title: '取消',
                        onPressed: () => Navigator.of(context).pop(),
                        textColor: destructiveColor,
                        isLast: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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

    final scope = CupertinoBottomSheetScope.maybeOf(context);
    final double contentTopInset = scope?.contentTopInset ?? 0;
    final double contentTopSpacing = scope?.contentTopSpacing ?? 0;
    final double headerTopPadding =
        (contentTopInset > 0 ? contentTopInset / 1.3 : 0) +
            contentTopSpacing +
            8;

    final slivers = <Widget>[];

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
    } else if (_errorMessage != null) {
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
    } else if (_entries.isEmpty) {
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
                  '当前目录为空',
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
    } else {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 10,
                childAspectRatio: 0.62,
              ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = _entries[index];
                  final historyKey = _historyKeyForEntry(entry);
                  return _FolderGridTile(
                    entry: entry,
                    labelColor: labelColor,
                    secondaryLabelColor: secondaryLabelColor,
                    countFuture: null,
                    historyFuture: historyKey == null
                        ? null
                        : WatchHistoryManager.getHistoryItem(historyKey),
                    onTap: () => _handleEntryTap(entry),
                    onLongPress: entry.isDirectory
                        ? null
                        : () => _showEntryActionSheet(entry),
                  );
                },
                childCount: _entries.length,
              ),
            ),
        ),
      );
    }

    return ColoredBox(
      color: backgroundColor,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, headerTopPadding, 20, 12),
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
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: slivers,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowserEntry {
  const _BrowserEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final bool isDirectory;
}

class _FolderGridTile extends StatefulWidget {
  const _FolderGridTile({
    required this.entry,
    required this.labelColor,
    required this.secondaryLabelColor,
    required this.countFuture,
    required this.onTap,
    required this.historyFuture,
    required this.onLongPress,
  });

  final _BrowserEntry entry;
  final Color labelColor;
  final Color secondaryLabelColor;
  final Future<int>? countFuture;
  final VoidCallback onTap;
  final Future<WatchHistoryItem?>? historyFuture;
  final VoidCallback? onLongPress;

  @override
  State<_FolderGridTile> createState() => _FolderGridTileState();
}

class _FolderGridTileState extends State<_FolderGridTile> {
  @override
  Widget build(BuildContext context) {
    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final iconColor = widget.entry.isDirectory
        ? CupertinoTheme.of(context).primaryColor
        : CupertinoDynamicColor.resolve(CupertinoColors.systemGrey, context);

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.systemGrey6,
                  context,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                widget.entry.isDirectory
                    ? CupertinoIcons.folder_fill
                    : CupertinoIcons.film,
                size: 90,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.entry.name.isNotEmpty
                  ? (widget.entry.isDirectory
                      ? widget.entry.name
                      : p.basenameWithoutExtension(widget.entry.name))
                  : widget.entry.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: widget.labelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            if (widget.historyFuture != null)
              FutureBuilder<WatchHistoryItem?>(
                future: widget.historyFuture,
                builder: (context, snapshot) {
                  final item = snapshot.data;
                  String label = '';
                  if (item == null) {
                    label = '未扫描';
                  } else if (item.animeId != null || item.episodeId != null) {
                    if (item.animeName.isNotEmpty &&
                        (item.episodeTitle?.isNotEmpty ?? false)) {
                      label = '${item.animeName} · ${item.episodeTitle}';
                    } else if (item.animeName.isNotEmpty) {
                      label = item.animeName;
                    } else {
                      label = '已匹配';
                    }
                  } else if (item.isFromScan) {
                    label = '已扫描';
                  } else {
                    label = '已播放';
                  }
                  return Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.secondaryLabelColor,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ScanProgressState {
  const _ScanProgressState({
    required this.progress,
    required this.message,
  });

  final double progress;
  final String message;
}

class _ScanProgressWindow extends StatelessWidget {
  const _ScanProgressWindow({
    required this.fileName,
    required this.progressListenable,
  });

  final String fileName;
  final ValueListenable<_ScanProgressState> progressListenable;

  @override
  Widget build(BuildContext context) {
    final Color labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final Color secondaryLabelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final Color primaryColor = CupertinoTheme.of(context).primaryColor;
    final Color trackColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey5,
      context,
    );

    return WillPopScope(
      onWillPop: () async => false,
      child: NipaplayWindowScaffold(
        showCloseButton: false,
        maxWidth: 420,
        maxHeightFactor: 0.5,
        child: Center(
          child: ValueListenableBuilder<_ScanProgressState>(
            valueListenable: progressListenable,
            builder: (context, value, _) {
              final double clamped =
                  value.progress.clamp(0.0, 1.0).toDouble();
              final int percent = (clamped * 100).round();
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '正在扫描',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: secondaryLabelColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ScanProgressBar(
                      progress: clamped,
                      color: primaryColor,
                      trackColor: trackColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$percent% · ${value.message}',
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryLabelColor,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ScanProgressBar extends StatelessWidget {
  const _ScanProgressBar({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final double clamped = progress.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 6,
        color: trackColor,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: clamped,
            child: Container(
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
