import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/models/dandanplay_remote_model.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/dandanplay_remote_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/media_path_name.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/shared_remote_history_helper.dart';
import 'package:nipaplay/utils/webdav_file_sorter.dart';

class PlaybackSourceService {
  const PlaybackSourceService._();

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

  static Future<PlaybackDetailContext> resolve(
    BuildContext context,
    PlayableItem item,
  ) async {
    final supplied = item.detailContext;
    if (supplied != null) return supplied;

    final path = item.videoPath;
    final animeId = item.animeId ?? item.historyItem?.animeId;

    try {
      if (_isDandanplayRemotePath(path)) {
        return await _resolveDandanplayRemote(item);
      }
      if (_isSharedRemoteManagementStreamUrl(path)) {
        final provider = context.read<SharedRemoteLibraryProvider>();
        await _activateSharedHostForPath(provider, path);
        if (animeId != null && animeId > 0) {
          return _resolveSharedAnime(provider, item, animeId);
        }
        return _resolveSharedDirectory(provider, item);
      }

      if (SharedRemoteHistoryHelper.isSharedRemoteStreamPath(path)) {
        final provider = context.read<SharedRemoteLibraryProvider>();
        await _activateSharedHostForPath(provider, path);
        if (animeId != null && animeId > 0) {
          return _resolveSharedAnime(provider, item, animeId);
        }
        return _singleItemContext(
          item,
          kind: PlaybackSourceKind.sharedRemoteDirectory,
          sourceLabel: provider.activeHost?.displayName ?? '共享媒体库',
        );
      }

      if (path.startsWith('jellyfin://')) {
        return await _resolveJellyfin(item);
      }
      if (path.startsWith('emby://')) {
        return await _resolveEmby(item);
      }
      if (_isSmbProxyStreamUrl(path)) {
        return await _resolveSmb(item);
      }
      if (MediaSourceUtils.isWebDavPath(path)) {
        return await _resolveWebDav(item);
      }
      if (_isNetworkPath(path)) {
        return _singleItemContext(
          item,
          kind: PlaybackSourceKind.networkStream,
          sourceLabel: '网络媒体',
        );
      }
      return _resolveLocal(item);
    } catch (error, stackTrace) {
      debugPrint('[PlaybackSource] 解析播放来源失败，使用基础上下文: $error');
      debugPrintStack(stackTrace: stackTrace);
      return fallback(item);
    }
  }

  static PlaybackDetailContext fallback(PlayableItem item) {
    final path = item.videoPath;
    final animeId = item.animeId ?? item.historyItem?.animeId;
    final kind = sourceKindForPath(path, animeId: animeId);
    final title = _resolvedTitle(item);
    final identified = (animeId != null && animeId > 0) ||
        kind == PlaybackSourceKind.jellyfin ||
        kind == PlaybackSourceKind.emby ||
        kind == PlaybackSourceKind.sharedRemoteAnime;

    return PlaybackDetailContext(
      sourceKind: kind,
      sourceLabel: _defaultSourceLabel(kind),
      sourceKey: _sourceKey(path, kind),
      title: title,
      subtitle: item.subtitle ?? item.historyItem?.episodeTitle,
      imageUrl: item.historyItem?.thumbnailPath,
      animeId: animeId,
      isIdentified: identified,
      episodeLoader: () async {
        if ((kind == PlaybackSourceKind.localFile ||
                kind == PlaybackSourceKind.localLibrary) &&
            !kIsWeb) {
          return _loadLocalEpisodes(item);
        }
        return <PlaybackDetailEpisode>[_episodeFromItem(item)];
      },
    );
  }

