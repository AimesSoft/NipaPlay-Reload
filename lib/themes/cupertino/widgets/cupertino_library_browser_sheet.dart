import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_modal_popup.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

enum CupertinoLibraryBrowserSource { local, webdav, smb, sharedRemote }
enum CupertinoLibraryBrowserLayout { grid, list }
enum _BrowserSortOrder { nameAsc, nameDesc }

class CupertinoLibraryFolderBrowserSheet extends StatefulWidget {
  const CupertinoLibraryFolderBrowserSheet._({
    super.key,
    required this.source,
    required this.rootPath,
    required this.sourceLabel,
    this.webdavConnection,
    this.smbConnection,
    this.sharedRemoteProvider,
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

  factory CupertinoLibraryFolderBrowserSheet.sharedRemote({
    Key? key,
    required SharedRemoteLibraryProvider provider,
    String rootPath = '/',
    String? sourceLabel,
  }) {
    final host = provider.activeHost;
    final label =
        sourceLabel ?? host?.displayName ?? host?.baseUrl ?? '共享媒体库';
    return CupertinoLibraryFolderBrowserSheet._(
      key: key,
      source: CupertinoLibraryBrowserSource.sharedRemote,
      rootPath: rootPath,
      sourceLabel: label,
      sharedRemoteProvider: provider,
    );
  }

  final CupertinoLibraryBrowserSource source;
  final String rootPath;
  final String sourceLabel;
  final WebDAVConnection? webdavConnection;
  final SMBConnection? smbConnection;
  final SharedRemoteLibraryProvider? sharedRemoteProvider;

  @override
  State<CupertinoLibraryFolderBrowserSheet> createState() =>
      _CupertinoLibraryFolderBrowserSheetState();
}

class _CupertinoLibraryFolderBrowserSheetState
    extends State<CupertinoLibraryFolderBrowserSheet> {
  static const String _lastPathKeyPrefix =
      'cupertino_library_browser_last_path_';
  final ScrollController _scrollController = ScrollController();
  // Reserved for future: folder counts (disabled for accuracy).
  final List<String> _pathStack = [];

  bool _isLoading = false;
  String? _errorMessage;
  List<_BrowserEntry> _entries = [];
  String _searchQuery = '';
  CupertinoLibraryBrowserLayout _layout = CupertinoLibraryBrowserLayout.grid;
  _BrowserSortOrder _sortOrder = _BrowserSortOrder.nameAsc;
  String? _restoredPath;
  final Map<String, List<_BrowserEntry>> _expandedEntries = {};
  final Set<String> _expandedDirectories = {};
  final Set<String> _loadingDirectories = {};
  final Map<String, String> _expandedErrors = {};
  bool _isBatchScanning = false;

  String get _currentPath => _pathStack.isNotEmpty
      ? _pathStack.last
      : widget.rootPath;

  bool get _canGoBack => _pathStack.length > 1;

  @override
  void initState() {
    super.initState();
    _pathStack.add(widget.rootPath);
    _restoreLastPathAndLoad();
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
      _resetExpansionState();
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _loadDirectory();
  }

  void _goRoot() {
    if (_currentPath == widget.rootPath) return;
    setState(() {
      _pathStack
        ..clear()
        ..add(widget.rootPath);
      _entries = [];
      _errorMessage = null;
      _resetExpansionState();
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _resetExpansionState();
    });

    try {
      final entries = await _listDirectories(_currentPath);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
      await _saveLastPath(_currentPath);
    } catch (e) {
      if (!mounted) return;
      if (_restoredPath != null && _currentPath == _restoredPath) {
        _restoredPath = null;
        setState(() {
          _pathStack
            ..clear()
            ..add(widget.rootPath);
          _entries = [];
          _isLoading = false;
          _errorMessage = null;
        });
        _loadDirectory();
        return;
      }
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
      final compare =
          a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return _sortOrder == _BrowserSortOrder.nameAsc ? compare : -compare;
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
      case CupertinoLibraryBrowserSource.sharedRemote:
        final provider = widget.sharedRemoteProvider;
        if (provider == null) {
          throw Exception('共享媒体库不可用');
        }
        if (path == widget.rootPath) {
          if (provider.scannedFolders.isEmpty) {
            await provider.refreshManagement(userInitiated: true);
          }
          final folders = provider.scannedFolders;
          if (folders.isEmpty) {
            final message = provider.managementErrorMessage;
            if (message != null && message.trim().isNotEmpty) {
              throw Exception(message);
            }
          }
          final result = folders
              .map((folder) => _BrowserEntry(
                    name: folder.name.isNotEmpty
                        ? folder.name
                        : p.basename(folder.path),
                    path: folder.path,
                    isDirectory: true,
                  ))
              .toList();
          return _sortEntries(result);
        }
        final entries = await provider.browseRemoteDirectory(path);
        final result = entries
            .map((entry) => _BrowserEntry(
                  name: entry.name.isNotEmpty ? entry.name : p.basename(entry.path),
                  path: entry.path,
                  isDirectory: entry.isDirectory,
                  animeName: entry.animeName,
                  episodeTitle: entry.episodeTitle,
                  animeId: entry.animeId,
                  episodeId: entry.episodeId,
                  isFromScan: entry.isFromScan,
                ))
            .toList();
        return _sortEntries(result);
    }
  }

  void _resetExpansionState() {
    _expandedDirectories.clear();
    _expandedEntries.clear();
    _loadingDirectories.clear();
    _expandedErrors.clear();
  }


  void _openFolder(_BrowserEntry entry) {
    if (!entry.isDirectory) {
      return;
    }
    setState(() {
      _pathStack.add(entry.path);
      _entries = [];
      _errorMessage = null;
      _resetExpansionState();
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _loadDirectory();
  }

  Future<void> _toggleDirectoryExpansion(_BrowserEntry entry) async {
    if (!entry.isDirectory) return;
    final path = entry.path;
    if (_expandedDirectories.contains(path)) {
      setState(() {
        _expandedDirectories.remove(path);
      });
      return;
    }

    setState(() {
      _expandedDirectories.add(path);
      _expandedErrors.remove(path);
      if (!_expandedEntries.containsKey(path)) {
        _loadingDirectories.add(path);
      }
    });

    if (_expandedEntries.containsKey(path)) return;
    try {
      final entries = await _listDirectories(path);
      if (!mounted) return;
      setState(() {
        _expandedEntries[path] = entries;
        _loadingDirectories.remove(path);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _expandedErrors[path] = e.toString();
        _loadingDirectories.remove(path);
      });
    }
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
      case CupertinoLibraryBrowserSource.sharedRemote:
        final provider = widget.sharedRemoteProvider;
        if (provider == null) return null;
        try {
          return provider.buildRemoteFileStreamUri(entry.path).toString();
        } catch (_) {
          return null;
        }
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

  Future<void> _playSharedRemoteFile(_BrowserEntry entry) async {
    final provider = widget.sharedRemoteProvider;
    if (provider == null) {
      _showSnack('共享媒体库不可用');
      return;
    }
    try {
      final streamUrl =
          provider.buildRemoteFileStreamUri(entry.path).toString();
      final fallbackName =
          entry.name.isNotEmpty ? entry.name : p.basename(entry.path);
      final title = p.basenameWithoutExtension(fallbackName);
      final animeName = (entry.animeName?.trim().isNotEmpty ?? false)
          ? entry.animeName!.trim()
          : (title.isNotEmpty ? title : fallbackName);
      final historyItem = WatchHistoryItem(
        filePath: streamUrl,
        animeName: animeName,
        episodeTitle: entry.episodeTitle?.trim().isNotEmpty == true
            ? entry.episodeTitle!.trim()
            : null,
        animeId: entry.animeId,
        episodeId: entry.episodeId,
        watchProgress: 0.0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
        isFromScan: entry.isFromScan ?? false,
      );
      await WatchHistoryManager.addOrUpdateHistory(historyItem);

      final playable = PlayableItem(
        videoPath: streamUrl,
        title: historyItem.animeName,
        subtitle: historyItem.episodeTitle,
        animeId: historyItem.animeId,
        episodeId: historyItem.episodeId,
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
      case CupertinoLibraryBrowserSource.sharedRemote:
        await _playSharedRemoteFile(entry);
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

  Future<_ScanOutcome> _scanFileEntry(_BrowserEntry entry) async {
    if (entry.isDirectory) return _ScanOutcome.failed;
    final targetPath = _videoInfoPathForEntry(entry);
    if (targetPath == null || targetPath.isEmpty) {
      return _ScanOutcome.failed;
    }

    try {
      final videoInfo = await DandanplayService.getVideoInfo(targetPath)
          .timeout(const Duration(seconds: 20));

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

          await WatchHistoryManager.addOrUpdateHistory(itemToSave);
          if (mounted) {
            setState(() {});
          }
          return _ScanOutcome.matched;
        }
      }
      return _ScanOutcome.unmatched;
    } on TimeoutException {
      return _ScanOutcome.failed;
    } catch (_) {
      return _ScanOutcome.failed;
    }
  }

  Future<List<_BrowserEntry>> _collectVideoFiles(String path) async {
    switch (widget.source) {
      case CupertinoLibraryBrowserSource.local:
        return _collectLocalVideoFiles(path);
      case CupertinoLibraryBrowserSource.webdav:
        return _collectWebDAVVideoFiles(path);
      case CupertinoLibraryBrowserSource.smb:
        return _collectSMBVideoFiles(path);
      case CupertinoLibraryBrowserSource.sharedRemote:
        return _collectSharedRemoteVideoFiles(path);
    }
  }

  Future<List<_BrowserEntry>> _collectLocalVideoFiles(String path) async {
    final results = <_BrowserEntry>[];
    final directory = Directory(path);
    if (!await directory.exists()) {
      return results;
    }
    await for (final entity
        in directory.list(recursive: false, followLinks: false)) {
      if (entity is Directory) {
        results.addAll(await _collectLocalVideoFiles(entity.path));
      } else if (entity is File) {
        final fileName = p.basename(entity.path);
        if (SMBService.instance.isVideoFile(fileName)) {
          results.add(
            _BrowserEntry(
              name: fileName,
              path: entity.path,
              isDirectory: false,
            ),
          );
        }
      }
    }
    return results;
  }

  Future<List<_BrowserEntry>> _collectWebDAVVideoFiles(String path) async {
    final connection = widget.webdavConnection;
    if (connection == null) {
      throw Exception('WebDAV 连接不可用');
    }
    final results = <_BrowserEntry>[];
    final entries = await WebDAVService.instance.listDirectory(
      connection,
      path,
    );
    for (final entry in entries) {
      if (entry.isDirectory) {
        results.addAll(await _collectWebDAVVideoFiles(entry.path));
      } else if (WebDAVService.instance.isVideoFile(entry.name)) {
        results.add(
          _BrowserEntry(
            name: entry.name,
            path: entry.path,
            isDirectory: false,
          ),
        );
      }
    }
    return results;
  }

  Future<List<_BrowserEntry>> _collectSMBVideoFiles(String path) async {
    final connection = widget.smbConnection;
    if (connection == null) {
      throw Exception('SMB 连接不可用');
    }
    final results = <_BrowserEntry>[];
    final entries = await SMBService.instance.listDirectory(
      connection,
      path,
    );
    for (final entry in entries) {
      if (entry.isDirectory) {
        results.addAll(await _collectSMBVideoFiles(entry.path));
      } else if (SMBService.instance.isVideoFile(entry.name)) {
        results.add(
          _BrowserEntry(
            name: entry.name,
            path: entry.path,
            isDirectory: false,
          ),
        );
      }
    }
    return results;
  }

  Future<List<_BrowserEntry>> _collectSharedRemoteVideoFiles(String path) async {
    final provider = widget.sharedRemoteProvider;
    if (provider == null) {
      throw Exception('共享媒体库不可用');
    }
    final results = <_BrowserEntry>[];
    final entries = await provider.browseRemoteDirectory(path);
    for (final entry in entries) {
      if (entry.isDirectory) {
        results.addAll(await _collectSharedRemoteVideoFiles(entry.path));
      } else if (SMBService.instance.isVideoFile(entry.name)) {
        results.add(
          _BrowserEntry(
            name: entry.name.isNotEmpty ? entry.name : p.basename(entry.path),
            path: entry.path,
            isDirectory: false,
          ),
        );
      }
    }
    return results;
  }

  Future<void> _scanFolder(_BrowserEntry entry) async {
    if (!entry.isDirectory) return;
    if (kIsWeb) {
      _showSnack('Web 端暂不支持扫描');
      return;
    }
    if (_isBatchScanning) {
      _showSnack('已有扫描任务在进行中，请稍后再试。');
      return;
    }

    _isBatchScanning = true;
    final displayName =
        entry.name.isNotEmpty ? entry.name : p.basename(entry.path);
    final bool useNativeOverlay = PlatformInfo.isIOS26OrHigher();
    NavigatorState? navigator;
    ValueNotifier<_ScanProgressState>? progressNotifier;

    if (useNativeOverlay) {
      await AdaptiveNativeOverlay.showScanProgress(
        title: '正在扫描',
        message: displayName,
        progress: 0.05,
      );
    } else {
      navigator = Navigator.of(context, rootNavigator: true);
      progressNotifier = ValueNotifier<_ScanProgressState>(
        const _ScanProgressState(progress: 0.05, message: '准备扫描'),
      );
      NipaplayWindow.show<void>(
        context: context,
        barrierDismissible: false,
        child: _ScanProgressWindow(
          fileName: displayName,
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
      updateProgress(0.08, '正在整理文件列表');
      final files = await _collectVideoFiles(entry.path);
      if (files.isEmpty) {
        updateProgress(1.0, '未找到可扫描的视频文件');
        await Future.delayed(const Duration(milliseconds: 200));
        if (useNativeOverlay) {
          await AdaptiveNativeOverlay.showToast(message: '未找到可扫描的视频文件');
        } else {
          _showSnack('未找到可扫描的视频文件');
        }
        return;
      }

      int matched = 0;
      int unmatched = 0;
      int failed = 0;
      final total = files.length;

      for (int i = 0; i < total; i++) {
        final file = files[i];
        final progress = 0.1 + ((i + 1) / total) * 0.85;
        updateProgress(
          progress,
          '扫描中 ${file.name} (${i + 1}/$total)',
        );
        final result = await _scanFileEntry(file);
        switch (result) {
          case _ScanOutcome.matched:
            matched += 1;
            break;
          case _ScanOutcome.unmatched:
            unmatched += 1;
            break;
          case _ScanOutcome.failed:
            failed += 1;
            break;
        }
      }

      updateProgress(1.0, '扫描完成');
      await Future.delayed(const Duration(milliseconds: 200));
      final summary = '扫描完成：匹配 $matched，未匹配 $unmatched，失败 $failed';
      if (useNativeOverlay) {
        await AdaptiveNativeOverlay.showToast(message: summary);
      } else {
        _showSnack(summary);
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
      _isBatchScanning = false;
    }
  }

  Future<void> _showEntryActionSheet(_BrowserEntry entry) async {
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
                            title: entry.isDirectory ? '扫描文件夹' : '扫描',
                            onPressed: () async {
                              Navigator.of(context).pop();
                              if (entry.isDirectory) {
                                await _scanFolder(entry);
                              } else {
                                await _scanEntry(entry);
                              }
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

  List<_BrowserEntry> _applySearch(List<_BrowserEntry> entries) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return entries;
    return entries.where((entry) {
      final name = entry.isDirectory
          ? entry.name
          : p.basenameWithoutExtension(entry.name);
      final candidate = name.isNotEmpty ? name : entry.name;
      return candidate.toLowerCase().contains(query);
    }).toList();
  }

  List<_ListItem> _buildListItems(List<_BrowserEntry> entries, int depth) {
    final items = <_ListItem>[];
    for (final entry in entries) {
      items.add(_ListItem.entry(entry, depth: depth));
      if (!entry.isDirectory) continue;
      if (!_expandedDirectories.contains(entry.path)) continue;

      if (_loadingDirectories.contains(entry.path)) {
        items.add(_ListItem.loading(entry.path, depth: depth + 1));
        continue;
      }

      final error = _expandedErrors[entry.path];
      if (error != null) {
        items.add(_ListItem.error(entry.path, error, depth: depth + 1));
        continue;
      }

      final children = _expandedEntries[entry.path] ?? const <_BrowserEntry>[];
      final visibleChildren = _applySearch(children);
      if (visibleChildren.isEmpty) {
        final message = _searchQuery.trim().isNotEmpty ? '无匹配内容' : '空文件夹';
        items.add(_ListItem.empty(entry.path, message, depth: depth + 1));
        continue;
      }
      items.addAll(_buildListItems(visibleChildren, depth + 1));
    }
    return items;
  }

  Future<void> _restoreLastPathAndLoad() async {
    final lastPath = await _loadLastPath();
    if (lastPath != null && _isValidRestoredPath(lastPath)) {
      _restoredPath = lastPath;
      setState(() {
        _pathStack
          ..clear()
          ..add(lastPath);
      });
    }
    _loadDirectory();
  }

  bool _isValidRestoredPath(String path) {
    if (path.isEmpty) return false;
    if (widget.source == CupertinoLibraryBrowserSource.local) {
      return path == widget.rootPath || path.startsWith(widget.rootPath);
    }
    return true;
  }

  String _storageKey() {
    String id;
    switch (widget.source) {
      case CupertinoLibraryBrowserSource.local:
        id = widget.rootPath;
        break;
      case CupertinoLibraryBrowserSource.webdav:
        final connection = widget.webdavConnection;
        id = connection == null
            ? widget.rootPath
            : '${connection.url}|${connection.username}';
        break;
      case CupertinoLibraryBrowserSource.smb:
        final connection = widget.smbConnection;
        id = connection == null
            ? widget.rootPath
            : '${connection.host}|${connection.port}|${connection.username}|${connection.domain}';
        break;
      case CupertinoLibraryBrowserSource.sharedRemote:
        final host = widget.sharedRemoteProvider?.activeHost;
        id = host == null
            ? widget.rootPath
            : '${host.baseUrl}|${host.id}';
        break;
    }
    final encoded = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
    return '$_lastPathKeyPrefix${widget.source.name}_$encoded';
  }

  Future<void> _saveLastPath(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey(), path);
    } catch (_) {}
  }

  Future<String?> _loadLastPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_storageKey());
    } catch (_) {
      return null;
    }
  }

  void _toggleLayout() {
    setState(() {
      _layout = _layout == CupertinoLibraryBrowserLayout.grid
          ? CupertinoLibraryBrowserLayout.list
          : CupertinoLibraryBrowserLayout.grid;
    });
  }

  IconData _layoutIcon() {
    return _layout == CupertinoLibraryBrowserLayout.grid
        ? CupertinoIcons.list_bullet
        : CupertinoIcons.square_grid_2x2;
  }

  void _toggleSortOrder() {
    setState(() {
      _sortOrder = _sortOrder == _BrowserSortOrder.nameAsc
          ? _BrowserSortOrder.nameDesc
          : _BrowserSortOrder.nameAsc;
      _entries = _sortEntries(List<_BrowserEntry>.from(_entries));
      _expandedEntries.updateAll((_, value) {
        return _sortEntries(List<_BrowserEntry>.from(value));
      });
    });
  }

  IconData _sortIcon() {
    return _sortOrder == _BrowserSortOrder.nameAsc
        ? CupertinoIcons.arrow_up
        : CupertinoIcons.arrow_down;
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
    final visibleEntries = _applySearch(_entries);

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
    } else if (visibleEntries.isEmpty) {
      final bool isSearching = _searchQuery.trim().isNotEmpty;
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
                  isSearching ? '未找到匹配内容' : '当前目录为空',
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
    } else if (_layout == CupertinoLibraryBrowserLayout.grid) {
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
                final entry = visibleEntries[index];
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
                    onLongPress: () => _showEntryActionSheet(entry),
                  );
                },
                childCount: visibleEntries.length,
              ),
            ),
        ),
      );
    } else {
      final listItems = _buildListItems(visibleEntries, 0);
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = listItems[index];
                switch (item.type) {
                  case _ListItemType.entry:
                    final entry = item.entry!;
                    final historyKey = _historyKeyForEntry(entry);
                    final tile = _FolderListTile(
                      entry: entry,
                      depth: item.depth,
                      isExpanded: entry.isDirectory &&
                          _expandedDirectories.contains(entry.path),
                      labelColor: labelColor,
                      secondaryLabelColor: secondaryLabelColor,
                      historyFuture: historyKey == null
                          ? null
                          : WatchHistoryManager.getHistoryItem(historyKey),
                      onTap: entry.isDirectory
                          ? () => _toggleDirectoryExpansion(entry)
                          : () => _handleEntryTap(entry),
                      onLongPress: () => _showEntryActionSheet(entry),
                    );
                    return _ListAppear(
                      key: ValueKey('entry_${entry.path}_${item.depth}'),
                      animate: item.depth > 0,
                      child: tile,
                    );
                  case _ListItemType.loading:
                    return _ListAppear(
                      key: ValueKey('loading_${item.path}_${item.depth}'),
                      animate: item.depth > 0,
                      child: _FolderListStatusTile(
                        depth: item.depth,
                        text: '正在加载...',
                        showSpinner: true,
                      ),
                    );
                  case _ListItemType.empty:
                    return _ListAppear(
                      key: ValueKey('empty_${item.path}_${item.depth}'),
                      animate: item.depth > 0,
                      child: _FolderListStatusTile(
                        depth: item.depth,
                        text: item.message ?? '空文件夹',
                      ),
                    );
                  case _ListItemType.error:
                    return _ListAppear(
                      key: ValueKey('error_${item.path}_${item.depth}'),
                      animate: item.depth > 0,
                      child: _FolderListStatusTile(
                        depth: item.depth,
                        text: item.message ?? '读取失败',
                        isError: true,
                      ),
                    );
                }
              },
              childCount: listItems.length,
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
            padding: EdgeInsets.fromLTRB(20, headerTopPadding, 20, 10),
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
                  onPressed: _currentPath == widget.rootPath ? null : _goRoot,
                  child: const Icon(CupertinoIcons.home, size: 20),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: _toggleLayout,
                  child: Icon(_layoutIcon(), size: 20),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: _toggleSortOrder,
                  child: Icon(_sortIcon(), size: 20),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: _loadDirectory,
                  child: const Icon(CupertinoIcons.refresh_thin, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: CupertinoSearchTextField(
              placeholder: '搜索文件/文件夹',
              onChanged: (value) {
                if (_searchQuery == value) return;
                setState(() => _searchQuery = value);
              },
              backgroundColor: CupertinoDynamicColor.resolve(
                CupertinoColors.systemGrey5,
                context,
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return currentChild ?? const SizedBox.shrink();
              },
              transitionBuilder: (child, animation) {
                final position = Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).chain(CurveTween(curve: Curves.easeOutCubic));
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: animation.drive(position),
                    child: child,
                  ),
                );
              },
              child: CustomScrollView(
                key: ValueKey('${_currentPath}_${_layout.name}'),
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: slivers,
              ),
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
    this.animeName,
    this.episodeTitle,
    this.animeId,
    this.episodeId,
    this.isFromScan,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final String? animeName;
  final String? episodeTitle;
  final int? animeId;
  final int? episodeId;
  final bool? isFromScan;
}

