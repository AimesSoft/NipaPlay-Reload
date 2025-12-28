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

class RemoteSubtitleService {
  RemoteSubtitleService._();

  static final RemoteSubtitleService instance = RemoteSubtitleService._();

  bool isPotentialRemoteVideoPath(String videoPath) {
    if (videoPath.isEmpty) return false;
    if (MediaSourceUtils.isSmbPath(videoPath)) return true;
    final uri = Uri.tryParse(videoPath);
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  Future<List<RemoteSubtitleCandidate>> listCandidatesForVideo(
      String videoPath) async {
    if (kIsWeb || videoPath.isEmpty) return const [];

    if (MediaSourceUtils.isSmbPath(videoPath)) {
      return _listSmbCandidates(videoPath);
    }

    final uri = Uri.tryParse(videoPath);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return _listWebDavCandidates(videoPath);
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
    throw UnsupportedError('不支持的远程字幕来源');
  }

  Future<List<RemoteSubtitleCandidate>> _listWebDavCandidates(
      String videoUrl) async {
    await WebDAVService.instance.initialize();

    final resolved = WebDAVService.instance.resolveFileUrl(videoUrl);
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
