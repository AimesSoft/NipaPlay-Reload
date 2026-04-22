import 'dart:io';

import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

import 'package:path/path.dart' as p;
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/external_player_service.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/shared_remote_history_helper.dart';
import 'package:provider/provider.dart';

class CupertinoPlaylistPane extends StatefulWidget {
  const CupertinoPlaylistPane({
    super.key,
    required this.videoState,
    required this.onBack,
  });

  final VideoPlayerState videoState;
  final VoidCallback onBack;

  @override
  State<CupertinoPlaylistPane> createState() => _CupertinoPlaylistPaneState();
}

class _CupertinoPlaylistPaneState extends State<CupertinoPlaylistPane> {
  List<String> _episodes = [];
  final Map<String, dynamic> _jellyfinCache = {};
  final Map<String, dynamic> _embyCache = {};
  final Map<String, String> _remoteDisplayNameCache = {};
  final Map<String, String> _remoteSubtitleCache = {};

  bool _isLoading = true;
  String? _error;
  String? _currentPath;
  String? _animeTitle;
  String _dataSourceType = 'unknown';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _currentPath = widget.videoState.currentVideoPath;
      _animeTitle = widget.videoState.animeTitle;
      _episodes = [];
      _jellyfinCache.clear();
      _embyCache.clear();
      _remoteDisplayNameCache.clear();
      _remoteSubtitleCache.clear();
      final path = _currentPath;

      if (path == null) {
        throw Exception('没有正在播放的文件');
      }

      if (path.startsWith('jellyfin://')) {
        _dataSourceType = 'jellyfin';
        await _loadJellyfinEpisodes(path);
      } else if (path.startsWith('emby://')) {
        _dataSourceType = 'emby';
        await _loadEmbyEpisodes(path);
      } else if (_isSharedRemoteManagementStreamUrl(path)) {
        _dataSourceType = 'shared_manage';
        await _loadSharedRemoteManagementEpisodes(path);
      } else if (SharedRemoteHistoryHelper.isSharedRemoteStreamPath(path)) {
        final animeId = widget.videoState.animeId;
        if (animeId != null && animeId > 0) {
          _dataSourceType = 'shared_anime';
          await _loadSharedRemoteAnimeEpisodes(animeId, path);
        } else {
          throw Exception('共享媒体缺少番剧ID，无法加载播放列表');
        }
      } else if (_isSmbProxyStreamUrl(path)) {
        _dataSourceType = 'smb';
        await _loadSmbEpisodes(path);
      } else if (MediaSourceUtils.isWebDavPath(path)) {
        _dataSourceType = 'webdav';
        await _loadWebDavEpisodes(path);
      } else {
        _dataSourceType = 'filesystem';
        await _loadFileSystemEpisodes(path);
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  bool _isSharedRemoteManagementStreamUrl(String path) {
    final uri = Uri.tryParse(path);
    if (uri == null) return false;
    return uri.path.endsWith('/api/media/local/manage/stream') &&
        (uri.queryParameters['path']?.trim().isNotEmpty ?? false);
  }

  bool _isSmbProxyStreamUrl(String path) {
    final uri = Uri.tryParse(path);
    if (uri == null) return false;
    return uri.path == '/smb/stream' &&
        (uri.queryParameters['conn']?.trim().isNotEmpty ?? false) &&
        (uri.queryParameters['path']?.trim().isNotEmpty ?? false);
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    if (uri.scheme == 'https') return 443;
    if (uri.scheme == 'http') return 80;
    return 0;
  }

  String _normalizeBasePath(String path) {
    var normalized = path.trim();
    if (normalized.isEmpty) return '/';
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
      if (hostUri == null) continue;
      if (hostUri.scheme != uri.scheme) continue;
      if (hostUri.host != uri.host) continue;
      if (_effectivePort(hostUri) != _effectivePort(uri)) continue;
      final basePath = _normalizeBasePath(hostUri.path);
      if (basePath == '/' || uri.path.startsWith('$basePath/')) {
        return host;
      }
    }
    return null;
  }