enum _ScanOutcome { matched, unmatched, failed }

String _labelForEntry(_BrowserEntry entry, WatchHistoryItem? item) {
  final metaLabel = _entryMetadataLabel(entry);
  if (item == null) {
    return metaLabel ?? '未扫描';
  }

  final hasHistoryIds = item.animeId != null || item.episodeId != null;
  if (hasHistoryIds || item.isFromScan) {
    return _historyItemLabel(item);
  }

  return metaLabel ?? _historyItemLabel(item);
}

String? _entryMetadataLabel(_BrowserEntry entry) {
  final animeName = entry.animeName?.trim();
  final episodeTitle = entry.episodeTitle?.trim();
  final hasIds = (entry.animeId ?? 0) > 0 || (entry.episodeId ?? 0) > 0;

  if (animeName != null && animeName.isNotEmpty) {
    if (episodeTitle != null && episodeTitle.isNotEmpty) {
      return '$animeName · $episodeTitle';
    }
    return animeName;
  }
  if (episodeTitle != null && episodeTitle.isNotEmpty) {
    return episodeTitle;
  }
  if (hasIds) {
    return '已匹配';
  }
  if (entry.isFromScan == true) {
    return '已扫描';
  }
  return null;
}

String _historyItemLabel(WatchHistoryItem item) {
  if (item.animeId != null || item.episodeId != null) {
    if (item.animeName.isNotEmpty &&
        (item.episodeTitle?.isNotEmpty ?? false)) {
      return '${item.animeName} · ${item.episodeTitle}';
    }
    if (item.animeName.isNotEmpty) {
      return item.animeName;
    }
    return '已匹配';
  }
  if (item.isFromScan) {
    return '已扫描';
  }
  return '已播放';
}

