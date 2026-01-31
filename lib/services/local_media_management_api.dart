import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/smb_service.dart';

class _RemoteScrapeCandidate {
  final String filePath;
  final String fileName;

  const _RemoteScrapeCandidate({
    required this.filePath,
    required this.fileName,
  });
}

class _RemoteScrapeResult {
  final int total;
  final int matched;
  final int failed;

  const _RemoteScrapeResult({
    required this.total,
    required this.matched,
    required this.failed,
  });
}

class LocalMediaManagementApi {
  LocalMediaManagementApi() {
    router.get('/folders', _handleListFolders);
    router.post('/folders', _handleAddFolder);
    router.delete('/folders', _handleRemoveFolder);

    // WebDAV Management
    router.post('/webdav', _handleAddWebDAV);
    router.delete('/webdav', _handleRemoveWebDAV);
    router.get('/webdav/list', _handleListWebDAV);
    router.post('/webdav/test', _handleTestWebDAV);
    router.post('/webdav/scan', _handleScanWebDAV);

    // SMB Management
    router.post('/smb', _handleAddSMB);
    router.delete('/smb', _handleRemoveSMB);
    router.get('/smb/list', _handleListSMB);
    router.post('/smb/test', _handleTestSMB);
    router.post('/smb/scan', _handleScanSMB);

    router.get('/browse', _handleBrowse);
    router.get('/stream', _handleStream);
    router.add('HEAD', '/stream', _handleStreamHead);

    router.get('/scan/status', _handleScanStatus);
    router.post('/scan/rescan', _handleRescanAll);
  }

  final Router router = Router();

  ScanService get _scanService => ServiceProvider.scanService;
  WebDAVService get _webdavService => WebDAVService.instance;
  SMBService get _smbService => SMBService.instance;

  static const Set<String> _allowedMediaExtensions = {
    '.mp4',
    '.m4v',
    '.mkv',
    '.mov',
    '.avi',
    '.flv',
    '.ts',
    '.mpeg',
    '.mpg',
    '.webm',
    '.mp3',
    '.flac',
    '.aac',
    '.wav',
    '.ass',
    '.ssa',
    '.srt',
  };

  Future<Response> _handleListFolders(Request request) async {
    try {
      final folders = await _buildFolderPayload(_scanService.scannedFolders);
      final webdav = _webdavService.connections.map((c) => c.toJson()).toList();
      final smb = _smbService.connections.map((c) => c.toJson()).toList();
      
      return _jsonOk({
        'success': true,
        'data': {
          'folders': folders,
          'webdav': webdav,
          'smb': smb,
        },
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '读取库列表失败: $e');
    }
  }

  // --- WebDAV Handlers ---

  Future<Response> _handleAddWebDAV(Request request) async {
    try {
      final body = await request.readAsString();
      final payload = json.decode(body) as Map<String, dynamic>;
      final connection = WebDAVConnection.fromJson(payload);
      
      final success = await _webdavService.addConnection(connection);
      if (success) {
        return _jsonOk({'success': true, 'message': 'WebDAV 连接已添加'});
      } else {
        return _jsonError(HttpStatus.badRequest, 'WebDAV 连接测试失败');
      }
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '添加 WebDAV 失败: $e');
    }
  }

