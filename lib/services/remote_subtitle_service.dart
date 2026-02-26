import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:smb_connect/smb_connect.dart';

import 'package:nipaplay/services/smb2_native_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/storage_service.dart';

const Set<String> _subtitleExtensions = {
  '.ass',
  '.ssa',
  '.srt',
  '.sub',
  '.sup',
};

sealed class RemoteSubtitleCandidate {
  const RemoteSubtitleCandidate();

  String get name;
  String get extension;
  String get sourceLabel;
}

class WebDavRemoteSubtitleCandidate extends RemoteSubtitleCandidate {
  final WebDAVConnection connection;
  final String remotePath;

  @override
  final String name;

  @override
  final String extension;

  const WebDavRemoteSubtitleCandidate({
    required this.connection,
    required this.remotePath,
    required this.name,
    required this.extension,
  });

  @override
  String get sourceLabel => 'WebDAV: ${connection.name}';
}

class SmbRemoteSubtitleCandidate extends RemoteSubtitleCandidate {
  final SMBConnection connection;
  final String smbPath;

  @override
  final String name;

  @override
  final String extension;

  const SmbRemoteSubtitleCandidate({
    required this.connection,
    required this.smbPath,
    required this.name,
    required this.extension,
  });

  @override
  String get sourceLabel => 'SMB: ${connection.name}';
}

class DandanplayRemoteSubtitleCandidate extends RemoteSubtitleCandidate {
  final String entryId;
  final String fileName;

  @override
  final String name;

  @override
  final String extension;

  const DandanplayRemoteSubtitleCandidate({
    required this.entryId,
    required this.fileName,
    required this.name,
    required this.extension,
  });

  @override
  String get sourceLabel => '弹弹play 远程媒体库';
}

class RemoteSubtitleService {
  RemoteSubtitleService._();

  static final RemoteSubtitleService instance = RemoteSubtitleService._();

