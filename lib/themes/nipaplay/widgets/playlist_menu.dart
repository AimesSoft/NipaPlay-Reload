import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'base_settings_menu.dart';
import 'dart:io';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_episode_mapping_service.dart';
import 'package:nipaplay/services/emby_episode_mapping_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/services/external_player_service.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/utils/message_helper.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/shared_remote_history_helper.dart';

class PlaylistMenu extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;

  const PlaylistMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
  });

  @override
  State<PlaylistMenu> createState() => _PlaylistMenuState();
}

class _PlaylistMenuState extends State<PlaylistMenu> {
  // 文件系统数据
  List<String> _fileSystemEpisodes = [];

  // Jellyfin剧集信息缓存 (episodeId -> episode info)
  final Map<String, dynamic> _jellyfinEpisodeCache = {};

  // Emby剧集信息缓存 (episodeId -> episode info)
  final Map<String, dynamic> _embyEpisodeCache = {};

  // 远程来源（共享/WebDAV/SMB）显示与历史信息缓存
  final Map<String, String> _remoteDisplayNameCache = {};
  final Map<String, WatchHistoryItem> _remoteHistoryCache = {};

  bool _isLoading = true;
  String? _error;
  String? _currentFilePath;
  String? _currentAnimeTitle;

  // 可用的数据源
  bool _hasFileSystemData = false;

  @override
  void initState() {
    super.initState();
    _loadFileSystemData();
  }