  static PlaybackSourceKind sourceKindForPath(
    String path, {
    int? animeId,
  }) {
    if (_isDandanplayRemotePath(path)) {
      return PlaybackSourceKind.dandanplayRemote;
    }
    if (_isSharedRemoteManagementStreamUrl(path)) {
      return animeId != null && animeId > 0
          ? PlaybackSourceKind.sharedRemoteAnime
          : PlaybackSourceKind.sharedRemoteDirectory;
    }
    if (SharedRemoteHistoryHelper.isSharedRemoteStreamPath(path)) {
      return animeId != null && animeId > 0
          ? PlaybackSourceKind.sharedRemoteAnime
          : PlaybackSourceKind.sharedRemoteDirectory;
    }
    if (path.startsWith('jellyfin://')) return PlaybackSourceKind.jellyfin;
    if (path.startsWith('emby://')) return PlaybackSourceKind.emby;
    if (_isSmbProxyStreamUrl(path)) return PlaybackSourceKind.smb;
    if (MediaSourceUtils.isWebDavPath(path)) return PlaybackSourceKind.webDav;
    if (_isNetworkPath(path)) return PlaybackSourceKind.networkStream;
    return animeId != null && animeId > 0
        ? PlaybackSourceKind.localLibrary
        : PlaybackSourceKind.localFile;
  }

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

  static PlaybackDetailContext _resolveSharedAnime(
    SharedRemoteLibraryProvider provider,
    PlayableItem item,
    int animeId,
  ) {
    final summary = _sharedSummary(provider, item, animeId);
    final sourceLabel = provider.activeHost?.displayName ?? '共享媒体库';

    Future<List<PlaybackDetailEpisode>> loadEpisodes() async {
      try {
        final episodes = await provider.loadAnimeEpisodes(animeId);
        final sorted = List<SharedRemoteEpisode>.from(episodes)
          ..sort((a, b) {
            final idCompare = (a.episodeId ?? 0).compareTo(b.episodeId ?? 0);
            return idCompare != 0
                ? idCompare
                : WebDAVFileSorter.naturalCompare(a.title, b.title);
          });
        final playable = sorted
            .where((episode) =>
                episode.fileExists && episode.streamPath.trim().isNotEmpty)
            .map((episode) => _sharedEpisode(provider, summary, episode))
            .toList();
        if (playable.isNotEmpty) return playable;
      } catch (error) {
        debugPrint('[PlaybackSource] 共享番剧剧集加载失败: $error');
      }

      if (_isSharedRemoteManagementStreamUrl(item.videoPath)) {
        return _loadSharedDirectoryEpisodes(provider, item.videoPath);
      }
      return <PlaybackDetailEpisode>[_episodeFromItem(item)];
    }

    return PlaybackDetailContext(
      sourceKind: PlaybackSourceKind.sharedRemoteAnime,
      sourceLabel: sourceLabel,
      sourceKey: 'shared:${provider.activeHostId}:anime:$animeId',
      title: _firstNonEmpty(<String?>[
        summary.nameCn,
        summary.name,
        item.title,
        item.historyItem?.animeName,
      ])!,
      subtitle: summary.name,
      summary: summary.summary,
      imageUrl: summary.imageUrl ?? item.historyItem?.thumbnailPath,
      animeId: animeId,
      isIdentified: true,
      episodeLoader: loadEpisodes,
    );
  }

  static SharedRemoteAnimeSummary _sharedSummary(
    SharedRemoteLibraryProvider provider,
    PlayableItem item,
    int animeId,
  ) {
    for (final summary in provider.animeSummaries) {
      if (summary.animeId == animeId) return summary;
    }
    final title = _resolvedTitle(item);
    return SharedRemoteAnimeSummary(
      animeId: animeId,
      name: title,
      nameCn: title,
      summary: null,
      imageUrl: item.historyItem?.thumbnailPath,
      lastWatchTime: item.historyItem?.lastWatchTime ?? DateTime.now(),
      episodeCount: 0,
      hasMissingFiles: false,
    );
  }

  static PlaybackDetailEpisode _sharedEpisode(
    SharedRemoteLibraryProvider provider,
    SharedRemoteAnimeSummary anime,
    SharedRemoteEpisode episode,
  ) {
    final playable = provider.buildPlayableItem(anime: anime, episode: episode);
    return PlaybackDetailEpisode(
      id: episode.shareId.isNotEmpty
          ? episode.shareId
          : '${episode.episodeId ?? playable.videoPath.hashCode}',
      videoPath: playable.videoPath,
      title: episode.title.trim().isNotEmpty
          ? episode.title.trim()
          : p.basenameWithoutExtension(episode.fileName),
      subtitle: playable.title,
      animeId: playable.animeId,
      episodeId: playable.episodeId,
      historyItem: playable.historyItem,
      actualPlayUrl: playable.actualPlayUrl,
      playbackSession: playable.playbackSession,
      progress: episode.progress,
    );
  }