  String _normalizeSmbPath(String rawPath) {
    if (rawPath.isEmpty) return '/';
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
    if (idx <= 0) return '/';
    return normalized.substring(0, idx);
  }

  SMBConnection? _findSmbConnectionByNameOrHost(String connName) {
    final direct = SMBService.instance.getConnection(connName);
    if (direct != null) return direct;
    final matches = SMBService.instance.connections.where((connection) {
      if (connection.host == connName) return true;
      if ('${connection.host}:${connection.port}' == connName) return true;
      return false;
    }).toList();
    if (matches.length == 1) return matches.first;
    return null;
  }

  String _normalizeRemoteDirectoryPath(String directoryPath) {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty || trimmed == '.') {
      return '/';
    }
    return trimmed;
  }

  Future<void> _loadFileSystemEpisodes(String path) async {
    final currentFile = File(path);
    final dir = currentFile.parent;
    final videoExts = [
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

    if (!dir.existsSync()) {
      throw Exception('视频目录不存在');
    }

    final files = dir
        .listSync()
        .whereType<File>()
        .where(
          (file) => videoExts.any(
            (ext) => file.path.toLowerCase().endsWith(ext),
          ),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) {
      throw Exception('当前目录没有其他视频文件');
    }

    _episodes = files.map((file) => file.path).toList();
  }

  Future<void> _loadSharedRemoteManagementEpisodes(String path) async {
    final uri = Uri.parse(path);
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
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    _episodes = playableEntries.map((entry) {
      final streamUrl =
          provider.buildRemoteFileStreamUri(entry.path).toString();
      final fallbackName =
          entry.name.isNotEmpty ? entry.name : p.basename(entry.path);
      final displayName = p.basenameWithoutExtension(fallbackName);
      _remoteDisplayNameCache[streamUrl] = displayName;
      _remoteSubtitleCache[streamUrl] =
          (entry.episodeTitle?.trim().isNotEmpty ?? false)
              ? entry.episodeTitle!.trim()
              : (entry.animeName?.trim().isNotEmpty ?? false
                  ? entry.animeName!.trim()
                  : '共享媒体');
      return streamUrl;
    }).toList();

    if (_episodes.isEmpty) {
      throw Exception('共享目录中没有可播放媒体');
    }
  }

  Future<void> _loadSharedRemoteAnimeEpisodes(
      int animeId, String currentPath) async {
    final provider = context.read<SharedRemoteLibraryProvider>();
    final currentUri = Uri.tryParse(currentPath);
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

    final sorted = List<SharedRemoteEpisode>.from(episodes)
      ..sort((a, b) {
        final aId = a.episodeId ?? 0;
        final bId = b.episodeId ?? 0;
        if (aId != bId) return aId.compareTo(bId);
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    _episodes = sorted
        .where((episode) => episode.streamPath.trim().isNotEmpty)
        .map((episode) {
      final streamUrl = provider.buildStreamUri(episode).toString();
      final title = episode.title.trim().isNotEmpty
          ? episode.title.trim()
          : p.basenameWithoutExtension(episode.fileName);
      _remoteDisplayNameCache[streamUrl] = title;
      _remoteSubtitleCache[streamUrl] = _animeTitle ?? '共享媒体';
      return streamUrl;
    }).toList();

    if (_episodes.isEmpty) {
      throw Exception('共享番剧没有可播放剧集');
    }
  }

  Future<void> _loadWebDavEpisodes(String path) async {
    await WebDAVService.instance.initialize();
    final resolved = WebDAVService.instance.resolveFileUrl(path);
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

    _episodes = videoEntries.map((entry) {
      final fileUrl = WebDAVService.instance.getFileUrl(
        resolved.connection,
        entry.path,
      );
      _remoteDisplayNameCache[fileUrl] = p.basenameWithoutExtension(entry.name);
      _remoteSubtitleCache[fileUrl] = resolved.connection.name;
      return fileUrl;
    }).toList();

    if (_episodes.isEmpty) {
      throw Exception('WebDAV目录中没有可播放媒体');
    }
  }

  Future<void> _loadSmbEpisodes(String path) async {
    final uri = Uri.parse(path);
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

    _episodes = videoEntries.map((entry) {
      final url =
          SMBProxyService.instance.buildStreamUrl(connection, entry.path);
      _remoteDisplayNameCache[url] = p.basenameWithoutExtension(entry.name);
      _remoteSubtitleCache[url] = connection.name;
      return url;
    }).toList();

    if (_episodes.isEmpty) {
      throw Exception('SMB目录中没有可播放媒体');
    }
  }

  Future<void> _loadJellyfinEpisodes(String path) async {
    final episodeId = path.replaceFirst('jellyfin://', '');
    final info = await JellyfinService.instance.getEpisodeDetails(episodeId);
    if (info == null) throw Exception('无法获取 Jellyfin 剧集信息');

    final episodes = await JellyfinService.instance.getSeasonEpisodes(
      info.seriesId!,
      info.seasonId!,
    );
    if (episodes.isEmpty) throw Exception('该季没有剧集');

    episodes.sort((a, b) {
      final aIndex = (a.indexNumber == null || a.indexNumber == 0)
          ? 999999
          : a.indexNumber!;
      final bIndex = (b.indexNumber == null || b.indexNumber == 0)
          ? 999999
          : b.indexNumber!;
      return aIndex.compareTo(bIndex);
    });

    _episodes = episodes.map((ep) {
      final entry = {
        'name': ep.name,
        'indexNumber': ep.indexNumber,
        'seriesName': ep.seriesName,
      };
      _jellyfinCache[ep.id] = entry;
      return 'jellyfin://${ep.id}';
    }).toList();
  }

  Future<void> _loadEmbyEpisodes(String path) async {
    final raw = path.replaceFirst('emby://', '');
    final episodeId = raw.split('/').last;
    final info = await EmbyService.instance.getEpisodeDetails(episodeId);
    if (info == null) throw Exception('无法获取 Emby 剧集信息');

    final episodes = await EmbyService.instance.getSeasonEpisodes(
      info.seriesId!,
      info.seasonId!,
    );
    if (episodes.isEmpty) throw Exception('该季没有剧集');

    episodes.sort((a, b) {
      final aIndex = (a.indexNumber == null || a.indexNumber == 0)
          ? 999999
          : a.indexNumber!;
      final bIndex = (b.indexNumber == null || b.indexNumber == 0)
          ? 999999
          : b.indexNumber!;
      return aIndex.compareTo(bIndex);
    });

    _episodes = episodes.map((ep) {
      final entry = {
        'name': ep.name,
        'indexNumber': ep.indexNumber,
        'seriesName': ep.seriesName,
      };
      _embyCache[ep.id] = entry;
      return 'emby://${ep.id}';
    }).toList();
  }

  String _displayName(String path) {
    final cachedRemoteName = _remoteDisplayNameCache[path];
    if (cachedRemoteName != null && cachedRemoteName.trim().isNotEmpty) {
      return cachedRemoteName;
    }

    switch (_dataSourceType) {
      case 'jellyfin':
        final id = path.replaceFirst('jellyfin://', '');
        final info = _jellyfinCache[id];
        if (info != null) {
          final index = info['indexNumber'] ?? 0;
          return 'EP$index · ${info['name'] ?? ''}';
        }
        return 'Jellyfin 剧集';
      case 'emby':
        final id = path.replaceFirst('emby://', '');
        final info = _embyCache[id];
        if (info != null) {
          final index = info['indexNumber'] ?? 0;
          return 'EP$index · ${info['name'] ?? ''}';
        }
        return 'Emby 剧集';
      default:
        final uri = Uri.tryParse(path);
        if (uri != null && uri.pathSegments.isNotEmpty) {
          return Uri.decodeComponent(uri.pathSegments.last);
        }
        return path.split('/').last;
    }
  }

  String _subtitle(String path) {
    final cachedRemoteSubtitle = _remoteSubtitleCache[path];
    if (cachedRemoteSubtitle != null && cachedRemoteSubtitle.isNotEmpty) {
      return cachedRemoteSubtitle;
    }

    switch (_dataSourceType) {
      case 'jellyfin':
        final id = path.replaceFirst('jellyfin://', '');
        return _jellyfinCache[id]?['seriesName'] ?? 'Jellyfin';
      case 'emby':
        final id = path.replaceFirst('emby://', '');
        return _embyCache[id]?['seriesName'] ?? 'Emby';
      case 'shared_manage':
        return '共享库管理';
      case 'shared_anime':
        return _animeTitle ?? '共享媒体';
      case 'webdav':
        return 'WebDAV';
      case 'smb':
        return 'SMB';
      default:
        return path;
    }
  }

  IconData _sourceIcon() {
    switch (_dataSourceType) {
      case 'jellyfin':
      case 'emby':
      case 'shared_manage':
      case 'shared_anime':
      case 'webdav':
      case 'smb':
        return CupertinoIcons.cloud;
      default:
        return CupertinoIcons.folder;
    }
  }

  String _sourceName() {
    switch (_dataSourceType) {
      case 'jellyfin':
        return 'Jellyfin';
      case 'emby':
        return 'Emby';
      case 'shared_manage':
        return '共享媒体库管理';
      case 'shared_anime':
        return '共享媒体库';
      case 'webdav':
        return 'WebDAV';
      case 'smb':
        return 'SMB';
      default:
        return '本地文件';
    }
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

  bool _isCurrentEpisode(String path) {
    final currentPath = _currentPath;
    if (currentPath == null) return false;
    if (path == currentPath) return true;
    if (_isSameSmbStream(path, currentPath)) return true;
    if (_isSameSharedManagementStream(path, currentPath)) return true;
    return false;
  }

  Future<void> _playEpisode(String path) async {
    try {
      PlaybackSession? playbackSession;
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      if (settingsProvider.useExternalPlayer) {
        if (path.startsWith('jellyfin://')) {
          final itemId = path.replaceFirst('jellyfin://', '');
          playbackSession =
              await JellyfinService.instance.createPlaybackSession(
            itemId: itemId,
          );
        } else if (path.startsWith('emby://')) {
          final embyPath = path.replaceFirst('emby://', '');
          final parts = embyPath.split('/');
          final embyId = parts.isNotEmpty ? parts.last : embyPath;
          playbackSession = await EmbyService.instance.createPlaybackSession(
            itemId: embyId,
          );
        }

        final playableItem = PlayableItem(
          videoPath: path,
          playbackSession: playbackSession,
        );
        if (!mounted) return;
        if (await ExternalPlayerService.tryHandlePlayback(
            context, playableItem)) {
          return;
        }
      }

      await widget.videoState.initializePlayer(
        path,
        playbackSession: playbackSession,
      );
      if (!mounted) return;
      BlurSnackBar.show(context, '已切换到新的播放项');
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '无法播放该条目：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _sourceIcon(),
                      size: 18,
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '播放列表 · ${_sourceName()}',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .navTitleTextStyle,
                    ),
                  ],
                ),
                if (_animeTitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _animeTitle!,
                    style: CupertinoTheme.of(context).textTheme.textStyle,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_isLoading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CupertinoActivityIndicator(radius: 16),
            ),
          )
        else if (_error != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.exclamationmark_circle, size: 40),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                CupertinoButton(
                  onPressed: _loadData,
                  child: const Text('重试'),
                ),
              ],
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final path = _episodes[index];
                final bool isCurrent = _isCurrentEpisode(path);
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: GestureDetector(
                    onTap: isCurrent ? null : () => _playEpisode(path),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isCurrent
                            ? CupertinoTheme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.12)
                            : CupertinoColors.systemGrey6.resolveFrom(context),
                        border: Border.all(
                          color: isCurrent
                              ? CupertinoTheme.of(context).primaryColor
                              : CupertinoColors.separator.resolveFrom(context),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName(path),
                            style: TextStyle(
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _subtitle(path),
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              childCount: _episodes.length,
            ),
          ),
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: widget.onBack),
        ),
      ],
    );
  }
}
