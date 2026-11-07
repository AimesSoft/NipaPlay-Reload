import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/media_path_name.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/media_identity_resolver.dart';
import 'package:nipaplay/utils/webdav_file_sorter.dart';

/// Next's file-source episode context. Only file services participate.
abstract final class SourceDetails {
  static Future<PlaybackDetailContext> resolve(PlayableItem item) async {
    if (item.detailContext case final context?) {
      if (!const {
        PlaybackSourceKind.localFile,
        PlaybackSourceKind.localLibrary,
        PlaybackSourceKind.webDav,
        PlaybackSourceKind.smb,
        PlaybackSourceKind.networkStream
      }.contains(context.sourceKind)) {
        throw const Failure(
            FailureCode.invalidInput, 'Unsupported source context.');
      }
      return context;
    }
    final path = item.videoPath;
    final parsed = Uri.tryParse(path);
    final smbProxy =
        const {'localhost', '127.0.0.1', '::1'}.contains(parsed?.host) &&
            parsed?.path == '/smb/stream' &&
            parsed!.queryParameters.containsKey('conn');
    if (MediaSourceUtils.isNewSmbPath(path) || smbProxy) {
      return _resolveSmb(item);
    }
    if (MediaSourceUtils.isWebDavPath(path)) return _resolveWebDav(item);
    final scheme = Uri.tryParse(path)?.scheme ?? '';
    if (scheme.isEmpty ||
        scheme == 'file' ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      return _resolveLocal(item);
    }
    return _singleItemContext(item,
        kind: PlaybackSourceKind.networkStream, sourceLabel: '网络媒体');
  }

  static const List<String> _videoExtensions = <String>[
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.flv',
    '.webm',
    '.m4v',
    '.3gp',
    '.ts',
    '.m2ts',
  ];

  static PlaybackDetailContext _resolveLocal(PlayableItem item) {
    final animeId = item.animeId ?? item.historyItem?.animeId;
    final kind = animeId != null && animeId > 0
        ? PlaybackSourceKind.localLibrary
        : PlaybackSourceKind.localFile;
    return PlaybackDetailContext(
      sourceKind: kind,
      sourceLabel: kind == PlaybackSourceKind.localLibrary ? '本地媒体库' : '本地文件',
      sourceKey: _sourceKey(item.videoPath, kind),
      title: _resolvedTitle(item),
      subtitle: item.subtitle ?? item.historyItem?.episodeTitle,
      imageUrl: item.historyItem?.thumbnailPath,
      animeId: animeId,
      isIdentified: animeId != null && animeId > 0,
      episodeLoader: () => _loadLocalEpisodes(item),
    );
  }

  static Future<PlaybackDetailContext> _resolveWebDav(
    PlayableItem item,
  ) async {
    await WebDAVService.instance.initialize();
    final path = item.videoPath;

    final resolved = WebDAVService.instance.resolveMediaPath(path);
    if (resolved == null) throw Exception('无法识别 WebDAV 连接: $path');

    final animeId = item.animeId ?? item.historyItem?.animeId;
    final resolvedTitle = _resolvedTitle(item);
    final resolvedSubtitle = item.subtitle ?? item.historyItem?.episodeTitle;

    return PlaybackDetailContext(
      sourceKind: PlaybackSourceKind.webDav,
      sourceLabel: resolved.connection.name,
      sourceKey:
          'webdav:${resolved.connection.id}:${p.posix.dirname(resolved.relativePath)}',
      title: resolvedTitle,
      subtitle: resolvedSubtitle,
      imageUrl: item.historyItem?.thumbnailPath,
      animeId: animeId,
      isIdentified: animeId != null && animeId > 0,
      episodeLoader: () => _loadWebDavEpisodes(resolved),
    );
  }

  static Future<List<PlaybackDetailEpisode>> _loadWebDavEpisodes(
    WebDAVResolvedFile resolved,
  ) async {
    final entries = await WebDAVService.instance.listDirectory(
      resolved.connection,
      _webDavParentDirectory(resolved),
    );
    final videos = entries
        .where((entry) =>
            !entry.isDirectory &&
            WebDAVService.instance.isVideoFile(entry.name))
        .toList()
      ..sort((a, b) => WebDAVFileSorter.playlistCompare(a.name, b.name));

    return videos.map((entry) {
      // 服务端 href 是不透明定位符：持久化地址和身份都保留原始编码。
      // 解码只用于 entry.name 的 UI 展示，不能参与媒体身份判断。
      final mediaPath = MediaSourceUtils.buildWebDavPath(
        resolved.connection.id,
        entry.path,
      );
      // getFileUrl 用于实际 HTTP 请求，保留服务器原始编码。
      final url = WebDAVService.instance.getFileUrl(
        resolved.connection,
        entry.path,
      );
      final title = p.basenameWithoutExtension(entry.name);
      final history = WatchHistoryItem(
        filePath: mediaPath,
        animeName: title,
        episodeTitle: entry.name,
        watchProgress: 0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
        mediaKey: MediaIdentityResolver.forPath(mediaPath),
      );
      return PlaybackDetailEpisode(
        id: entry.path,
        videoPath: mediaPath,
        title: title,
        subtitle: resolved.connection.name,
        historyItem: history,
        actualPlayUrl: url,
        mediaKey: history.mediaKey,
      );
    }).toList();
  }