  static PlaybackDetailContext _resolveSharedDirectory(
    SharedRemoteLibraryProvider provider,
    PlayableItem item,
  ) {
    return PlaybackDetailContext(
      sourceKind: PlaybackSourceKind.sharedRemoteDirectory,
      sourceLabel: provider.activeHost?.displayName ?? '共享媒体库',
      sourceKey: _sourceKey(
        item.videoPath,
        PlaybackSourceKind.sharedRemoteDirectory,
      ),
      title: _resolvedTitle(item),
      subtitle: item.subtitle ?? item.historyItem?.episodeTitle,
      imageUrl: item.historyItem?.thumbnailPath,
      animeId: null,
      isIdentified: false,
      episodeLoader: () =>
          _loadSharedDirectoryEpisodes(provider, item.videoPath),
    );
  }

  static Future<List<PlaybackDetailEpisode>> _loadSharedDirectoryEpisodes(
    SharedRemoteLibraryProvider provider,
    String currentPath,
  ) async {
    final uri = Uri.parse(currentPath);
    final rawPath = uri.queryParameters['path']?.trim();
    if (rawPath == null || rawPath.isEmpty) {
      throw Exception('共享文件路径缺失');
    }
    await _activateSharedHostForPath(provider, currentPath);
    final entries = await provider.browseRemoteDirectory(
      _normalizeRemoteDirectoryPath(p.posix.dirname(rawPath)),
    );
    final playableEntries = entries
        .where((entry) =>
            !entry.isDirectory && provider.isRemoteFilePlayable(entry))
        .toList()
      ..sort((a, b) => WebDAVFileSorter.naturalCompare(a.name, b.name));

    return playableEntries.map((entry) {
      final streamUrl =
          provider.buildRemoteFileStreamUri(entry.path).toString();
      final fileName =
          entry.name.trim().isNotEmpty ? entry.name : p.basename(entry.path);
      final title = p.basenameWithoutExtension(fileName);
      final animeName = _firstNonEmpty(<String?>[entry.animeName, title])!;
      final history = WatchHistoryItem(
        filePath: streamUrl,
        animeName: animeName,
        episodeTitle: entry.episodeTitle,
        animeId: entry.animeId,
        episodeId: entry.episodeId,
        watchProgress: 0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
        isFromScan: entry.isFromScan ?? false,
      );
      return PlaybackDetailEpisode(
        id: entry.path,
        videoPath: streamUrl,
        title: entry.episodeTitle?.trim().isNotEmpty == true
            ? entry.episodeTitle!.trim()
            : title,
        subtitle: entry.animeName,
        animeId: entry.animeId,
        episodeId: entry.episodeId,
        historyItem: history,
        actualPlayUrl: streamUrl,
      );
    }).toList();
  }

