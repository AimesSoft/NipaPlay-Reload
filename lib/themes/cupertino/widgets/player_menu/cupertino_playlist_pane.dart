import 'dart:io';

import 'package:flutter/cupertino.dart';

import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/video_player_state.dart';

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
      final aIndex =
          (a.indexNumber == null || a.indexNumber == 0) ? 999999 : a.indexNumber!;
      final bIndex =
          (b.indexNumber == null || b.indexNumber == 0) ? 999999 : b.indexNumber!;
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
      final aIndex =
          (a.indexNumber == null || a.indexNumber == 0) ? 999999 : a.indexNumber!;
      final bIndex =
          (b.indexNumber == null || b.indexNumber == 0) ? 999999 : b.indexNumber!;
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
        return path.split('/').last;
    }
  }

  String _subtitle(String path) {
    switch (_dataSourceType) {
      case 'jellyfin':
        final id = path.replaceFirst('jellyfin://', '');
        return _jellyfinCache[id]?['seriesName'] ?? 'Jellyfin';
      case 'emby':
        final id = path.replaceFirst('emby://', '');
        return _embyCache[id]?['seriesName'] ?? 'Emby';
      default:
        return path;
    }
  }

  IconData _sourceIcon() {
    switch (_dataSourceType) {
      case 'jellyfin':
      case 'emby':
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
      default:
        return '本地文件';
    }
  }

  Future<void> _playEpisode(String path) async {
    try {
      await widget.videoState.initializePlayer(path);
      BlurSnackBar.show(context, '已切换到新的播放项');
    } catch (e) {
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
                      color: CupertinoColors.secondaryLabel
                          .resolveFrom(context),
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
                  child: const Text('重试'),
                  onPressed: _loadData,
                ),
              ],
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final path = _episodes[index];
                final bool isCurrent = path == _currentPath;
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
                                .withOpacity(0.12)
                            : CupertinoColors.systemGrey6
                                .resolveFrom(context),
                        border: Border.all(
                          color: isCurrent
                              ? CupertinoTheme.of(context).primaryColor
                              : CupertinoColors.separator
                                  .resolveFrom(context),
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