enum _ListItemType { entry, loading, empty, error }

class _ListItem {
  _ListItem.entry(_BrowserEntry entry, {required this.depth})
      : type = _ListItemType.entry,
        entry = entry,
        path = entry.path,
        message = null;

  _ListItem.loading(this.path, {required this.depth})
      : type = _ListItemType.loading,
        entry = null,
        message = null;

  _ListItem.empty(this.path, this.message, {required this.depth})
      : type = _ListItemType.empty,
        entry = null;

  _ListItem.error(this.path, this.message, {required this.depth})
      : type = _ListItemType.error,
        entry = null;

  final _ListItemType type;
  final _BrowserEntry? entry;
  final String path;
  final int depth;
  final String? message;
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
            const SizedBox(height: 4),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                widget.entry.name.isNotEmpty
                    ? (widget.entry.isDirectory
                        ? widget.entry.name
                        : p.basenameWithoutExtension(widget.entry.name))
                    : widget.entry.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: widget.labelColor,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(height: 2),
            if (widget.historyFuture != null)
              Flexible(
                fit: FlexFit.loose,
                child: FutureBuilder<WatchHistoryItem?>(
                  future: widget.historyFuture,
                  builder: (context, snapshot) {
                    final label =
                        _labelForEntry(widget.entry, snapshot.data);
                    return Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.secondaryLabelColor,
                        height: 1.15,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FolderListTile extends StatelessWidget {
  const _FolderListTile({
    required this.entry,
    required this.depth,
    required this.isExpanded,
    required this.labelColor,
    required this.secondaryLabelColor,
    required this.onTap,
    required this.historyFuture,
    required this.onLongPress,
  });

  final _BrowserEntry entry;
  final int depth;
  final bool isExpanded;
  final Color labelColor;
  final Color secondaryLabelColor;
  final VoidCallback onTap;
  final Future<WatchHistoryItem?>? historyFuture;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final mutedColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final iconColor = entry.isDirectory
        ? CupertinoTheme.of(context).primaryColor
        : CupertinoDynamicColor.resolve(CupertinoColors.systemGrey, context);
    final nameText = entry.name.isNotEmpty
        ? (entry.isDirectory
            ? entry.name
            : p.basenameWithoutExtension(entry.name))
        : entry.path;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (depth > 0) SizedBox(width: depth * 12.0),
              if (entry.isDirectory)
                Icon(
                  isExpanded
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_right,
                  size: 16,
                  color: mutedColor,
                )
              else
                const SizedBox(width: 16),
              const SizedBox(width: 2),
              Icon(
                entry.isDirectory
                    ? CupertinoIcons.folder_fill
                    : CupertinoIcons.film,
                size: entry.isDirectory ? 22 : 20,
                color: iconColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: entry.isDirectory
                    ? Text(
                        nameText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            nameText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: labelColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (historyFuture != null)
                            FutureBuilder<WatchHistoryItem?>(
                              future: historyFuture,
                              builder: (context, snapshot) {
                                final label =
                                    _labelForEntry(entry, snapshot.data);
                                return Text(
                                  label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: secondaryLabelColor,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListAppear extends StatelessWidget {
  const _ListAppear({
    super.key,
    required this.child,
    required this.animate,
  });

  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: animate ? 12.0 : 0.0, end: 0.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, value, child) {
        final opacity = (1 - (value / 12.0)).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, value),
          child: Opacity(opacity: opacity, child: child),
        );
      },
    );
  }
}

class _FolderListStatusTile extends StatelessWidget {
  const _FolderListStatusTile({
    required this.depth,
    required this.text,
    this.isError = false,
    this.showSpinner = false,
  });

  final int depth;
  final String text;
  final bool isError;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemBackground,
      context,
    );
    final textColor = CupertinoDynamicColor.resolve(
      isError ? CupertinoColors.systemRed : CupertinoColors.secondaryLabel,
      context,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (depth > 0) SizedBox(width: depth * 12.0),
            if (showSpinner) ...[
              const CupertinoActivityIndicator(radius: 7),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
              ),
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