  static Future<PlaybackDetailContext> _resolveDandanplayRemote(
    PlayableItem item,
  ) async {
    final service = DandanplayRemoteService.instance;
    var library = service.cachedEpisodes;
    if (library.isEmpty && service.isConnected) {
      library = await service.refreshLibrary(force: true);
    }

    final animeId = item.animeId ?? item.historyItem?.animeId;
    final currentHash = item.historyItem?.videoHash;
    DandanplayRemoteEpisode? current;
    for (final episode in library) {
      final streamUrl = service.buildEpisodeStreamUrl(
        hash: episode.hash.isNotEmpty ? episode.hash : null,
        entryId: episode.entryId.isNotEmpty ? episode.entryId : null,
      );
      if (streamUrl == item.videoPath ||
          (currentHash?.isNotEmpty == true && episode.hash == currentHash)) {
        current = episode;
        break;
      }
    }

    final resolvedAnimeId = animeId ?? current?.animeId;
    final resolvedTitle = _firstNonEmpty(<String?>[
      current?.animeTitle,
      item.title,
      item.historyItem?.animeName,
      p.basenameWithoutExtension(_pathName(item.videoPath)),
    ])!;
    final group = library.where((episode) {
      if (resolvedAnimeId != null) return episode.animeId == resolvedAnimeId;
      return episode.animeTitle.trim().toLowerCase() ==
          resolvedTitle.trim().toLowerCase();
    }).toList()
      ..sort((a, b) {
        final idCompare = (a.episodeId ?? 0).compareTo(b.episodeId ?? 0);
        return idCompare != 0
            ? idCompare
            : WebDAVFileSorter.naturalCompare(a.name, b.name);
      });

    final mapped = group
        .map((episode) => _dandanplayEpisode(service, episode))
        .whereType<PlaybackDetailEpisode>()
        .toList();
    String? imageHash;
    if (current?.hash.isNotEmpty == true) {
      imageHash = current!.hash;
    } else {
      for (final episode in group) {
        if (episode.hash.isNotEmpty) {
          imageHash = episode.hash;
          break;
        }
      }
    }

    return PlaybackDetailContext(
      sourceKind: PlaybackSourceKind.dandanplayRemote,
      sourceLabel: service.serverUrl ?? '弹弹play远程媒体库',
      sourceKey: 'dandanplay:${resolvedAnimeId ?? resolvedTitle.toLowerCase()}',
      title: resolvedTitle,
      subtitle: current?.episodeTitle ?? item.historyItem?.episodeTitle,
      imageUrl: imageHash == null
          ? item.historyItem?.thumbnailPath
          : service.buildImageUrl(imageHash),
      animeId: resolvedAnimeId,
      isIdentified: resolvedAnimeId != null && resolvedAnimeId > 0,
      episodeLoader: () async => mapped.isEmpty
          ? <PlaybackDetailEpisode>[_episodeFromItem(item)]
          : mapped,
    );
  }

  static PlaybackDetailEpisode? _dandanplayEpisode(
    DandanplayRemoteService service,
    DandanplayRemoteEpisode episode,
  ) {
    final streamUrl = service.buildEpisodeStreamUrl(
      hash: episode.hash.isNotEmpty ? episode.hash : null,
      entryId: episode.entryId.isNotEmpty ? episode.entryId : null,
    );
    if (streamUrl == null || streamUrl.isEmpty) return null;
    final resolvedEpisodeId = episode.episodeId ??
        (episode.entryId.isNotEmpty
            ? episode.entryId.hashCode
            : (episode.hash.isNotEmpty
                ? episode.hash.hashCode
                : episode.name.hashCode));
    final title = _firstNonEmpty(<String?>[
      episode.episodeTitle,
      episode.name,
    ])!;
    final history = WatchHistoryItem(
      filePath: streamUrl,
      animeName: _firstNonEmpty(<String?>[
        episode.animeTitle,
        episode.name,
      ])!,
      episodeTitle: title,
      episodeId: resolvedEpisodeId,
      animeId: episode.animeId,
      watchProgress: 0,
      lastPosition: 0,
      duration: episode.duration ?? 0,
      lastWatchTime: episode.lastPlay ?? episode.created ?? DateTime.now(),
      isFromScan: false,
      videoHash: episode.hash.isNotEmpty ? episode.hash : null,
    );
    return PlaybackDetailEpisode(
      id: episode.entryId.isNotEmpty ? episode.entryId : streamUrl,
      videoPath: streamUrl,
      title: title,
      subtitle: episode.animeTitle,
      animeId: episode.animeId,
      episodeId: resolvedEpisodeId,
      historyItem: history,
      actualPlayUrl: streamUrl,
    );
  }