  static String _webDavParentDirectory(WebDAVResolvedFile resolved) {
    return _normalizeRemoteDirectoryPath(
        p.posix.dirname(resolved.relativePath));
  }

  static Future<PlaybackDetailContext> _resolveSmb(PlayableItem item) async {
    final path = item.videoPath;
    String connectionName;
    String smbPath;

    if (MediaSourceUtils.isNewSmbPath(path)) {
      // 新格式: smb://connectionName/path
      final parsed = MediaSourceUtils.parseSmbPath(path);
      if (parsed == null) throw Exception('SMB 地址格式无效');
      connectionName = parsed.connectionName;
      smbPath = parsed.relativePath;
    } else {
      // 旧格式: http://127.0.0.1:33221/smb/stream?conn=...&path=...
      final uri = Uri.parse(path);
      connectionName = uri.queryParameters['conn']?.trim() ?? '';
      smbPath = uri.queryParameters['path']?.trim() ?? '';
      if (connectionName.isEmpty || smbPath.isEmpty) {
        throw Exception('SMB 地址缺少必要参数');
      }
    }

    await SMBService.instance.initialize();
    await SMBProxyService.instance.initialize();
    final connection = _findSmbConnection(connectionName);
    if (connection == null) throw Exception('找不到 SMB 连接：$connectionName');
    final animeId = item.animeId ?? item.historyItem?.animeId;

    return PlaybackDetailContext(
      sourceKind: PlaybackSourceKind.smb,
      sourceLabel: connection.name,
      sourceKey: 'smb:${connection.id}:${_smbParent(smbPath)}',
      title: _resolvedTitle(item),
      subtitle: item.subtitle ?? item.historyItem?.episodeTitle,
      imageUrl: item.historyItem?.thumbnailPath,
      animeId: animeId,
      isIdentified: animeId != null && animeId > 0,
      episodeLoader: () => _loadSmbEpisodes(connection, smbPath),
    );
  }

  static Future<List<PlaybackDetailEpisode>> _loadSmbEpisodes(
    SMBConnection connection,
    String currentPath,
  ) async {
    final entries = await SMBService.instance.listDirectory(
      connection,
      _smbParent(currentPath),
    );
    final videos = entries
        .where((entry) =>
            !entry.isDirectory && SMBService.instance.isVideoFile(entry.name))
        .toList()
      ..sort((a, b) => WebDAVFileSorter.playlistCompare(a.name, b.name));

    return videos.map((entry) {
      final mediaPath =
          MediaSourceUtils.buildSmbPath(connection.id, entry.path);
      final url =
          SMBProxyService.instance.buildStreamUrl(connection, entry.path);
      final title = p.basenameWithoutExtension(entry.name);
      final history = WatchHistoryItem(
        filePath: mediaPath,
        animeName: title,
        episodeTitle: entry.name,
        watchProgress: 0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
        mediaKey: MediaIdentityResolver.forPath(mediaPath),
      );
      return PlaybackDetailEpisode(
        id: entry.path,
        videoPath: mediaPath,
        title: title,
        subtitle: connection.name,
        historyItem: history,
        actualPlayUrl: url,
        mediaKey: history.mediaKey,
      );
    }).toList();
  }

  static Future<List<PlaybackDetailEpisode>> _loadLocalEpisodes(
    PlayableItem current,
  ) =>
      compute(
          _readLocalEpisodes,
          PlayableItem(
              videoPath: current.videoPath.startsWith('file:')
                  ? Uri.parse(current.videoPath)
                      .toFilePath(windows: Platform.isWindows)
                  : current.videoPath,
              title: current.title,
              subtitle: current.subtitle,
              animeId: current.animeId,
              episodeId: current.episodeId,
              historyItem: current.historyItem));

