import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart'
    show AdaptiveButton, AdaptiveButtonStyle;
import 'package:provider/provider.dart';

import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/emby_media_source_selection.dart';
import 'package:nipaplay/services/emby_player_menu_selection.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/adaptive_player_menu_primitives.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/emby_media_source_selector.dart';

class CupertinoJellyfinQualityPane extends StatefulWidget {
  const CupertinoJellyfinQualityPane({
    super.key,
    required this.videoState,
  });

  final VideoPlayerState videoState;

  @override
  State<CupertinoJellyfinQualityPane> createState() =>
      _CupertinoJellyfinQualityPaneState();
}

class _CupertinoJellyfinQualityPaneState
    extends State<CupertinoJellyfinQualityPane> {
  JellyfinVideoQuality? _currentQuality;
  bool _isLoading = false;
  List<Map<String, dynamic>> _serverSubtitles = [];
  int? _selectedServerSubtitle;
  bool _burnIn = false;
  List<PlaybackMediaSource> _mediaSources = const [];
  String? _selectedMediaSourceId;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    try {
      final path = widget.videoState.currentVideoPath;
      if (path != null && path.startsWith('emby://')) {
        final session = widget.videoState.currentPlaybackSession;
        _mediaSources = session?.mediaSources ?? const [];
        _selectedMediaSourceId = session?.mediaSourceId;
        final provider =
            Provider.of<EmbyTranscodeProvider>(context, listen: false);
        await provider.initialize();
        if (!mounted) return;
        setState(() {
          _currentQuality = provider.currentVideoQuality;
        });
        await _loadServerSubtitles(path);
      } else {
        final provider =
            Provider.of<JellyfinTranscodeProvider>(context, listen: false);
        await provider.initialize();
        if (!mounted) return;
        setState(() {
          _currentQuality = provider.currentVideoQuality;
        });
        if (path != null) {
          await _loadServerSubtitles(path);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentQuality = JellyfinVideoQuality.bandwidth5m;
      });
    }
  }

  Future<void> _loadServerSubtitles(String path) async {
    if (path.startsWith('jellyfin://')) {
      final itemId = path.replaceFirst('jellyfin://', '');
      final tracks = await JellyfinService.instance.getSubtitleTracks(itemId);
      if (!mounted) return;
      setState(() {
        _serverSubtitles = tracks;
        final defaultTrack = tracks.firstWhere(
          (t) => t['isDefault'] == true,
          orElse: () => {},
        );
        _selectedServerSubtitle =
            defaultTrack.isEmpty ? null : defaultTrack['index'] as int?;
      });
    } else if (path.startsWith('emby://')) {
      final itemId = path.replaceFirst('emby://', '').split('/').last;
      final tracks = await EmbyService.instance.getSubtitleTracks(
        itemId,
        mediaSourceId: widget.videoState.currentPlaybackSession?.mediaSourceId,
      );
      if (!mounted) return;
      setState(() {
        _serverSubtitles = tracks;
        final defaultTrack = tracks.firstWhere(
          (t) => t['isDefault'] == true,
          orElse: () => {},
        );
        _selectedServerSubtitle =
            defaultTrack.isEmpty ? null : defaultTrack['index'] as int?;
      });
    }
  }

  Future<void> _selectMediaSource(PlaybackMediaSource source) async {
    if (_selectedMediaSourceId == source.id) return;
    setState(() {
      _selectedMediaSourceId = source.id;
      _selectedServerSubtitle = null;
      _burnIn = false;
      _serverSubtitles = [];
      _isLoading = true;
    });

    final path = widget.videoState.currentVideoPath;
    if (path != null && path.startsWith('emby://')) {
      final itemId = path.replaceFirst('emby://', '').split('/').last;
      try {
        final tracks = await EmbyService.instance
            .getSubtitleTracks(itemId, mediaSourceId: source.id);
        if (!mounted || _selectedMediaSourceId != source.id) return;
        final defaultTrack = tracks.firstWhere(
          (track) => track['isDefault'] == true,
          orElse: () => <String, dynamic>{},
        );
        setState(() {
          _serverSubtitles = tracks;
          _selectedServerSubtitle =
              defaultTrack.isEmpty ? null : defaultTrack['index'] as int?;
          _isLoading = false;
        });
      } catch (_) {
        if (!mounted || _selectedMediaSourceId != source.id) return;
        setState(() => _isLoading = false);
      }
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _applySelection() async {
    if (_currentQuality == null) return;
    setState(() => _isLoading = true);

    try {
      final videoState = widget.videoState;
      final path = videoState.currentVideoPath;
      if (path != null && path.startsWith('emby://')) {
        final provider =
            Provider.of<EmbyTranscodeProvider>(context, listen: false);
        final itemId = path.replaceFirst('emby://', '').split('/').last;
        final normalizedSourceId = _selectedMediaSourceId?.trim();
        final selectedSourceId =
            normalizedSourceId?.isNotEmpty == true ? normalizedSourceId : null;
        final sourceChanged = selectedSourceId != null &&
            videoState.currentPlaybackSession?.mediaSourceId !=
                selectedSourceId;
        final selectedSource = sourceChanged
            ? videoState.embyMediaSourceDescriptor(selectedSourceId)
            : videoState.embyMediaSourceDescriptor();
        if (sourceChanged && selectedSource == null) {
          throw StateError(
              'Selected Emby media source is no longer available.');
        }
        final resolvedTracks = sourceChanged && selectedSource != null
            ? await videoState.resolveCurrentEmbyTracksForSource(selectedSource)
            : videoState.currentEmbyTrackSelection;
        final resolvedAudioIndex =
            resolvedTracks?.audio.mode == EmbyResolvedTrackMode.track
                ? resolvedTracks!.audio.sourceIndex
                : null;
        final resolvedSubtitleIndex =
            resolvedTracks?.subtitle.mode == EmbyResolvedTrackMode.track
                ? resolvedTracks!.subtitle.sourceIndex
                : null;
        final audioStreamIndex = sourceChanged
            ? resolvedAudioIndex
            : videoState.getEmbyServerAudioSelection(itemId);
        final subtitleStreamIndex =
            sourceChanged ? resolvedSubtitleIndex : _selectedServerSubtitle;
        final burnInSubtitle = _burnIn ||
            (resolvedTracks != null &&
                requiresEmbySubtitleBurnIn(resolvedTracks.subtitle));
        await provider.setDefaultVideoQuality(_currentQuality!);
        if (_currentQuality! != JellyfinVideoQuality.original) {
          await provider.setTranscodeEnabled(true);
        }
        await runMediaServerMenuSelection(
          MediaServerMenuSurface.cupertinoSource,
          true,
          () async {
            await videoState.reloadCurrentEmbyStream(
              quality: _currentQuality!,
              serverSubtitleIndex: subtitleStreamIndex,
              burnInSubtitle: burnInSubtitle,
              mediaSourceId: selectedSourceId,
              audioStreamIndex: audioStreamIndex,
              embyTrackSelection: resolvedTracks,
            );
            videoState.setEmbyServerSubtitleSelection(
              itemId,
              subtitleStreamIndex,
              burnIn: burnInSubtitle,
            );
            if (sourceChanged) {
              videoState.setEmbyServerAudioSelection(itemId, audioStreamIndex);
            }
          },
          () async {
            if (!sourceChanged || selectedSource == null) return false;
            return videoState.persistCurrentEmbyManualPatch(
              EmbyManualSelectionPatch(source: selectedSource),
              currentSource: selectedSource,
            );
          },
        );
      } else {
        final provider =
            Provider.of<JellyfinTranscodeProvider>(context, listen: false);
        await provider.setDefaultVideoQuality(_currentQuality!);
        if (_currentQuality! != JellyfinVideoQuality.original) {
          await provider.setTranscodeEnabled(true);
        }
        await runMediaServerMenuSelection(
          MediaServerMenuSurface.cupertinoSource,
          false,
          () => videoState.reloadCurrentJellyfinStream(
            quality: _currentQuality!,
            serverSubtitleIndex: _selectedServerSubtitle,
            burnInSubtitle: _burnIn,
          ),
          () async => false,
        );
      }

      if (!mounted) return;
      BlurSnackBar.show(
        context,
        '已切换到 ${_qualityName(_currentQuality!)}',
      );
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '设置失败：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quality = _currentQuality;
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Text(
              '选择转码质量，并可指定服务器字幕',
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
            ),
          ),
        ),
        if (quality == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: AdaptivePlayerMenuProgressIndicator(size: 32),
            ),
          )
        else
          SliverList(
            delegate: SliverChildListDelegate([
              if (_mediaSources.length > 1)
                AdaptivePlayerMenuSection(
                  header: const Text('媒体源'),
                  children: [
                    for (var index = 0; index < _mediaSources.length; index++)
                      AdaptivePlayerMenuTile(
                        title: Text(
                          embyMediaSourceLabel(
                            _mediaSources[index],
                            index: index,
                          ),
                        ),
                        trailing: Icon(
                          _mediaSources[index].id == _selectedMediaSourceId
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          color:
                              _mediaSources[index].id == _selectedMediaSourceId
                                  ? CupertinoTheme.of(context).primaryColor
                                  : CupertinoColors.inactiveGray,
                        ),
                        onTap: () => _selectMediaSource(_mediaSources[index]),
                      ),
                  ],
                ),
              AdaptivePlayerMenuSection(
                header: const Text('清晰度'),
                children: JellyfinVideoQuality.values.map((option) {
                  final selected = option == quality;
                  return AdaptivePlayerMenuTile(
                    title: Text(_qualityName(option)),
                    subtitle: Text(_qualityDescription(option)),
                    trailing: Icon(
                      selected
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.circle,
                      color: selected
                          ? CupertinoTheme.of(context).primaryColor
                          : CupertinoColors.inactiveGray,
                    ),
                    onTap: () => setState(() => _currentQuality = option),
                  );
                }).toList(),
              ),
              if (_serverSubtitles.isNotEmpty)
                AdaptivePlayerMenuSection(
                  header: const Text('服务器字幕'),
                  children: [
                    ..._serverSubtitles.map((track) {
                      final index = track['index'] as int?;
                      final selected = index == _selectedServerSubtitle;
                      final name = track['display']?.toString() ??
                          track['title']?.toString() ??
                          '字幕 $index';
                      return AdaptivePlayerMenuTile(
                        title: Text(name),
                        trailing: Icon(
                          selected
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          color: selected
                              ? CupertinoTheme.of(context).primaryColor
                              : CupertinoColors.inactiveGray,
                        ),
                        onTap: () {
                          setState(() => _selectedServerSubtitle = index);
                        },
                      );
                    }),
                    AdaptivePlayerMenuTile(
                      title: const Text('烧录字幕'),
                      subtitle: const Text('转码时将字幕写入画面'),
                      trailing: AdaptivePlayerMenuSwitch(
                        value: _burnIn,
                        onChanged: (value) => setState(() => _burnIn = value),
                      ),
                      onTap: () => setState(() => _burnIn = !_burnIn),
                    ),
                  ],
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: AdaptiveButton.child(
                  style: AdaptiveButtonStyle.prominentGlass,
                  onPressed: _isLoading ? null : _applySelection,
                  child: _isLoading
                      ? const AdaptivePlayerMenuProgressIndicator()
                      : const Text('应用设置'),
                ),
              ),
              const SizedBox(height: 12),
            ]),
          ),
      ],
    );
  }

  String _qualityName(JellyfinVideoQuality quality) {
    switch (quality) {
      case JellyfinVideoQuality.auto:
        return '自动 (AUTO)';
      case JellyfinVideoQuality.original:
        return '原画 (不转码)';
      case JellyfinVideoQuality.bandwidth40m:
        return '4K (40 Mbps)';
      case JellyfinVideoQuality.bandwidth20m:
        return '超清 (20 Mbps)';
      case JellyfinVideoQuality.bandwidth10m:
        return '全高清 (10 Mbps)';
      case JellyfinVideoQuality.bandwidth5m:
        return '高清 (5 Mbps)';
      case JellyfinVideoQuality.bandwidth2m:
        return '标清 (2 Mbps)';
      case JellyfinVideoQuality.bandwidth1m:
        return '省流 (1 Mbps)';
    }
  }

  String _qualityDescription(JellyfinVideoQuality quality) {
    switch (quality) {
      case JellyfinVideoQuality.auto:
        return '根据网络状况自动选择';
      case JellyfinVideoQuality.original:
        return '使用原始文件，不启用转码';
      case JellyfinVideoQuality.bandwidth40m:
        return '4K 画质，网络要求极高';
      case JellyfinVideoQuality.bandwidth20m:
        return '1080p 超清，网络要求较高';
      case JellyfinVideoQuality.bandwidth10m:
        return '1080p 全高清，网络要求适中';
      case JellyfinVideoQuality.bandwidth5m:
        return '720p 高清，默认推荐';
      case JellyfinVideoQuality.bandwidth2m:
        return '480p 标清，兼顾画质与流畅';
      case JellyfinVideoQuality.bandwidth1m:
        return '360p 低清，最省流量';
    }
  }
}