  static Future<PlaybackDetailContext> _resolveJellyfin(
    PlayableItem item,
  ) async {
    final service = JellyfinService.instance;
    final episodeId = item.videoPath.replaceFirst('jellyfin://', '');
    final info = await service.getEpisodeDetails(episodeId);
    if (info == null || info.seriesId == null || info.seasonId == null) {
      throw Exception('无法获取 Jellyfin 剧集来源');
    }
    final title = _firstNonEmpty(<String?>[
      info.seriesName,
      item.title,
      item.historyItem?.animeName,
    ])!;
    String? imageUrl;
    try {
      imageUrl = service.getImageUrl(info.seriesId!, width: 480);
    } catch (_) {
      imageUrl = item.historyItem?.thumbnailPath;
    }

    return PlaybackDetailContext(
      sourceKind: PlaybackSourceKind.jellyfin,
      sourceLabel: 'Jellyfin',
      sourceKey: 'jellyfin:${info.seriesId}:${info.seasonId}',
      title: title,
      subtitle: info.seasonName,
      summary: info.overview,
      imageUrl: imageUrl,
      animeId: item.animeId ?? item.historyItem?.animeId,
      isIdentified: true,
      episodeLoader: () async {
        final episodes = await service.getSeasonEpisodes(
          info.seriesId!,
          info.seasonId!,
        );
        return episodes.map((episode) {
          final history = episode.toWatchHistoryItem();
          return PlaybackDetailEpisode(
            id: episode.id,
            videoPath: 'jellyfin://${episode.id}',
            title: episode.name,
            subtitle: episode.seriesName,
            historyItem: history,
          );
        }).toList();
      },
    );
  }

  static Future<PlaybackDetailContext> _resolveEmby(PlayableItem item) async {
    final service = EmbyService.instance;
    final rawPath = item.videoPath.replaceFirst('emby://', '');
    final episodeId = rawPath.split('/').last;
    final info = await service.getEpisodeDetails(episodeId);
    if (info == null || info.seriesId == null || info.seasonId == null) {
      throw Exception('无法获取 Emby 剧集来源');
    }
    final title = _firstNonEmpty(<String?>[
      info.seriesName,
      item.title,
      item.historyItem?.animeName,
    ])!;
    final imageUrl = service.getImageUrl(info.seriesId!, width: 480);

    return PlaybackDetailContext(
      sourceKind: PlaybackSourceKind.emby,
      sourceLabel: 'Emby',
      sourceKey: 'emby:${info.seriesId}:${info.seasonId}',
      title: title,
      subtitle: info.seasonName,
      summary: info.overview,
      imageUrl: imageUrl.isEmpty ? item.historyItem?.thumbnailPath : imageUrl,
      animeId: item.animeId ?? item.historyItem?.animeId,
      isIdentified: true,
      episodeLoader: () async {
        final episodes = await service.getSeasonEpisodes(
          info.seriesId!,
          info.seasonId!,
        );
        return episodes.map((episode) {
          final history = episode.toWatchHistoryItem();
          return PlaybackDetailEpisode(
            id: episode.id,
            videoPath: 'emby://${episode.id}',
            title: episode.name,
            subtitle: episode.seriesName,
            historyItem: history,
          );
        }).toList();
      },
    );
  }