  Future<Response> _handleRemoveWebDAV(Request request) async {
    final name = request.url.queryParameters['name'];
    if (name == null || name.isEmpty) {
      return _jsonError(HttpStatus.badRequest, 'Missing name');
    }
    try {
      await _webdavService.removeConnection(name);
      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '移除 WebDAV 失败: $e');
    }
  }

  Future<Response> _handleListWebDAV(Request request) async {
    final name = request.url.queryParameters['name']?.trim();
    final path = request.url.queryParameters['path']?.trim() ?? '/';
    if (name == null || name.isEmpty) {
      return _jsonError(HttpStatus.badRequest, 'Missing name');
    }

    final connection = _webdavService.getConnection(name);
    if (connection == null) {
      return _jsonError(HttpStatus.notFound, 'WebDAV connection not found');
    }

    try {
      final files = await _webdavService.listDirectory(connection, path);
      final entries = files
          .map((file) => {
                'name': file.name,
                'path': file.path,
                'isDirectory': file.isDirectory,
                'size': file.size,
                'lastModified': file.lastModified?.toIso8601String(),
              })
          .toList();
      return _jsonOk({
        'success': true,
        'data': {
          'path': path,
          'entries': entries,
        },
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '读取WebDAV目录失败: $e');
    }
  }

  Future<Response> _handleTestWebDAV(Request request) async {
    try {
      final name = request.url.queryParameters['name']?.trim();
      if (name != null && name.isNotEmpty) {
        final existing = _webdavService.getConnection(name);
        if (existing == null) {
          return _jsonError(HttpStatus.notFound, 'WebDAV connection not found');
        }
        await _webdavService.updateConnectionStatus(name);
        final updated = _webdavService.getConnection(name);
        return _jsonOk({
          'success': true,
          'data': {'isConnected': updated?.isConnected ?? false},
        });
      }

      final body = await request.readAsString();
      if (body.trim().isEmpty) {
        return _jsonError(HttpStatus.badRequest, 'Missing payload');
      }
      final decoded = json.decode(body);
      final payload = decoded is Map<String, dynamic>
          ? decoded
          : (decoded is Map ? decoded.cast<String, dynamic>() : null);
      if (payload == null) {
        return _jsonError(HttpStatus.badRequest, 'Invalid JSON payload');
      }

      final connection = WebDAVConnection.fromJson(payload);
      final ok = await _webdavService.testConnection(connection);
      return _jsonOk({
        'success': true,
        'data': {'isConnected': ok},
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '测试 WebDAV 失败: $e');
    }
  }

  Future<Response> _handleScanWebDAV(Request request) async {
    Map<String, dynamic> payload = const {};
    try {
      final body = await request.readAsString();
      if (body.isNotEmpty) {
        payload = json.decode(body) as Map<String, dynamic>;
      }
    } catch (_) {
      return _jsonError(HttpStatus.badRequest, 'Invalid JSON payload');
    }

    final name = (payload['name'] ?? payload['connection'] ?? '').toString().trim();
    final folderPath =
        (payload['path'] ?? payload['folderPath'] ?? '/').toString().trim();
    if (name.isEmpty) {
      return _jsonError(HttpStatus.badRequest, 'Missing WebDAV connection name');
    }

    final connection = _webdavService.getConnection(name);
    if (connection == null) {
      return _jsonError(HttpStatus.notFound, 'WebDAV connection not found');
    }

    try {
      final files = await _collectWebDavVideoFiles(connection, folderPath);
      if (files.isEmpty) {
        return _jsonOk({
          'success': true,
          'data': {'total': 0, 'matched': 0, 'failed': 0},
        });
      }

      final candidates = files
          .map((file) => _RemoteScrapeCandidate(
                filePath: _webdavService.getFileUrl(connection, file.path),
                fileName: file.name,
              ))
          .toList();
      final result = await _scrapeRemoteFiles(
        sourceLabel: 'WebDAV',
        candidates: candidates,
      );
      await ServiceProvider.watchHistoryProvider.refresh();
      return _jsonOk({
        'success': true,
        'data': {
          'total': result.total,
          'matched': result.matched,
          'failed': result.failed,
        },
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '刮削WebDAV文件夹失败: $e');
    }
  }

  // --- SMB Handlers ---

  Future<Response> _handleAddSMB(Request request) async {
    try {
      final body = await request.readAsString();
      final payload = json.decode(body) as Map<String, dynamic>;
      final connection = SMBConnection.fromJson(payload);
      
      // Check if updating or adding
      final existing = _smbService.getConnection(connection.name);
      bool success;
      if (existing != null) {
        success = await _smbService.updateConnection(connection.name, connection);
      } else {
        success = await _smbService.addConnection(connection);
      }

      if (success) {
        return _jsonOk({'success': true, 'message': 'SMB 连接已保存'});
      } else {
        return _jsonError(HttpStatus.badRequest, 'SMB 连接测试失败');
      }
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '保存 SMB 失败: $e');
    }
  }

  Future<Response> _handleRemoveSMB(Request request) async {
    final name = request.url.queryParameters['name'];
    if (name == null || name.isEmpty) {
      return _jsonError(HttpStatus.badRequest, 'Missing name');
    }
    try {
      await _smbService.removeConnection(name);
      return _jsonOk({'success': true});
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '移除 SMB 失败: $e');
    }
  }

  Future<Response> _handleListSMB(Request request) async {
    final name = request.url.queryParameters['name']?.trim();
    final path = request.url.queryParameters['path']?.trim() ?? '/';
    if (name == null || name.isEmpty) {
      return _jsonError(HttpStatus.badRequest, 'Missing name');
    }

    final connection = _smbService.getConnection(name);
    if (connection == null) {
      return _jsonError(HttpStatus.notFound, 'SMB connection not found');
    }

    try {
      final files = await _smbService.listDirectory(connection, path);
      final entries = files
          .map((file) => {
                'name': file.name,
                'path': file.path,
                'isDirectory': file.isDirectory,
                'size': file.size,
                'isShare': file.isShare,
              })
          .toList();
      return _jsonOk({
        'success': true,
        'data': {
          'path': path,
          'entries': entries,
        },
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '读取SMB目录失败: $e');
    }
  }

  Future<Response> _handleTestSMB(Request request) async {
    final name = request.url.queryParameters['name']?.trim();
    if (name == null || name.isEmpty) {
      return _jsonError(HttpStatus.badRequest, 'Missing name');
    }

    final connection = _smbService.getConnection(name);
    if (connection == null) {
      return _jsonError(HttpStatus.notFound, 'SMB connection not found');
    }

    try {
      await _smbService.updateConnectionStatus(name);
      final updated = _smbService.getConnection(name);
      return _jsonOk({
        'success': true,
        'data': {'isConnected': updated?.isConnected ?? false},
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '测试 SMB 失败: $e');
    }
  }

  Future<Response> _handleScanSMB(Request request) async {
    Map<String, dynamic> payload = const {};
    try {
      final body = await request.readAsString();
      if (body.isNotEmpty) {
        payload = json.decode(body) as Map<String, dynamic>;
      }
    } catch (_) {
      return _jsonError(HttpStatus.badRequest, 'Invalid JSON payload');
    }

    final name = (payload['name'] ?? payload['connection'] ?? '').toString().trim();
    final folderPath =
        (payload['path'] ?? payload['folderPath'] ?? '/').toString().trim();
    if (name.isEmpty) {
      return _jsonError(HttpStatus.badRequest, 'Missing SMB connection name');
    }

    final connection = _smbService.getConnection(name);
    if (connection == null) {
      return _jsonError(HttpStatus.notFound, 'SMB connection not found');
    }

    try {
      await SMBProxyService.instance.initialize();
      final files = await _collectSmbVideoFiles(connection, folderPath);
      if (files.isEmpty) {
        return _jsonOk({
          'success': true,
          'data': {'total': 0, 'matched': 0, 'failed': 0},
        });
      }

      final candidates = files
          .map((file) => _RemoteScrapeCandidate(
                filePath: SMBProxyService.instance.buildStreamUrl(
                  connection,
                  file.path,
                ),
                fileName: file.name,
              ))
          .toList();
      final result = await _scrapeRemoteFiles(
        sourceLabel: 'SMB',
        candidates: candidates,
      );
      await ServiceProvider.watchHistoryProvider.refresh();
      return _jsonOk({
        'success': true,
        'data': {
          'total': result.total,
          'matched': result.matched,
          'failed': result.failed,
        },
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '刮削SMB文件夹失败: $e');
    }
  }

  int? _parseMatchId(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<List<WebDAVFile>> _collectWebDavVideoFiles(
    WebDAVConnection connection,
    String folderPath,
  ) async {
    final List<WebDAVFile> videoFiles = [];
    try {
      final files = await _webdavService.listDirectory(connection, folderPath);
      for (final file in files) {
        if (file.isDirectory) {
          final subFiles =
              await _collectWebDavVideoFiles(connection, file.path);
          videoFiles.addAll(subFiles);
        } else if (_webdavService.isVideoFile(file.name)) {
          videoFiles.add(file);
        }
      }
    } catch (e) {
      print('获取WebDAV视频文件失败: $e');
    }
    return videoFiles;
  }

  Future<List<SMBFileEntry>> _collectSmbVideoFiles(
    SMBConnection connection,
    String folderPath,
  ) async {
    final List<SMBFileEntry> videoFiles = [];
    try {
      final files = await _smbService.listDirectory(connection, folderPath);
      for (final file in files) {
        if (file.isDirectory) {
          final nested =
              await _collectSmbVideoFiles(connection, file.path);
          videoFiles.addAll(nested);
        } else if (_smbService.isVideoFile(file.name)) {
          videoFiles.add(file);
        }
      }
    } catch (e) {
      print('获取SMB视频文件失败: $e');
    }
    return videoFiles;
  }

  Future<_RemoteScrapeResult> _scrapeRemoteFiles({
    required String sourceLabel,
    required List<_RemoteScrapeCandidate> candidates,
  }) async {
    int matched = 0;
    int failed = 0;

    for (final candidate in candidates) {
      try {
        final videoInfo = await DandanplayService.getVideoInfo(
          candidate.filePath,
        );
        final matches = videoInfo['matches'];
        if (videoInfo['isMatched'] != true ||
            matches is! List ||
            matches.isEmpty ||
            matches.first is! Map) {
          failed++;
          continue;
        }

        final match = Map<String, dynamic>.from(matches.first as Map);
        final animeId = _parseMatchId(match['animeId']);
        final episodeId = _parseMatchId(match['episodeId']);
        if (animeId == null || episodeId == null) {
          failed++;
          continue;
        }

        final existingHistory =
            await WatchHistoryManager.getHistoryItem(candidate.filePath);
        final rawAnimeTitle = videoInfo['animeTitle'] ?? match['animeTitle'];
        final rawEpisodeTitle =
            videoInfo['episodeTitle'] ?? match['episodeTitle'];
        final rawHash = videoInfo['fileHash'] ?? videoInfo['hash'];
        final animeTitle = rawAnimeTitle?.toString();
        final episodeTitle = rawEpisodeTitle?.toString();
        final hashString = rawHash?.toString();
        final durationFromMatch = (videoInfo['duration'] is int)
            ? videoInfo['duration'] as int
            : (existingHistory?.duration ?? 0);
        final preserveProgress = existingHistory != null &&
            existingHistory.watchProgress > 0.01 &&
            !existingHistory.isFromScan;

        final historyItem = WatchHistoryItem(
          filePath: candidate.filePath,
          animeName: animeTitle?.isNotEmpty == true
              ? animeTitle!
              : (existingHistory?.animeName ??
                  p.basenameWithoutExtension(candidate.fileName)),
          episodeTitle: episodeTitle?.isNotEmpty == true
              ? episodeTitle
              : existingHistory?.episodeTitle,
          episodeId: episodeId,
          animeId: animeId,
          watchProgress: preserveProgress
              ? existingHistory!.watchProgress
              : (existingHistory?.watchProgress ?? 0.0),
          lastPosition: preserveProgress
              ? existingHistory!.lastPosition
              : (existingHistory?.lastPosition ?? 0),
          duration: durationFromMatch,
          lastWatchTime: DateTime.now(),
          thumbnailPath: existingHistory?.thumbnailPath,
          isFromScan: !preserveProgress,
          videoHash: hashString?.isNotEmpty == true
              ? hashString
              : existingHistory?.videoHash,
        );
        await WatchHistoryManager.addOrUpdateHistory(historyItem);
        matched++;
      } catch (e) {
        failed++;
        print('$sourceLabel 刮削失败: ${candidate.fileName} -> $e');
      }
    }

    return _RemoteScrapeResult(
      total: candidates.length,
      matched: matched,
      failed: failed,
    );
  }


  Future<Response> _handleAddFolder(Request request) async {
    Map<String, dynamic> payload = const {};
    try {
      final body = await request.readAsString();
      if (body.isNotEmpty) {
        payload = json.decode(body) as Map<String, dynamic>;
      }
    } catch (_) {
      return _jsonError(HttpStatus.badRequest, 'Invalid JSON payload');
    }

    final folderPath =
        (payload['path'] ?? payload['folderPath'] ?? payload['folder'] ?? '')
            .toString()
            .trim();
    if (folderPath.isEmpty) {
      return _jsonError(HttpStatus.badRequest, 'Missing folder path');
    }

    final bool scan = payload['scan'] == true;
    final bool skipPreviouslyMatchedUnwatched =
        payload['skipPreviouslyMatchedUnwatched'] == true;

    try {
      if (scan) {
        if (_scanService.isScanning) {
          return _jsonOk({
            'success': false,
            'message': '已有扫描任务在进行中，请稍后重试。',
          });
        }
        unawaited(_scanService.startDirectoryScan(
          folderPath,
          skipPreviouslyMatchedUnwatched: skipPreviouslyMatchedUnwatched,
        ));
      } else {
        await _scanService.addScannedFolder(folderPath);
      }

      final folders = await _buildFolderPayload(_scanService.scannedFolders);
      return _jsonOk({
        'success': true,
        'data': {
          'folders': folders,
          'scanStarted': scan,
        },
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '添加文件夹失败: $e');
    }
  }

  Future<Response> _handleRemoveFolder(Request request) async {
    final folderPath = request.url.queryParameters['path']?.trim();
    if (folderPath == null || folderPath.isEmpty) {
      return _jsonError(HttpStatus.badRequest, 'Missing folder path');
    }

    if (_scanService.isScanning) {
      return _jsonOk({
        'success': false,
        'message': '扫描进行中，无法移除文件夹。',
      });
    }

    try {
      await _scanService.removeScannedFolder(folderPath);
      final folders = await _buildFolderPayload(_scanService.scannedFolders);
      return _jsonOk({
        'success': true,
        'data': {'folders': folders},
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '移除文件夹失败: $e');
    }
  }

  Future<Response> _handleBrowse(Request request) async {
    final rawPath = request.url.queryParameters['path']?.trim();
    if (rawPath == null || rawPath.isEmpty) {
      return _jsonError(HttpStatus.badRequest, '缺少 path 参数');
    }

    final targetPath = p.normalize(rawPath);
    if (!_isAllowedPath(targetPath)) {
      return _jsonError(HttpStatus.forbidden, '路径不允许访问');
    }

    try {
      final directory = Directory(targetPath);
      if (!await directory.exists()) {
        return _jsonError(HttpStatus.notFound, '目录不存在');
      }

      final entries = <Map<String, dynamic>>[];
      await for (final entity in directory.list(recursive: false, followLinks: false)) {
        if (entity is Directory) {
          entries.add(await _buildEntryJson(entity, isDirectory: true));
          continue;
        }
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (!_allowedMediaExtensions.contains(ext)) {
            continue;
          }
          entries.add(await _buildEntryJson(entity, isDirectory: false));
        }
      }

      entries.sort((a, b) {
        final bool aDir = a['isDirectory'] == true;
        final bool bDir = b['isDirectory'] == true;
        if (aDir != bDir) {
          return aDir ? -1 : 1;
        }
        final aName = (a['name'] as String? ?? '').toLowerCase();
        final bName = (b['name'] as String? ?? '').toLowerCase();
        return aName.compareTo(bName);
      });

      return _jsonOk({
        'success': true,
        'data': {
          'path': targetPath,
          'entries': entries,
        },
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '读取目录失败: $e');
    }
  }

  Future<Response> _handleStream(Request request) async {
    return _handleStreamInternal(request, headOnly: false);
  }

  Future<Response> _handleStreamHead(Request request) async {
    return _handleStreamInternal(request, headOnly: true);
  }

  Future<Response> _handleStreamInternal(
    Request request, {
    required bool headOnly,
  }) async {
    final rawPath = request.url.queryParameters['path']?.trim();
    if (rawPath == null || rawPath.isEmpty) {
      return _jsonError(HttpStatus.badRequest, '缺少 path 参数');
    }

    final targetPath = p.normalize(rawPath);
    if (!_isAllowedPath(targetPath)) {
      return _jsonError(HttpStatus.forbidden, '路径不允许访问');
    }

    final ext = p.extension(targetPath).toLowerCase();
    if (!_allowedMediaExtensions.contains(ext)) {
      return _jsonError(HttpStatus.forbidden, '不支持的文件类型');
    }

    try {
      final file = File(targetPath);
      if (!await file.exists()) {
        return Response.notFound('File not found');
      }

      final totalLength = await file.length();
      final contentType = _determineContentType(targetPath);
      final contentDisposition = _buildContentDispositionHeader(p.basename(targetPath));
      final rangeHeader = request.headers['range'];

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
        if (match != null) {
          final startStr = match.group(1);
          final endStr = match.group(2);
          final start = startStr != null && startStr.isNotEmpty ? int.parse(startStr) : 0;
          final end = endStr != null && endStr.isNotEmpty ? int.parse(endStr) : totalLength - 1;
          if (start >= totalLength) {
            return Response(
              HttpStatus.requestedRangeNotSatisfiable,
              headers: {
                'Content-Range': 'bytes */$totalLength',
                'Content-Disposition': contentDisposition,
              },
            );
          }
          final adjustedEnd = end >= totalLength ? totalLength - 1 : end;
          final chunkSize = adjustedEnd - start + 1;
          final stream = headOnly ? null : file.openRead(start, adjustedEnd + 1);
          return Response(
            HttpStatus.partialContent,
            body: stream,
            headers: {
              'Content-Type': contentType,
              'Content-Length': '$chunkSize',
              'Accept-Ranges': 'bytes',
              'Content-Range': 'bytes $start-$adjustedEnd/$totalLength',
              'Cache-Control': 'no-cache',
              'Content-Disposition': contentDisposition,
            },
          );
        }
      }

      final stream = headOnly ? null : file.openRead();
      return Response.ok(
        stream,
        headers: {
          'Content-Type': contentType,
          'Content-Length': '$totalLength',
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'no-cache',
          'Content-Disposition': contentDisposition,
        },
      );
    } catch (e) {
      return Response.internalServerError(body: '文件读取失败: $e');
    }
  }

  Future<Response> _handleScanStatus(Request request) async {
    try {
      return _jsonOk({
        'success': true,
        'data': {
          'isScanning': _scanService.isScanning,
          'progress': _scanService.scanProgress,
          'message': _scanService.scanMessage,
          'totalFilesFound': _scanService.totalFilesFound,
          'scannedFolders': _scanService.scannedFolders,
        },
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '获取扫描状态失败: $e');
    }
  }

  Future<Response> _handleRescanAll(Request request) async {
    Map<String, dynamic> payload = const {};
    try {
      final body = await request.readAsString();
      if (body.isNotEmpty) {
        payload = json.decode(body) as Map<String, dynamic>;
      }
    } catch (_) {
      return _jsonError(HttpStatus.badRequest, 'Invalid JSON payload');
    }

    final bool skipPreviouslyMatchedUnwatched =
        payload['skipPreviouslyMatchedUnwatched'] != false;

    if (_scanService.isScanning) {
      return _jsonOk({
        'success': false,
        'message': '已有扫描任务在进行中，请稍后重试。',
      });
    }

    try {
      unawaited(_scanService.rescanAllFolders(
        skipPreviouslyMatchedUnwatched: skipPreviouslyMatchedUnwatched,
      ));
      return _jsonOk({
        'success': true,
        'data': {'scanStarted': true},
      });
    } catch (e) {
      return _jsonError(HttpStatus.internalServerError, '启动刷新失败: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _buildFolderPayload(
    List<String> folders,
  ) async {
    final List<Map<String, dynamic>> payload = [];
    for (final folder in folders) {
      bool exists = false;
      try {
        exists = await Directory(folder).exists();
      } catch (_) {
        exists = false;
      }
      payload.add({
        'path': folder,
        'name': p.basename(folder),
        'exists': exists,
      });
    }
    return payload;
  }

  Response _jsonOk(Map<String, dynamic> body) {
    return Response.ok(
      json.encode(body),
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Response _jsonError(int status, String message) {
    return Response(
      status,
      body: json.encode({'success': false, 'message': message}),
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  bool _isAllowedPath(String targetPath) {
    for (final root in _scanService.scannedFolders) {
      final rootNormalized = p.normalize(root);
      for (final candidateRoot in _pathCandidates(rootNormalized)) {
        for (final candidateTarget in _pathCandidates(targetPath)) {
          if (p.equals(candidateTarget, candidateRoot) ||
              p.isWithin(candidateRoot, candidateTarget)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  List<String> _pathCandidates(String value) {
    final normalized = p.normalize(value);
    final candidates = <String>{normalized};

    // iOS 路径在 /private 前缀上可能出现别名差异（/var/... 与 /private/var/...）。
    if (Platform.isIOS) {
      if (normalized.startsWith('/private')) {
        candidates.add(normalized.replaceFirst('/private', ''));
      } else if (normalized.startsWith('/')) {
        candidates.add('/private$normalized');
      }
    }

    return candidates.toList(growable: false);
  }

  Future<Map<String, dynamic>> _buildEntryJson(
    FileSystemEntity entity, {
    required bool isDirectory,
  }) async {
    String name = p.basename(entity.path);
    int? size;
    DateTime? modifiedTime;
    try {
      final stat = await entity.stat();
      modifiedTime = stat.modified;
      if (!isDirectory) {
        size = stat.size;
      }
    } catch (_) {
      size = null;
      modifiedTime = null;
    }

    String? animeName;
    String? episodeTitle;
    int? animeId;
    int? episodeId;
    bool? isFromScan;
    if (!isDirectory) {
      try {
        final history = await WatchHistoryManager.getHistoryItem(entity.path);
        if (history != null) {
          final candidateAnimeId = history.animeId;
          final candidateEpisodeId = history.episodeId;
          if (candidateAnimeId != null &&
              candidateAnimeId > 0 &&
              candidateEpisodeId != null &&
              candidateEpisodeId > 0) {
            animeName = history.animeName;
            episodeTitle = history.episodeTitle;
            animeId = candidateAnimeId;
            episodeId = candidateEpisodeId;
            isFromScan = history.isFromScan;
          }
        }
      } catch (_) {
        // ignore
      }
    }

    return {
      'path': entity.path,
      'name': name,
      'isDirectory': isDirectory,
      'size': size,
      'modifiedTime': modifiedTime?.toIso8601String(),
      'animeName': animeName,
      'episodeTitle': episodeTitle,
      'animeId': animeId,
      'episodeId': episodeId,
      'isFromScan': isFromScan,
    };
  }

  String _determineContentType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.mp4':
      case '.m4v':
        return 'video/mp4';
      case '.mkv':
        return 'video/x-matroska';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      case '.flv':
        return 'video/x-flv';
      case '.ts':
      case '.mpeg':
      case '.mpg':
        return 'video/mpeg';
      case '.webm':
        return 'video/webm';
      case '.mp3':
        return 'audio/mpeg';
      case '.flac':
        return 'audio/flac';
      case '.aac':
        return 'audio/aac';
      case '.wav':
        return 'audio/wav';
      case '.ass':
      case '.ssa':
        return 'text/plain';
      case '.srt':
        return 'application/x-subrip';
      default:
        return 'application/octet-stream';
    }
  }

  String _buildContentDispositionHeader(String fileName) {
    String sanitizeAsciiFallback(String value) {
      if (value.isEmpty) return 'file';
      final buffer = StringBuffer();
      for (final codeUnit in value.codeUnits) {
        final bool isAsciiPrintable = codeUnit >= 0x20 && codeUnit <= 0x7E;
        final bool isForbidden = codeUnit == 0x22 /* " */ || codeUnit == 0x5C /* \\ */;
        buffer.writeCharCode(
          isAsciiPrintable && !isForbidden ? codeUnit : 0x5F /* _ */,
        );
      }
      final sanitized = buffer.toString().trim();
      return sanitized.isEmpty ? 'file' : sanitized;
    }

    final fallbackName = sanitizeAsciiFallback(fileName);
    final encodedName = Uri.encodeComponent(fileName);
    return 'inline; filename="$fallbackName"; filename*=UTF-8\'\'$encodedName';
  }
}