  Future<void> _loadFileSystemData() async {
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _fileSystemEpisodes = [];
      _hasFileSystemData = false;
      _jellyfinEpisodeCache.clear();
      _embyEpisodeCache.clear();
      _remoteDisplayNameCache.clear();
      _remoteHistoryCache.clear();

      _currentFilePath = videoState.currentVideoPath;
      _currentAnimeTitle = videoState.animeTitle;

      debugPrint('[播放列表] 开始加载文件系统数据');
      debugPrint('[播放列表] _currentFilePath: $_currentFilePath');
      debugPrint('[播放列表] _currentAnimeTitle: $_currentAnimeTitle');

      if (_currentFilePath != null) {
        final currentPath = _currentFilePath!;

        // 检查是否为Jellyfin流媒体URL
        if (currentPath.startsWith('jellyfin://')) {
          await _loadJellyfinEpisodes();
          return; // 直接返回，不执行本地文件逻辑
        }

        // 检查是否为Emby流媒体URL
        if (currentPath.startsWith('emby://')) {
          await _loadEmbyEpisodes();
          return; // 直接返回，不执行本地文件逻辑
        }

        // 共享媒体库（库管理中的远程目录流）
        if (_isSharedRemoteManagementStreamUrl(currentPath)) {
          await _loadSharedRemoteManagementEpisodes(currentPath);
          return;
        }

        // 共享媒体库（剧集流）
        if (SharedRemoteHistoryHelper.isSharedRemoteStreamPath(currentPath)) {
          final animeId = videoState.animeId;
          if (animeId != null && animeId > 0) {
            await _loadSharedRemoteAnimeEpisodes(animeId);
            return;
          }
          debugPrint('[播放列表] 共享剧集流缺少animeId，回退到其他来源探测');
        }

        // SMB代理流媒体
        if (_isSmbProxyStreamUrl(currentPath)) {
          await _loadSmbEpisodes(currentPath);
          return;
        }

        // WebDAV媒体
        if (MediaSourceUtils.isWebDavPath(currentPath)) {
          await _loadWebDavEpisodes(currentPath);
          return;
        }

        final currentFile = File(currentPath);
        final directory = currentFile.parent;

        if (directory.existsSync()) {
          // 获取目录中的所有视频文件
          final videoExtensions = [
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
            '.m2ts'
          ];
          final videoFiles = directory
              .listSync()
              .whereType<File>()
              .where((file) => videoExtensions
                  .any((ext) => file.path.toLowerCase().endsWith(ext)))
              .toList();

          // 按文件名排序
          videoFiles.sort(
              (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

          _fileSystemEpisodes = videoFiles.map((file) => file.path).toList();
          _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;

          debugPrint('[播放列表] 找到 ${_fileSystemEpisodes.length} 个视频文件');
        }
      }

      if (!_hasFileSystemData) {
        throw Exception('目录中没有找到视频文件');
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[播放列表] 加载文件系统数据失败: $e');
      setState(() {
        _error = '加载播放列表失败：$e';
        _isLoading = false;
      });
    }
  }

  bool _isSharedRemoteManagementStreamUrl(String path) {
    final uri = Uri.tryParse(path);
    if (uri == null) {
      return false;
    }
    return uri.path.endsWith('/api/media/local/manage/stream') &&
        (uri.queryParameters['path']?.trim().isNotEmpty ?? false);
  }

  bool _isSmbProxyStreamUrl(String path) {
    final uri = Uri.tryParse(path);
    if (uri == null) {
      return false;
    }
    return uri.path == '/smb/stream' &&
        (uri.queryParameters['conn']?.trim().isNotEmpty ?? false) &&
        (uri.queryParameters['path']?.trim().isNotEmpty ?? false);
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    if (uri.scheme == 'https') {
      return 443;
    }
    if (uri.scheme == 'http') {
      return 80;
    }
    return 0;
  }

  String _normalizeBasePath(String path) {
    var normalized = path.trim();
    if (normalized.isEmpty) {
      return '/';
    }
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  SharedRemoteHost? _resolveSharedHostForUri(
    SharedRemoteLibraryProvider provider,
    Uri uri,
  ) {
    for (final host in provider.hosts) {
      final hostUri = Uri.tryParse(host.baseUrl);
      if (hostUri == null) {
        continue;
      }
      if (hostUri.scheme != uri.scheme) {
        continue;
      }
      if (hostUri.host != uri.host) {
        continue;
      }
      if (_effectivePort(hostUri) != _effectivePort(uri)) {
        continue;
      }
      final basePath = _normalizeBasePath(hostUri.path);
      if (basePath == '/' || uri.path.startsWith('$basePath/')) {
        return host;
      }
    }
    return null;
  }

  String _normalizeSmbPath(String rawPath) {
    if (rawPath.isEmpty) {
      return '/';
    }
    var normalized = rawPath.replaceAll('\\', '/');
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    normalized = normalized.replaceAll(RegExp(r'/{2,}'), '/');
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _dirnameSmbPath(String smbPath) {
    final normalized = _normalizeSmbPath(smbPath);
    final idx = normalized.lastIndexOf('/');
    if (idx <= 0) {
      return '/';
    }
    return normalized.substring(0, idx);
  }

  SMBConnection? _findSmbConnectionByNameOrHost(String connName) {
    final direct = SMBService.instance.getConnection(connName);
    if (direct != null) {
      return direct;
    }

    final matches = SMBService.instance.connections.where((connection) {
      if (connection.host == connName) {
        return true;
      }
      if ('${connection.host}:${connection.port}' == connName) {
        return true;
      }
      return false;
    }).toList();

    if (matches.length == 1) {
      return matches.first;
    }
    return null;
  }

  String _normalizeRemoteDirectoryPath(String directoryPath) {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty || trimmed == '.') {
      return '/';
    }
    return trimmed;
  }

  Future<void> _loadSharedRemoteManagementEpisodes(String currentPath) async {
    try {
      final uri = Uri.parse(currentPath);
      final rawPath = uri.queryParameters['path']?.trim();
      if (rawPath == null || rawPath.isEmpty) {
        throw Exception('共享文件路径缺失');
      }

      final provider = context.read<SharedRemoteLibraryProvider>();
      final matchedHost = _resolveSharedHostForUri(provider, uri);
      if (matchedHost != null && provider.activeHostId != matchedHost.id) {
        await provider.setActiveHost(matchedHost.id);
      }

      final parentDir = _normalizeRemoteDirectoryPath(p.posix.dirname(rawPath));
      final entries = await provider.browseRemoteDirectory(parentDir);
      final playableEntries = entries
          .where((entry) =>
              !entry.isDirectory && provider.isRemoteFilePlayable(entry))
          .toList();

      playableEntries
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      _fileSystemEpisodes = playableEntries.map((entry) {
        final streamUrl =
            provider.buildRemoteFileStreamUri(entry.path).toString();
        final fallbackName =
            entry.name.isNotEmpty ? entry.name : p.basename(entry.path);
        _remoteDisplayNameCache[streamUrl] =
            p.basenameWithoutExtension(fallbackName);

        final historyItem = WatchHistoryItem(
          filePath: streamUrl,
          animeName: (entry.animeName?.trim().isNotEmpty ?? false)
              ? entry.animeName!.trim()
              : p.basenameWithoutExtension(fallbackName),
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
        _remoteHistoryCache[streamUrl] = historyItem;
        return streamUrl;
      }).toList();

      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;
      if (!_hasFileSystemData) {
        throw Exception('共享目录中没有可播放媒体');
      }

      debugPrint('[播放列表] 共享库管理模式: 找到 ${_fileSystemEpisodes.length} 个媒体项');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[播放列表] 加载共享库管理播放列表失败: $e');
      rethrow;
    }
  }

  Future<void> _loadSharedRemoteAnimeEpisodes(int animeId) async {
    try {
      final provider = context.read<SharedRemoteLibraryProvider>();
      final currentUri = Uri.tryParse(_currentFilePath ?? '');
      if (currentUri != null) {
        final matchedHost = _resolveSharedHostForUri(provider, currentUri);
        if (matchedHost != null && provider.activeHostId != matchedHost.id) {
          await provider.setActiveHost(matchedHost.id);
        }
      }

      final episodes = await provider.loadAnimeEpisodes(animeId);
      if (episodes.isEmpty) {
        throw Exception('该共享番剧没有可播放剧集');
      }

      final sortedEpisodes = List<SharedRemoteEpisode>.from(episodes)
        ..sort((a, b) {
          final aEpisodeId = a.episodeId ?? 0;
          final bEpisodeId = b.episodeId ?? 0;
          if (aEpisodeId != bEpisodeId) {
            return aEpisodeId.compareTo(bEpisodeId);
          }
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });

      final animeName = (_currentAnimeTitle?.trim().isNotEmpty ?? false)
          ? _currentAnimeTitle!.trim()
          : '共享媒体';
      _fileSystemEpisodes = sortedEpisodes
          .where((episode) => episode.streamPath.trim().isNotEmpty)
          .map((episode) {
        final streamUrl = provider.buildStreamUri(episode).toString();
        final title = episode.title.trim().isNotEmpty
            ? episode.title.trim()
            : p.basenameWithoutExtension(episode.fileName);
        _remoteDisplayNameCache[streamUrl] = title;
        _remoteHistoryCache[streamUrl] = WatchHistoryItem(
          filePath: streamUrl,
          animeName: animeName,
          episodeTitle: title,
          animeId: episode.animeId ?? animeId,
          episodeId: episode.episodeId,
          watchProgress: episode.progress ?? 0.0,
          lastPosition: episode.lastPosition ?? 0,
          duration: episode.duration ?? 0,
          lastWatchTime: episode.lastWatchTime ?? DateTime.now(),
          videoHash: episode.videoHash,
        );
        return streamUrl;
      }).toList();

      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;
      if (!_hasFileSystemData) {
        throw Exception('共享番剧没有可播放剧集');
      }

      debugPrint('[播放列表] 共享剧集模式: 找到 ${_fileSystemEpisodes.length} 个剧集');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[播放列表] 加载共享剧集失败: $e');
      rethrow;
    }
  }

  Future<void> _loadWebDavEpisodes(String currentPath) async {
    try {
      await WebDAVService.instance.initialize();
      final resolved = WebDAVService.instance.resolveFileUrl(currentPath);
      if (resolved == null) {
        throw Exception('无法识别WebDAV连接');
      }

      final connectionUri = Uri.parse(resolved.connection.url);
      final basePath = connectionUri.path.isEmpty ? '/' : connectionUri.path;
      final normalizedBasePath = basePath.endsWith('/') ? basePath : '$basePath/';
      final filePath = resolved.relativePath.startsWith('/')
          ? resolved.relativePath
          : '/${resolved.relativePath}';

      String parentDir;
      if (filePath.length > normalizedBasePath.length &&
          filePath.startsWith(normalizedBasePath)) {
        parentDir = filePath.substring(normalizedBasePath.length);
        final lastSlashIndex = parentDir.lastIndexOf('/');
        if (lastSlashIndex > 0) {
          parentDir = parentDir.substring(0, lastSlashIndex);
        } else if (lastSlashIndex == 0) {
          parentDir = '/';
        } else {
          parentDir = '/';
        }
      } else {
        parentDir = p.posix.dirname(resolved.relativePath);
      }

      parentDir = _normalizeRemoteDirectoryPath(parentDir);

      final entries = await WebDAVService.instance.listDirectory(
        resolved.connection,
        parentDir,
      );
      final videoEntries = entries
          .where((entry) =>
              !entry.isDirectory &&
              WebDAVService.instance.isVideoFile(entry.name))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      _fileSystemEpisodes = videoEntries.map((entry) {
        final fileUrl = WebDAVService.instance.getFileUrl(
          resolved.connection,
          entry.path,
        );
        _remoteDisplayNameCache[fileUrl] =
            p.basenameWithoutExtension(entry.name);
        return fileUrl;
      }).toList();

      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;
      if (!_hasFileSystemData) {
        throw Exception('WebDAV目录中没有可播放媒体');
      }

      debugPrint('[播放列表] WebDAV模式: 找到 ${_fileSystemEpisodes.length} 个媒体项');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[播放列表] 加载WebDAV播放列表失败: $e');
      rethrow;
    }
  }

  Future<void> _loadSmbEpisodes(String currentPath) async {
    try {
      final uri = Uri.parse(currentPath);
      final connName = uri.queryParameters['conn']?.trim();
      final smbPath = uri.queryParameters['path']?.trim();
      if (connName == null ||
          connName.isEmpty ||
          smbPath == null ||
          smbPath.isEmpty) {
        throw Exception('SMB地址缺少必要参数');
      }

      await SMBService.instance.initialize();
      await SMBProxyService.instance.initialize();

      final connection = _findSmbConnectionByNameOrHost(connName);
      if (connection == null) {
        throw Exception('找不到SMB连接：$connName');
      }

      final parentDir = _dirnameSmbPath(smbPath);

      final entries =
          await SMBService.instance.listDirectory(connection, parentDir);
      final videoEntries = entries
          .where((entry) =>
              !entry.isDirectory && SMBService.instance.isVideoFile(entry.name))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      _fileSystemEpisodes = videoEntries.map((entry) {
        final url =
            SMBProxyService.instance.buildStreamUrl(connection, entry.path);
        _remoteDisplayNameCache[url] = p.basenameWithoutExtension(entry.name);
        return url;
      }).toList();

      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;
      if (!_hasFileSystemData) {
        throw Exception('SMB目录中没有可播放媒体');
      }

      debugPrint('[播放列表] SMB模式: 找到 ${_fileSystemEpisodes.length} 个媒体项');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[播放列表] 加载SMB播放列表失败: $e');
      rethrow;
    }
  }

  Future<void> _loadJellyfinEpisodes() async {
    try {
      // 解析当前的Jellyfin URL获取episodeId
      final episodeId = _currentFilePath!.replaceFirst('jellyfin://', '');

      // 通过episodeId获取剧集详情，然后获取同一季的所有剧集
      final episodeInfo =
          await JellyfinService.instance.getEpisodeDetails(episodeId);
      if (episodeInfo == null) {
        throw Exception('无法获取Jellyfin剧集信息');
      }

      // 获取该季的所有剧集
      final episodes = await JellyfinService.instance
          .getSeasonEpisodes(episodeInfo.seriesId!, episodeInfo.seasonId!);

      if (episodes.isEmpty) {
        throw Exception('该季没有找到剧集');
      }

      // 按集数排序
      episodes
          .sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));

      // 缓存剧集信息并转换为播放列表格式
      _jellyfinEpisodeCache.clear();
      _fileSystemEpisodes = episodes.map((ep) {
        final episodeUrl = 'jellyfin://${ep.id}';
        _jellyfinEpisodeCache[ep.id] = {
          'name': ep.name,
          'indexNumber': ep.indexNumber,
          'seriesName': ep.seriesName,
        };
        return episodeUrl;
      }).toList();
      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;

      debugPrint('[播放列表] Jellyfin模式: 找到 ${_fileSystemEpisodes.length} 个剧集');

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[播放列表] 加载Jellyfin剧集失败: $e');
      setState(() {
        _error = '加载Jellyfin播放列表失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadEmbyEpisodes() async {
    try {
      // 解析当前的Emby URL获取episodeId
      final embyPath = _currentFilePath!.replaceFirst('emby://', '');
      final pathParts = embyPath.split('/');
      final episodeId = pathParts.last; // 只使用最后一部分作为episodeId

      // 通过episodeId获取剧集详情，然后获取同一季的所有剧集
      final episodeInfo =
          await EmbyService.instance.getEpisodeDetails(episodeId);
      if (episodeInfo == null) {
        throw Exception('无法获取Emby剧集信息');
      }

      // 获取该季的所有剧集
      final episodes = await EmbyService.instance
          .getSeasonEpisodes(episodeInfo.seriesId!, episodeInfo.seasonId!);

      if (episodes.isEmpty) {
        throw Exception('该季没有找到剧集');
      }

      // 按集数排序，将特别篇（indexNumber 为 null 或 0）排在最后
      episodes.sort((a, b) {
        final aIndex = (a.indexNumber == null || a.indexNumber == 0)
            ? 999999
            : a.indexNumber!;
        final bIndex = (b.indexNumber == null || b.indexNumber == 0)
            ? 999999
            : b.indexNumber!;
        return aIndex.compareTo(bIndex);
      });

      // 缓存剧集信息并转换为播放列表格式
      _embyEpisodeCache.clear();
      _fileSystemEpisodes = episodes.map((ep) {
        final episodeUrl = 'emby://${ep.id}';
        _embyEpisodeCache[ep.id] = {
          'name': ep.name,
          'indexNumber': ep.indexNumber,
          'seriesName': ep.seriesName,
        };
        return episodeUrl;
      }).toList();
      _hasFileSystemData = _fileSystemEpisodes.isNotEmpty;

      debugPrint('[播放列表] Emby模式: 找到 ${_fileSystemEpisodes.length} 个剧集');

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[播放列表] 加载Emby剧集失败: $e');
      setState(() {
        _error = '加载Emby播放列表失败：$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _playEpisode(String filePath) async {
    try {
      debugPrint('[播放列表] 开始播放剧集: $filePath');

      final videoState = Provider.of<VideoPlayerState>(context, listen: false);

      if (mounted) {
        // 检查是否为Jellyfin URL
        if (filePath.startsWith('jellyfin://')) {
          // Jellyfin流媒体模式：使用完整的弹幕映射和API获取逻辑
          final episodeId = filePath.replaceFirst('jellyfin://', '');
          final episodeInfo =
              await JellyfinService.instance.getEpisodeDetails(episodeId);

          if (episodeInfo == null) {
            throw Exception('无法获取Jellyfin剧集信息');
          }

          // 获取播放会话
          final playbackSession =
              await JellyfinService.instance.createPlaybackSession(
            itemId: episodeId,
          );
          debugPrint('[播放列表] 获取Jellyfin播放会话: ${playbackSession.streamUrl}');

          // 尝试获取弹幕映射
          int? animeId;
          int? episodeIdForDanmaku;

          try {
            final mapping = await JellyfinEpisodeMappingService.instance
                .getEpisodeMapping(episodeId);
            if (mapping != null) {
              animeId = mapping['dandanplay_anime_id'] as int?;
              episodeIdForDanmaku = mapping['dandanplay_episode_id'] as int?;
              debugPrint(
                  '[播放列表] 找到剧集弹幕映射: animeId=$animeId, episodeId=$episodeIdForDanmaku');
            } else {
              debugPrint('[播放列表] 未找到剧集弹幕映射，将进行自动匹配');
            }
          } catch (e) {
            debugPrint('[播放列表] 获取剧集弹幕映射失败: $e');
          }

          // 创建带有弹幕信息的历史项
          final historyItem = await _createJellyfinHistoryItem(
              episodeInfo, animeId, episodeIdForDanmaku);

          final playableItem = PlayableItem(
            videoPath: filePath,
            title: historyItem.animeName,
            subtitle: historyItem.episodeTitle,
            animeId: historyItem.animeId,
            episodeId: historyItem.episodeId,
            historyItem: historyItem,
            playbackSession: playbackSession,
          );
          if (!mounted) {
            return;
          }
          if (await ExternalPlayerService.tryHandlePlayback(
              context, playableItem)) {
            if (mounted) {
              widget.onClose();
            }
            return;
          }

          // 按照剧集导航的方式，使用Jellyfin协议URL作为标识符，HTTP URL作为实际播放源
          await videoState.initializePlayer(
            filePath, // 使用Jellyfin协议URL作为标识符
            historyItem: historyItem,
            playbackSession: playbackSession,
          );
          debugPrint('[播放列表] Jellyfin剧集播放完成');
        } else if (filePath.startsWith('emby://')) {
          // Emby流媒体模式：使用完整的弹幕映射和API获取逻辑
          final embyPath = filePath.replaceFirst('emby://', '');
          final pathParts = embyPath.split('/');
          final episodeId = pathParts.last; // 只使用最后一部分作为episodeId
          final episodeInfo =
              await EmbyService.instance.getEpisodeDetails(episodeId);

          if (episodeInfo == null) {
            throw Exception('无法获取Emby剧集信息');
          }

          // 获取播放会话
          final playbackSession =
              await EmbyService.instance.createPlaybackSession(
            itemId: episodeId,
          );
          debugPrint('[播放列表] 获取Emby播放会话: ${playbackSession.streamUrl}');

          // 尝试获取弹幕映射
          int? animeId;
          int? episodeIdForDanmaku;

          try {
            final mapping = await EmbyEpisodeMappingService.instance
                .getEpisodeMapping(episodeId);
            if (mapping != null) {
              animeId = mapping['dandanplay_anime_id'] as int?;
              episodeIdForDanmaku = mapping['dandanplay_episode_id'] as int?;
              debugPrint(
                  '[播放列表] 找到Emby剧集弹幕映射: animeId=$animeId, episodeId=$episodeIdForDanmaku');
            } else {
              debugPrint('[播放列表] 未找到Emby剧集弹幕映射，将进行自动匹配');
            }
          } catch (e) {
            debugPrint('[播放列表] 获取Emby剧集弹幕映射失败: $e');
          }

          // 创建带有弹幕信息的历史项
          final historyItem = await _createEmbyHistoryItem(
              episodeInfo, animeId, episodeIdForDanmaku);

          final playableItem = PlayableItem(
            videoPath: filePath,
            title: historyItem.animeName,
            subtitle: historyItem.episodeTitle,
            animeId: historyItem.animeId,
            episodeId: historyItem.episodeId,
            historyItem: historyItem,
            playbackSession: playbackSession,
          );
          if (!mounted) {
            return;
          }
          if (await ExternalPlayerService.tryHandlePlayback(
              context, playableItem)) {
            if (mounted) {
              widget.onClose();
            }
            return;
          }

          // 按照剧集导航的方式，使用Emby协议URL作为标识符，HTTP URL作为实际播放源
          await videoState.initializePlayer(
            filePath, // 使用Emby协议URL作为标识符
            historyItem: historyItem,
            playbackSession: playbackSession,
          );
          debugPrint('[播放列表] Emby剧集播放完成');
        } else {
          final uri = Uri.tryParse(filePath);
          final isHttpStream =
              uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
          final cachedHistory = _remoteHistoryCache[filePath];

          if (isHttpStream) {
            // 共享/WebDAV/SMB 等网络流媒体
            final lastSegment =
                uri.pathSegments.isNotEmpty ? uri.pathSegments.last : filePath;
            final fallbackTitle = _remoteDisplayNameCache[filePath] ??
                p.basenameWithoutExtension(Uri.decodeComponent(lastSegment));
            final playableItem = PlayableItem(
              videoPath: filePath,
              title: cachedHistory?.animeName ?? fallbackTitle,
              subtitle: cachedHistory?.episodeTitle,
              animeId: cachedHistory?.animeId,
              episodeId: cachedHistory?.episodeId,
              historyItem: cachedHistory,
              actualPlayUrl: filePath,
            );
            if (!mounted) {
              return;
            }
            if (await ExternalPlayerService.tryHandlePlayback(
                context, playableItem)) {
              if (mounted) {
                widget.onClose();
              }
              return;
            }

            await videoState.initializePlayer(
              filePath,
              historyItem: cachedHistory,
              actualPlayUrl: filePath,
            );
            debugPrint('[播放列表] 远程流媒体播放完成');
          } else {
            // 本地文件模式
            final file = File(filePath);
            if (!file.existsSync()) {
              throw Exception('文件不存在: $filePath');
            }

            final playableItem = PlayableItem(videoPath: filePath);
            if (!mounted) {
              return;
            }
            if (await ExternalPlayerService.tryHandlePlayback(
                context, playableItem)) {
              if (mounted) {
                widget.onClose();
              }
              return;
            }

            await videoState.initializePlayer(filePath);
            debugPrint('[播放列表] 文件路径播放完成');
          }
        }

        // 播放成功后关闭菜单
        if (mounted) {
          widget.onClose();
        }
      } else {
        debugPrint('[播放列表] 组件已卸载，取消播放');
      }
    } catch (e) {
      debugPrint('[播放列表] 播放剧集失败: $e');

      // 发生错误时也要关闭菜单
      if (mounted) {
        widget.onClose();

        MessageHelper.showMessage(
          context,
          '播放失败：$e',
          isError: true,
        );
      }
    }
  }

  String _getEpisodeDisplayName(String filePath) {
    final cachedRemoteName = _remoteDisplayNameCache[filePath];
    if (cachedRemoteName != null && cachedRemoteName.trim().isNotEmpty) {
      return cachedRemoteName;
    }

    // 检查是否为Jellyfin URL
    if (filePath.startsWith('jellyfin://')) {
      final episodeId = filePath.replaceFirst('jellyfin://', '');
      final cachedInfo = _jellyfinEpisodeCache[episodeId];
      if (cachedInfo != null) {
        final indexNumber = cachedInfo['indexNumber'] as int?;
        final name = cachedInfo['name'] as String?;
        if (indexNumber != null && name != null) {
          return '第$indexNumber话 - $name';
        } else if (name != null) {
          return name;
        }
      }
      return 'Episode $episodeId'; // 默认显示
    }

    // 检查是否为Emby URL
    if (filePath.startsWith('emby://')) {
      final embyPath = filePath.replaceFirst('emby://', '');
      final pathParts = embyPath.split('/');
      final episodeId = pathParts.last; // 只使用最后一部分作为episodeId
      final cachedInfo = _embyEpisodeCache[episodeId];
      if (cachedInfo != null) {
        final indexNumber = cachedInfo['indexNumber'] as int?;
        final name = cachedInfo['name'] as String?;
        if (indexNumber != null && name != null) {
          return '第$indexNumber话 - $name';
        } else if (name != null) {
          return name;
        }
      }
      return 'Episode $episodeId'; // 默认显示
    }

    final uri = Uri.tryParse(filePath);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return p
          .basenameWithoutExtension(Uri.decodeComponent(uri.pathSegments.last));
    }

    return p.basenameWithoutExtension(filePath);
  }

  bool _isSameSharedManagementStream(String a, String b) {
    if (!_isSharedRemoteManagementStreamUrl(a) ||
        !_isSharedRemoteManagementStreamUrl(b)) {
      return false;
    }
    final aUri = Uri.tryParse(a);
    final bUri = Uri.tryParse(b);
    if (aUri == null || bUri == null) {
      return false;
    }
    return aUri.queryParameters['path'] == bUri.queryParameters['path'] &&
        aUri.host == bUri.host &&
        _effectivePort(aUri) == _effectivePort(bUri);
  }

  bool _isSameSmbStream(String a, String b) {
    if (!_isSmbProxyStreamUrl(a) || !_isSmbProxyStreamUrl(b)) {
      return false;
    }
    final aUri = Uri.tryParse(a);
    final bUri = Uri.tryParse(b);
    if (aUri == null || bUri == null) {
      return false;
    }
    final aConn = aUri.queryParameters['conn']?.trim();
    final bConn = bUri.queryParameters['conn']?.trim();
    final aPath = _normalizeSmbPath(aUri.queryParameters['path'] ?? '');
    final bPath = _normalizeSmbPath(bUri.queryParameters['path'] ?? '');
    return aConn == bConn && aPath == bPath;
  }

  bool _isCurrentEpisode(String filePath) {
    final currentPath = _currentFilePath;
    if (currentPath == null) {
      return false;
    }
    if (filePath == currentPath) {
      return true;
    }
    if (_isSameSmbStream(filePath, currentPath)) {
      return true;
    }
    if (_isSameSharedManagementStream(filePath, currentPath)) {
      return true;
    }
    return false;
  }

  /// 创建Jellyfin历史项，包含完整的弹幕映射预测和API获取的准确信息
  Future<WatchHistoryItem> _createJellyfinHistoryItem(
      JellyfinEpisodeInfo episode, int? animeId, int? episodeId) async {
    try {
      int? finalAnimeId = animeId;
      int? finalEpisodeId = episodeId;

      // 如果没有提供映射的弹幕ID，尝试智能预测
      if (finalAnimeId == null || finalEpisodeId == null) {
        debugPrint('[播放列表] 未提供弹幕映射，开始智能预测');

        // 1. 首先尝试获取现有的剧集映射
        final existingMapping = await JellyfinEpisodeMappingService.instance
            .getEpisodeMapping(episode.id);
        if (existingMapping != null) {
          finalEpisodeId = existingMapping['dandanplay_episode_id'] as int?;

          // 通过系列ID获取动画映射
          final animeMapping =
              await JellyfinEpisodeMappingService.instance.getAnimeMapping(
            jellyfinSeriesId: episode.seriesId!,
            jellyfinSeasonId: episode.seasonId,
          );

          if (animeMapping != null) {
            finalAnimeId = animeMapping['dandanplay_anime_id'] as int?;
            debugPrint(
                '[播放列表] 从现有映射获取弹幕ID: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
          }
        } else {
          // 2. 如果没有现有映射，尝试智能预测
          debugPrint('[播放列表] 没有现有映射，开始智能预测映射');
          final predictedEpisodeId = await JellyfinEpisodeMappingService
              .instance
              .predictEpisodeMapping(
            jellyfinEpisode: episode,
          );

          if (predictedEpisodeId != null) {
            finalEpisodeId = predictedEpisodeId;

            // 获取对应的动画ID
            final animeMapping =
                await JellyfinEpisodeMappingService.instance.getAnimeMapping(
              jellyfinSeriesId: episode.seriesId!,
              jellyfinSeasonId: episode.seasonId,
            );

            if (animeMapping != null) {
              finalAnimeId = animeMapping['dandanplay_anime_id'] as int?;
              debugPrint(
                  '[播放列表] 预测映射成功: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
            }
          } else {
            debugPrint('[播放列表] 智能预测失败，将使用基础信息创建历史项');
          }
        }
      }

      // 如果有映射的弹幕ID，使用DanDanPlay API获取正确的剧集信息
      if (finalAnimeId != null && finalEpisodeId != null) {
        try {
          // 使用DanDanPlay API获取准确的剧集标题，保持标题一致性
          debugPrint(
              '[播放列表] 使用弹幕ID查询剧集信息: animeId=$finalAnimeId, episodeId=$finalEpisodeId');

          // 获取动画详情以获取准确的标题
          final bangumiDetails =
              await DandanplayService.getBangumiDetails(finalAnimeId);

          String? animeTitle;
          String? episodeTitle;

          if (bangumiDetails['success'] == true &&
              bangumiDetails['bangumi'] != null) {
            final bangumi = bangumiDetails['bangumi'];
            animeTitle = bangumi['animeTitle'] as String?;

            // 查找对应的剧集标题
            if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
              final episodes = bangumi['episodes'] as List;
              final targetEpisode = episodes.firstWhere(
                (ep) => ep['episodeId'] == finalEpisodeId,
                orElse: () => null,
              );

              if (targetEpisode != null) {
                episodeTitle = targetEpisode['episodeTitle'] as String?;
                debugPrint('[播放列表] 从DanDanPlay API获取到剧集标题: $episodeTitle');
              }
            }
          }

          // 创建包含正确弹幕信息和标题的历史项
          return WatchHistoryItem(
            filePath: 'jellyfin://${episode.id}',
            animeName: animeTitle ?? episode.seriesName ?? 'Unknown',
            episodeTitle: episodeTitle ?? episode.name,
            animeId: finalAnimeId,
            episodeId: finalEpisodeId,
            watchProgress: 0.0,
            lastPosition: 0,
            duration: 0,
            lastWatchTime: DateTime.now(),
            thumbnailPath: null,
            isFromScan: false,
          );
        } catch (e) {
          debugPrint('[播放列表] 获取DanDanPlay剧集信息失败: $e，使用基础信息');
        }
      }

      // 如果没有映射的弹幕ID或获取失败，使用基础信息创建历史项
      debugPrint('[播放列表] 没有映射的弹幕ID，使用基础信息创建历史项');
      return episode.toWatchHistoryItem();
    } catch (e) {
      debugPrint('[播放列表] 创建历史项时出错：$e，使用基础历史项');
      return episode.toWatchHistoryItem();
    }
  }

  /// 创建Emby历史项，包含完整的弹幕映射预测和API获取的准确信息
  Future<WatchHistoryItem> _createEmbyHistoryItem(
      EmbyEpisodeInfo episode, int? animeId, int? episodeId) async {
    try {
      int? finalAnimeId = animeId;
      int? finalEpisodeId = episodeId;

      // 如果没有提供映射的弹幕ID，尝试智能预测
      if (finalAnimeId == null || finalEpisodeId == null) {
        debugPrint('[播放列表] 未提供Emby弹幕映射，开始智能预测');

        // 1. 首先尝试获取现有的剧集映射
        final existingMapping = await EmbyEpisodeMappingService.instance
            .getEpisodeMapping(episode.id);
        if (existingMapping != null) {
          finalEpisodeId = existingMapping['dandanplay_episode_id'] as int?;

          // 通过系列ID获取动画映射
          final animeMapping =
              await EmbyEpisodeMappingService.instance.getAnimeMapping(
            embySeriesId: episode.seriesId!,
            embySeasonId: episode.seasonId,
          );

          if (animeMapping != null) {
            finalAnimeId = animeMapping['dandanplay_anime_id'] as int?;
            debugPrint(
                '[播放列表] 从现有Emby映射获取弹幕ID: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
          }
        } else {
          // 2. 如果没有现有映射，尝试智能预测
          debugPrint('[播放列表] 没有现有Emby映射，开始智能预测映射');
          final predictedEpisodeId =
              await EmbyEpisodeMappingService.instance.predictEpisodeId(
            embyEpisodeId: episode.id,
            embyIndexNumber: episode.indexNumber ?? 0,
            embySeriesId: episode.seriesId!,
            embySeasonId: episode.seasonId,
          );

          if (predictedEpisodeId != null) {
            finalEpisodeId = predictedEpisodeId;

            // 获取对应的动画ID
            final animeMapping =
                await EmbyEpisodeMappingService.instance.getAnimeMapping(
              embySeriesId: episode.seriesId!,
              embySeasonId: episode.seasonId,
            );

            if (animeMapping != null) {
              finalAnimeId = animeMapping['dandanplay_anime_id'] as int?;
              debugPrint(
                  '[播放列表] Emby预测映射成功: animeId=$finalAnimeId, episodeId=$finalEpisodeId');
            }
          } else {
            debugPrint('[播放列表] Emby智能预测失败，将使用基础信息创建历史项');
          }
        }
      }

      // 如果有映射的弹幕ID，使用DanDanPlay API获取正确的剧集信息
      if (finalAnimeId != null && finalEpisodeId != null) {
        try {
          // 使用DanDanPlay API获取准确的剧集标题，保持标题一致性
          debugPrint(
              '[播放列表] 使用弹幕ID查询Emby剧集信息: animeId=$finalAnimeId, episodeId=$finalEpisodeId');

          // 获取动画详情以获取准确的标题
          final bangumiDetails =
              await DandanplayService.getBangumiDetails(finalAnimeId);

          String? animeTitle;
          String? episodeTitle;

          if (bangumiDetails['success'] == true &&
              bangumiDetails['bangumi'] != null) {
            final bangumi = bangumiDetails['bangumi'];
            animeTitle = bangumi['animeTitle'] as String?;

            // 查找对应的剧集标题
            if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
              final episodes = bangumi['episodes'] as List;
              final targetEpisode = episodes.firstWhere(
                (ep) => ep['episodeId'] == finalEpisodeId,
                orElse: () => null,
              );

              if (targetEpisode != null) {
                episodeTitle = targetEpisode['episodeTitle'] as String?;
                debugPrint('[播放列表] 从DanDanPlay API获取到Emby剧集标题: $episodeTitle');
              }
            }
          }

          // 创建包含正确弹幕信息和标题的历史项
          return WatchHistoryItem(
            filePath: 'emby://${episode.id}',
            animeName: animeTitle ?? episode.seriesName ?? 'Unknown',
            episodeTitle: episodeTitle ?? episode.name,
            animeId: finalAnimeId,
            episodeId: finalEpisodeId,
            watchProgress: 0.0,
            lastPosition: 0,
            duration: 0,
            lastWatchTime: DateTime.now(),
            thumbnailPath: null,
            isFromScan: false,
          );
        } catch (e) {
          debugPrint('[播放列表] 获取DanDanPlay Emby剧集信息失败: $e，使用基础信息');
        }
      }

      // 如果没有映射的弹幕ID或获取失败，使用基础信息创建历史项
      debugPrint('[播放列表] 没有映射的Emby弹幕ID，使用基础信息创建历史项');
      return episode.toWatchHistoryItem();
    } catch (e) {
      debugPrint('[播放列表] 创建Emby历史项时出错：$e，使用基础历史项');
      return episode.toWatchHistoryItem();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseSettingsMenu(
      title: '播放列表',
      onClose: widget.onClose,
      onHoverChanged: widget.onHoverChanged,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 动画标题
          if (_currentAnimeTitle != null)
            Container(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _currentAnimeTitle!,
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),

          // 内容区域 - 移除固定高度限制
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              '加载播放列表中...',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _loadFileSystemData();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (!_hasFileSystemData || _fileSystemEpisodes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              color: Colors.white,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(
              '目录中没有找到视频文件',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 添加顶部边距
        const SizedBox(height: 8),
        // 使用Column和多个Container替代ListView.builder
        for (int index = 0; index < _fileSystemEpisodes.length; index++)
          Builder(
            builder: (context) {
              final filePath = _fileSystemEpisodes[index];
              final isCurrentEpisode = _isCurrentEpisode(filePath);
              final displayName = _getEpisodeDisplayName(filePath);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isCurrentEpisode
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.transparent,
                  border: isCurrentEpisode
                      ? Border.all(
                          color: Colors.white.withValues(alpha: 0.5), width: 1)
                      : null,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(
                    displayName,
                    locale: const Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      color: isCurrentEpisode
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.87),
                      fontSize: 14,
                      fontWeight: isCurrentEpisode
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isCurrentEpisode
                      ? const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                  onTap: isCurrentEpisode
                      ? null // 当前剧集不可点击
                      : () => _playEpisode(filePath),
                  enabled: !isCurrentEpisode,
                ),
              );
            },
          ),
        // 添加底部边距，确保最后一项不被遮挡
        const SizedBox(height: 16),
      ],
    );
  }
}