  static Future<List<PlaybackDetailEpisode>> _readLocalEpisodes(
    PlayableItem current,
  ) async {
    if (kIsWeb) return <PlaybackDetailEpisode>[_episodeFromItem(current)];
    final directory = File(current.videoPath).parent;
    if (!await directory.exists()) {
      return <PlaybackDetailEpisode>[_episodeFromItem(current)];
    }
    final files = (await directory
            .list()
            .where((entry) => entry is File)
            .cast<File>()
            .toList())
        .where((file) => _videoExtensions.any(
              (extension) => file.path.toLowerCase().endsWith(extension),
            ))
        .toList()
      ..sort((a, b) => WebDAVFileSorter.playlistCompare(
            p.basename(a.path),
            p.basename(b.path),
          ));
    return files.map((file) {
      final isCurrent = file.path == current.videoPath;
      return PlaybackDetailEpisode(
        id: file.path,
        videoPath: file.path,
        title: p.basenameWithoutExtension(file.path),
        subtitle: isCurrent
            ? current.subtitle ?? current.historyItem?.episodeTitle
            : null,
        animeId: isCurrent ? current.animeId : null,
        episodeId: isCurrent ? current.episodeId : null,
        historyItem: isCurrent ? current.historyItem : null,
        mediaKey: MediaIdentityResolver.forPath(file.path),
      );
    }).toList();
  }

  static PlaybackDetailContext _singleItemContext(
    PlayableItem item, {
    required PlaybackSourceKind kind,
    required String sourceLabel,
  }) {
    final animeId = item.animeId ?? item.historyItem?.animeId;
    return PlaybackDetailContext(
      sourceKind: kind,
      sourceLabel: sourceLabel,
      sourceKey: _sourceKey(item.videoPath, kind),
      title: _resolvedTitle(item),
      subtitle: item.subtitle ?? item.historyItem?.episodeTitle,
      imageUrl: item.historyItem?.thumbnailPath,
      animeId: animeId,
      isIdentified: animeId != null && animeId > 0,
      episodeLoader: () async => <PlaybackDetailEpisode>[
        _episodeFromItem(item),
      ],
    );
  }

  static PlaybackDetailEpisode _episodeFromItem(PlayableItem item) {
    return PlaybackDetailEpisode(
      id: item.videoPath,
      videoPath: item.videoPath,
      title: _episodeTitle(item),
      subtitle: item.title ?? item.historyItem?.animeName,
      animeId: item.animeId ?? item.historyItem?.animeId,
      episodeId: item.episodeId ?? item.historyItem?.episodeId,
      historyItem: item.historyItem,
      actualPlayUrl: item.actualPlayUrl,
      playbackSession: item.playbackSession,
      progress: item.historyItem?.watchProgress,
      mediaKey: item.mediaKey ?? MediaIdentityResolver.forPath(item.videoPath),
    );
  }

  static SMBConnection? _findSmbConnection(String name) {
    final direct = SMBService.instance.getConnectionByIdOrName(name);
    if (direct != null) return direct;
    final matches = SMBService.instance.connections.where((connection) {
      return connection.host == name ||
          '${connection.host}:${connection.port}' == name ||
          connection.wanHost == name ||
          '${connection.wanHost}:${connection.wanPort}' == name;
    }).toList();
    return matches.length == 1 ? matches.first : null;
  }

  static String _smbParent(String rawPath) {
    final normalized = _normalizeSmbPath(rawPath);
    final index = normalized.lastIndexOf('/');
    return index <= 0 ? '/' : normalized.substring(0, index);
  }

  static String _normalizeSmbPath(String rawPath) {
    var normalized = rawPath.replaceAll('\\', '/');
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    normalized = normalized.replaceAll(RegExp(r'/{2,}'), '/');
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String _resolvedTitle(PlayableItem item) {
    return _firstNonEmpty(<String?>[
      item.title,
      item.historyItem?.animeName,
      p.basenameWithoutExtension(_pathName(item.videoPath)),
    ])!;
  }

  static String _episodeTitle(PlayableItem item) {
    return _firstNonEmpty(<String?>[
      item.subtitle,
      item.historyItem?.episodeTitle,
      p.basenameWithoutExtension(_pathName(item.videoPath)),
    ])!;
  }

  static String _pathName(String path) {
    return mediaPathName(path);
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static String _sourceKey(String path, PlaybackSourceKind kind) =>
      '${kind.name}:${p.dirname(path)}';
  static String _normalizeRemoteDirectoryPath(String path) {
    final trimmed = path.trim();
    return trimmed.isEmpty || trimmed == '.' ? '/' : trimmed;
  }
}