  static Future<PlaybackDetailContext> _resolveWebDav(
    PlayableItem item,
  ) async {
    await WebDAVService.instance.initialize();
    final resolved = WebDAVService.instance.resolveFileUrl(item.videoPath);
    if (resolved == null) throw Exception('无法识别 WebDAV 连接');
    final animeId = item.animeId ?? item.historyItem?.animeId;

    return PlaybackDetailContext(
      sourceKind: PlaybackSourceKind.webDav,
      sourceLabel: resolved.connection.name,
      sourceKey:
          'webdav:${resolved.connection.name}:${p.posix.dirname(resolved.relativePath)}',
      title: _resolvedTitle(item),
      subtitle: item.subtitle ?? item.historyItem?.episodeTitle,
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
      ..sort((a, b) => WebDAVFileSorter.naturalCompare(a.name, b.name));

    return videos.map((entry) {
      final url = WebDAVService.instance.getFileUrl(
        resolved.connection,
        entry.path,
      );
      final title = p.basenameWithoutExtension(entry.name);
      final history = WatchHistoryItem(
        filePath: url,
        animeName: title,
        episodeTitle: entry.name,
        watchProgress: 0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
      );
      return PlaybackDetailEpisode(
        id: entry.path,
        videoPath: url,
        title: title,
        subtitle: resolved.connection.name,
        historyItem: history,
        actualPlayUrl: url,
      );
    }).toList();
  }

  static String _webDavParentDirectory(WebDAVResolvedFile resolved) {
    final connectionUri = Uri.parse(resolved.connection.url);
    final basePath = connectionUri.path.isEmpty ? '/' : connectionUri.path;
    final normalizedBase = basePath.endsWith('/') ? basePath : '$basePath/';
    final filePath = resolved.relativePath.startsWith('/')
        ? resolved.relativePath
        : '/${resolved.relativePath}';
    if (filePath.length > normalizedBase.length &&
        filePath.startsWith(normalizedBase)) {
      final relative = filePath.substring(normalizedBase.length);
      return _normalizeRemoteDirectoryPath(p.posix.dirname(relative));
    }
    return _normalizeRemoteDirectoryPath(
        p.posix.dirname(resolved.relativePath));
  }

  static Future<PlaybackDetailContext> _resolveSmb(PlayableItem item) async {
    final uri = Uri.parse(item.videoPath);
    final connectionName = uri.queryParameters['conn']?.trim();
    final smbPath = uri.queryParameters['path']?.trim();
    if (connectionName == null ||
        connectionName.isEmpty ||
        smbPath == null ||
        smbPath.isEmpty) {
      throw Exception('SMB 地址缺少必要参数');
    }
    await SMBService.instance.initialize();
    await SMBProxyService.instance.initialize();
    final connection = _findSmbConnection(connectionName);
    if (connection == null) throw Exception('找不到 SMB 连接：$connectionName');
    final animeId = item.animeId ?? item.historyItem?.animeId;

    return PlaybackDetailContext(
      sourceKind: PlaybackSourceKind.smb,
      sourceLabel: connection.name,
      sourceKey: 'smb:${connection.name}:${_smbParent(smbPath)}',
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
      ..sort((a, b) => WebDAVFileSorter.naturalCompare(a.name, b.name));

    return videos.map((entry) {
      final url =
          SMBProxyService.instance.buildStreamUrl(connection, entry.path);
      final title = p.basenameWithoutExtension(entry.name);
      final history = WatchHistoryItem(
        filePath: url,
        animeName: title,
        episodeTitle: entry.name,
        watchProgress: 0,
        lastPosition: 0,
        duration: 0,
        lastWatchTime: DateTime.now(),
      );
      return PlaybackDetailEpisode(
        id: entry.path,
        videoPath: url,
        title: title,
        subtitle: connection.name,
        historyItem: history,
        actualPlayUrl: url,
      );
    }).toList();
  }

  static Future<List<PlaybackDetailEpisode>> _loadLocalEpisodes(
    PlayableItem current,
  ) async {
    if (kIsWeb) return <PlaybackDetailEpisode>[_episodeFromItem(current)];
    final directory = File(current.videoPath).parent;
    if (!directory.existsSync()) {
      return <PlaybackDetailEpisode>[_episodeFromItem(current)];
    }
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => _videoExtensions.any(
              (extension) => file.path.toLowerCase().endsWith(extension),
            ))
        .toList()
      ..sort((a, b) => WebDAVFileSorter.naturalCompare(
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
    );
  }

  static Future<void> _activateSharedHostForPath(
    SharedRemoteLibraryProvider provider,
    String path,
  ) async {
    final uri = Uri.tryParse(path);
    if (uri == null) return;
    for (final host in provider.hosts) {
      final hostUri = Uri.tryParse(host.baseUrl);
      if (hostUri == null ||
          hostUri.scheme != uri.scheme ||
          hostUri.host != uri.host ||
          _effectivePort(hostUri) != _effectivePort(uri)) {
        continue;
      }
      final basePath = _normalizeBasePath(hostUri.path);
      if (basePath != '/' && !uri.path.startsWith('$basePath/')) continue;
      if (provider.activeHostId != host.id) {
        await provider.setActiveHost(host.id);
      }
      return;
    }
  }

  static SMBConnection? _findSmbConnection(String name) {
    final direct = SMBService.instance.getConnection(name);
    if (direct != null) return direct;
    final matches = SMBService.instance.connections.where((connection) {
      return connection.host == name ||
          '${connection.host}:${connection.port}' == name;
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

  static bool _isSharedRemoteManagementStreamUrl(String path) {
    final uri = Uri.tryParse(path);
    return uri != null &&
        uri.path.endsWith('/api/media/local/manage/stream') &&
        (uri.queryParameters['path']?.trim().isNotEmpty ?? false);
  }

  static bool _isSmbProxyStreamUrl(String path) {
    final uri = Uri.tryParse(path);
    return uri != null &&
        uri.path == '/smb/stream' &&
        (uri.queryParameters['conn']?.trim().isNotEmpty ?? false) &&
        (uri.queryParameters['path']?.trim().isNotEmpty ?? false);
  }

  static bool _isNetworkPath(String path) {
    final lower = path.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static bool _isDandanplayRemotePath(String path) {
    final lower = path.toLowerCase();
    return lower.startsWith('dandanplay://') ||
        lower.contains('/api/v1/stream/');
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

  static String _defaultSourceLabel(PlaybackSourceKind kind) {
    switch (kind) {
      case PlaybackSourceKind.localLibrary:
        return '本地媒体库';
      case PlaybackSourceKind.localFile:
        return '本地文件';
      case PlaybackSourceKind.sharedRemoteAnime:
      case PlaybackSourceKind.sharedRemoteDirectory:
        return '共享媒体库';
      case PlaybackSourceKind.webDav:
        return 'WebDAV';
      case PlaybackSourceKind.smb:
        return 'SMB';
      case PlaybackSourceKind.dandanplayRemote:
        return '弹弹play远程媒体库';
      case PlaybackSourceKind.jellyfin:
        return 'Jellyfin';
      case PlaybackSourceKind.emby:
        return 'Emby';
      case PlaybackSourceKind.networkStream:
        return '网络媒体';
    }
  }

  static String _sourceKey(String path, PlaybackSourceKind kind) {
    final uri = Uri.tryParse(path);
    switch (kind) {
      case PlaybackSourceKind.localLibrary:
      case PlaybackSourceKind.localFile:
        return 'local:${p.dirname(path)}';
      case PlaybackSourceKind.sharedRemoteDirectory:
        final remotePath = uri?.queryParameters['path'];
        return 'shared-directory:${uri?.host}:${p.posix.dirname(remotePath ?? uri?.path ?? path)}';
      case PlaybackSourceKind.smb:
        return 'smb:${uri?.queryParameters['conn']}:${_smbParent(uri?.queryParameters['path'] ?? '')}';
      case PlaybackSourceKind.dandanplayRemote:
        return 'dandanplay:${uri?.host}';
      case PlaybackSourceKind.webDav:
        return 'webdav:${uri?.host}:${p.posix.dirname(uri?.path ?? path)}';
      case PlaybackSourceKind.jellyfin:
        return 'jellyfin';
      case PlaybackSourceKind.emby:
        return 'emby';
      case PlaybackSourceKind.sharedRemoteAnime:
        return 'shared-anime:${uri?.host}';
      case PlaybackSourceKind.networkStream:
        return 'network:${uri?.host}:${p.posix.dirname(uri?.path ?? path)}';
    }
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    if (uri.scheme == 'https') return 443;
    if (uri.scheme == 'http') return 80;
    return 0;
  }

  static String _normalizeBasePath(String path) {
    var normalized = path.trim();
    if (normalized.isEmpty) return '/';
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String _normalizeRemoteDirectoryPath(String path) {
    final trimmed = path.trim();
    return trimmed.isEmpty || trimmed == '.' ? '/' : trimmed;
  }
}