  bool isPotentialRemoteVideoPath(String videoPath) {
    if (videoPath.isEmpty) return false;
    final resolvedPath = _resolveManagedStreamPath(videoPath);
    if (resolvedPath.isEmpty) return false;
    if (MediaSourceUtils.isSmbPath(resolvedPath)) return true;
    final uri = Uri.tryParse(resolvedPath);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'smb') return true;
    if (scheme == 'webdav' ||
        scheme == 'dav' ||
        scheme == 'webdavs' ||
        scheme == 'davs') {
      return true;
    }
    return scheme == 'http' || scheme == 'https';
  }

  String resolveVideoPathForMatching(String videoPath) {
    return _resolveManagedStreamPath(videoPath);
  }

  Future<List<RemoteSubtitleCandidate>> listCandidatesForVideo(
      String videoPath) async {
    if (kIsWeb || videoPath.isEmpty) return const [];

    final resolvedPath = _resolveManagedStreamPath(videoPath);

    if (DandanplayRemoteService.instance.isDandanplayStreamUrl(resolvedPath)) {
      return _listDandanplayCandidates(resolvedPath);
    }

    if (MediaSourceUtils.isSmbPath(resolvedPath)) {
      final uri = Uri.tryParse(resolvedPath);
      if (uri != null && uri.scheme.toLowerCase() == 'smb') {
        return _listSmbCandidatesFromUri(uri);
      }
      return _listSmbCandidates(resolvedPath);
    }

    final uri = Uri.tryParse(resolvedPath);
    if (uri != null) {
      final scheme = uri.scheme.toLowerCase();
      if (scheme == 'webdav' ||
          scheme == 'dav' ||
          scheme == 'webdavs' ||
          scheme == 'davs') {
        return _listWebDavCandidates(_normalizeWebDavUri(uri));
      }
      if (scheme == 'http' || scheme == 'https') {
        return _listWebDavCandidates(resolvedPath);
      }
    }

    return const [];
  }

  Future<String> ensureSubtitleCached(RemoteSubtitleCandidate candidate,
      {bool forceRefresh = false}) async {
    if (kIsWeb) {
      throw UnsupportedError('Web 平台不支持缓存远程字幕');
    }

    final baseDir = await StorageService.getAppStorageDirectory();
    final cacheDir = Directory(p.join(baseDir.path, 'remote_subtitles'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final extension =
        candidate.extension.isNotEmpty ? candidate.extension : '.srt';
    final cacheKey = switch (candidate) {
      WebDavRemoteSubtitleCandidate() =>
        'webdav:${candidate.connection.name}:${candidate.remotePath}',
      SmbRemoteSubtitleCandidate() =>
        'smb:${candidate.connection.name}:${candidate.smbPath}',
      DandanplayRemoteSubtitleCandidate() =>
        'dandanplay:${candidate.entryId}:${candidate.fileName}',
    };

    final hash = sha1.convert(utf8.encode(cacheKey)).toString();
    final target = File(p.join(cacheDir.path, '$hash$extension'));

    if (!forceRefresh && await target.exists()) {
      final size = await target.length();
      if (size > 0) {
        return target.path;
      }
    }

    final tmp = File('${target.path}.downloading');
    if (await tmp.exists()) {
      await tmp.delete();
    }

    try {
      await _downloadToFile(candidate, tmp);
      if (await target.exists()) {
        await target.delete();
      }
      await tmp.rename(target.path);
      return target.path;
    } catch (e) {
      if (await tmp.exists()) {
        await tmp.delete();
      }
      rethrow;
    }
  }

  Future<void> _downloadToFile(
      RemoteSubtitleCandidate candidate, File destination) async {
    if (candidate is WebDavRemoteSubtitleCandidate) {
      await _downloadWebDavSubtitle(candidate, destination);
      return;
    }
    if (candidate is SmbRemoteSubtitleCandidate) {
      await _downloadSmbSubtitle(candidate, destination);
      return;
    }
    if (candidate is DandanplayRemoteSubtitleCandidate) {
      await _downloadDandanplaySubtitle(candidate, destination);
      return;
    }
    throw UnsupportedError('不支持的远程字幕来源');
  }

  Future<List<RemoteSubtitleCandidate>> _listDandanplayCandidates(
      String videoUrl) async {
    final entryId =
        await DandanplayRemoteService.instance.resolveEntryIdForStreamUrl(
      videoUrl,
    );
    if (entryId == null || entryId.isEmpty) return const [];

    final subtitles =
        await DandanplayRemoteService.instance.getSubtitleList(entryId);

    final candidates = <RemoteSubtitleCandidate>[];
    for (final item in subtitles) {
      final name = item.fileName.trim();
      if (name.isEmpty) continue;
      final ext = p.extension(name).toLowerCase();
      if (!_subtitleExtensions.contains(ext)) continue;
      candidates.add(
        DandanplayRemoteSubtitleCandidate(
          entryId: entryId,
          fileName: name,
          name: name,
          extension: ext,
        ),
      );
    }

    candidates.sort((a, b) => a.name.compareTo(b.name));
    return candidates;
  }

  Future<List<RemoteSubtitleCandidate>> _listWebDavCandidates(
      String videoUrl) async {
    await WebDAVService.instance.initialize();

    WebDAVResolvedFile? resolved =
        WebDAVService.instance.resolveFileUrl(videoUrl);
    resolved ??= _tryResolveWebDavFromUrl(videoUrl);
    if (resolved == null) return const [];

    final directory = _posixDirname(resolved.relativePath);
    final entries =
        await WebDAVService.instance.listDirectoryAll(resolved.connection, directory);

    final candidates = <RemoteSubtitleCandidate>[];
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final ext = p.extension(entry.name).toLowerCase();
      if (!_subtitleExtensions.contains(ext)) continue;
      candidates.add(
        WebDavRemoteSubtitleCandidate(
          connection: resolved.connection,
          remotePath: entry.path,
          name: entry.name,
          extension: ext,
        ),
      );
    }

    candidates.sort((a, b) => a.name.compareTo(b.name));
    return candidates;
  }

  Future<List<RemoteSubtitleCandidate>> _listSmbCandidatesFromUri(
      Uri smbUri) async {
    await SMBService.instance.initialize();

    final connection = _resolveSmbConnectionFromUri(smbUri);
    if (connection == null) return const [];

    final smbPath = _normalizeSmbPathFromUri(smbUri);
    if (smbPath.isEmpty || smbPath == '/') return const [];

    final directory = _posixDirname(smbPath);
    final entries =
        await SMBService.instance.listDirectoryAll(connection, directory);

    final candidates = <RemoteSubtitleCandidate>[];
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final ext = p.extension(entry.name).toLowerCase();
      if (!_subtitleExtensions.contains(ext)) continue;
      candidates.add(
        SmbRemoteSubtitleCandidate(
          connection: connection,
          smbPath: entry.path,
          name: entry.name,
          extension: ext,
        ),
      );
    }

    candidates.sort((a, b) => a.name.compareTo(b.name));
    return candidates;
  }

  WebDAVResolvedFile? _tryResolveWebDavFromUrl(String videoUrl) {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    final lowerPath = uri.path.toLowerCase();
    final hasDavHint = uri.userInfo.isNotEmpty ||
        lowerPath.contains('/webdav') ||
        lowerPath.contains('/dav');
    if (!hasDavHint) return null;

    WebDAVConnection? matched;
    for (final conn in WebDAVService.instance.connections) {
      final baseUri = Uri.tryParse(conn.url.trim());
      if (baseUri == null || baseUri.scheme.isEmpty || baseUri.host.isEmpty) {
        continue;
      }
      if (baseUri.scheme != uri.scheme) continue;
      if (baseUri.host != uri.host) continue;
      if (_effectivePort(baseUri) != _effectivePort(uri)) continue;
      matched = conn;
      break;
    }

    String username = '';
    String password = '';
    if (uri.userInfo.isNotEmpty) {
      final parts = uri.userInfo.split(':');
      username = Uri.decodeComponent(parts.first);
      if (parts.length > 1) {
        password = Uri.decodeComponent(parts.sublist(1).join(':'));
      }
    }

    final rootUrl = uri
        .replace(userInfo: '', path: '/', query: '', fragment: '')
        .toString();
    final connection = matched != null
        ? matched.copyWith(url: rootUrl)
        : WebDAVConnection(
            name: 'auto',
            url: rootUrl,
            username: username,
            password: password,
            isConnected: true,
          );

    final relativePath = _normalizeWebDavPath(uri.path, isDirectory: false);
    return WebDAVResolvedFile(
      connection: connection,
      relativePath: relativePath,
    );
  }

  String _normalizeWebDavPath(String path, {required bool isDirectory}) {
    var normalized = path.trim();
    if (normalized.isEmpty) {
      normalized = '/';
    }
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');
    if (normalized.length == 1) {
      return normalized;
    }
    if (isDirectory) {
      return normalized.endsWith('/') ? normalized : '$normalized/';
    }
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    if (uri.scheme == 'https') return 443;
    if (uri.scheme == 'http') return 80;
    return 0;
  }

  String _normalizeWebDavUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'webdavs' || scheme == 'davs') {
      return uri.replace(scheme: 'https').toString();
    }
    if (scheme == 'webdav' || scheme == 'dav') {
      final resolvedScheme =
          uri.hasPort && uri.port == 443 ? 'https' : 'http';
      return uri.replace(scheme: resolvedScheme).toString();
    }
    return uri.toString();
  }

  String _resolveManagedStreamPath(String videoPath) {
    final uri = Uri.tryParse(videoPath);
    if (uri == null) return videoPath;
    final lowerPath = uri.path.toLowerCase();
    if (lowerPath.contains('/api/media/local/manage/stream') ||
        lowerPath.contains('/api/media/local/share/stream')) {
      final pathParam = uri.queryParameters['path'];
      if (pathParam != null && pathParam.trim().isNotEmpty) {
        return pathParam.trim();
      }
    }
    return videoPath;
  }

  SMBConnection? _resolveSmbConnectionFromUri(Uri smbUri) {
    final host = smbUri.host.trim();
    if (host.isEmpty) return null;
    final port = smbUri.hasPort ? smbUri.port : 445;

    String username = '';
    String password = '';
    if (smbUri.userInfo.isNotEmpty) {
      final parts = smbUri.userInfo.split(':');
      username = Uri.decodeComponent(parts.first);
      if (parts.length > 1) {
        password = Uri.decodeComponent(parts.sublist(1).join(':'));
      }
    }

    SMBConnection? matched;
    for (final conn in SMBService.instance.connections) {
      if (conn.host.trim().toLowerCase() != host.toLowerCase()) {
        continue;
      }
      if (conn.port != port) continue;
      if (username.isNotEmpty && conn.username != username) continue;
      matched = conn;
      break;
    }

    if (matched != null) {
      if (username.isNotEmpty &&
          (matched.username != username || matched.password != password)) {
        return matched.copyWith(username: username, password: password);
      }
      return matched;
    }

    final displayHost = port == 445 ? host : '$host:$port';
    return SMBConnection(
      name: 'auto@$displayHost',
      host: host,
      port: port,
      username: username,
      password: password,
      domain: '',
      isConnected: true,
    );
  }

  String _normalizeSmbPathFromUri(Uri smbUri) {
    var path = smbUri.path.trim();
    if (path.isEmpty) return '/';
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    return path.replaceAll(RegExp(r'/+'), '/');
  }

  Future<List<RemoteSubtitleCandidate>> _listSmbCandidates(String videoUrl) async {
    final parsed = _parseSmbProxyStreamUrl(videoUrl);
    if (parsed == null) return const [];

    await SMBService.instance.initialize();
    final connection = SMBService.instance.getConnection(parsed.connName);
    if (connection == null) return const [];

    final directory = _posixDirname(parsed.smbPath);
    final entries = await SMBService.instance.listDirectoryAll(connection, directory);

    final candidates = <RemoteSubtitleCandidate>[];
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final ext = p.extension(entry.name).toLowerCase();
      if (!_subtitleExtensions.contains(ext)) continue;
      candidates.add(
        SmbRemoteSubtitleCandidate(
          connection: connection,
          smbPath: entry.path,
          name: entry.name,
          extension: ext,
        ),
      );
    }

    candidates.sort((a, b) => a.name.compareTo(b.name));
    return candidates;
  }

  Future<void> _downloadWebDavSubtitle(
      WebDavRemoteSubtitleCandidate candidate, File destination) async {
    final rawUrl =
        WebDAVService.instance.getFileUrl(candidate.connection, candidate.remotePath);
    final rawUri = Uri.parse(rawUrl);
    final sanitized = rawUri.replace(userInfo: '');

    final headers = <String, String>{
      'user-agent': 'NipaPlay',
      'accept': '*/*',
    };

    final hasAuth = candidate.connection.username.isNotEmpty ||
        candidate.connection.password.isNotEmpty;
    if (hasAuth) {
      final credentials =
          '${candidate.connection.username}:${candidate.connection.password}';
      headers['authorization'] =
          'Basic ${base64Encode(utf8.encode(credentials))}';
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: 15000),
        receiveTimeout: const Duration(milliseconds: 45000),
        sendTimeout: const Duration(milliseconds: 15000),
        followRedirects: true,
        responseType: ResponseType.bytes,
        headers: headers,
      ),
    );

    final resp = await dio.get<List<int>>(sanitized.toString());
    final status = resp.statusCode ?? 0;
    if (status != 200 && status != 206) {
      throw Exception('WebDAV 下载失败 (HTTP $status)');
    }
    final data = resp.data;
    if (data == null || data.isEmpty) {
      throw Exception('WebDAV 返回空内容');
    }
    await destination.writeAsBytes(data, flush: true);
  }

  Future<void> _downloadSmbSubtitle(
      SmbRemoteSubtitleCandidate candidate, File destination) async {
    if (Smb2NativeService.instance.isSupported) {
      final stat = await Smb2NativeService.instance.stat(
        candidate.connection,
        candidate.smbPath,
      );
      if (stat.isDirectory) {
        throw Exception('SMB 路径是目录，无法作为字幕加载');
      }
      final stream = Smb2NativeService.instance.openReadStream(
        candidate.connection,
        candidate.smbPath,
        start: 0,
        endExclusive: stat.size,
      );
      await _writeStreamToFile(stream, destination);
      return;
    }

    SmbConnect? client;
    try {
      client = await SmbConnect.connectAuth(
        host: candidate.connection.host,
        username: candidate.connection.username,
        password: candidate.connection.password,
        domain: candidate.connection.domain,
        debugPrint: false,
      );

      final smbFile = await client.file(candidate.smbPath);
      if (!smbFile.isExists) {
        throw Exception('SMB 字幕文件不存在');
      }
      if (smbFile.isDirectory()) {
        throw Exception('SMB 路径是目录，无法作为字幕加载');
      }

      final totalLength = smbFile.size;
      final stream = await client.openRead(smbFile, 0, totalLength);
      await _writeStreamToFile(stream, destination);
    } finally {
      await client?.close();
    }
  }

  Future<void> _downloadDandanplaySubtitle(
      DandanplayRemoteSubtitleCandidate candidate, File destination) async {
    final data = await DandanplayRemoteService.instance.downloadSubtitleFileBytes(
      candidate.entryId,
      candidate.fileName,
    );
    if (data.isEmpty) {
      throw Exception('弹弹play 返回空字幕内容');
    }
    await destination.writeAsBytes(data, flush: true);
  }

  Future<void> _writeStreamToFile(
    Stream<List<int>> stream,
    File destination,
  ) async {
    final sink = destination.openWrite();
    try {
      await sink.addStream(stream);
    } finally {
      await sink.close();
    }
  }

  String _posixDirname(String filePath) {
    final normalized = filePath.trim().isEmpty ? '/' : filePath.trim();
    final dir = p.posix.dirname(normalized);
    if (dir == '.' || dir.isEmpty) return '/';
    return dir.endsWith('/') ? dir : '$dir/';
  }

  _SmbProxyStreamUrl? _parseSmbProxyStreamUrl(String filePath) {
    final uri = Uri.tryParse(filePath);
    if (uri == null) return null;
    if (uri.path != '/smb/stream') return null;

    final connName = uri.queryParameters['conn']?.trim();
    final smbPath = uri.queryParameters['path']?.trim();
    if (connName == null || connName.isEmpty || smbPath == null || smbPath.isEmpty) {
      return null;
    }
    return _SmbProxyStreamUrl(connName: connName, smbPath: smbPath);
  }
}

class _SmbProxyStreamUrl {
  final String connName;
  final String smbPath;

  const _SmbProxyStreamUrl({
    required this.connName,
    required this.smbPath,
  });
}
