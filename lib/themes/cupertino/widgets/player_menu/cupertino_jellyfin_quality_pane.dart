import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/video_player_state.dart';

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

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    try {
      final path = widget.videoState.currentVideoPath;
      if (path != null && path.startsWith('emby://')) {
        final provider =
            Provider.of<EmbyTranscodeProvider>(context, listen: false);
        await provider.initialize();
        setState(() {
          _currentQuality = provider.currentVideoQuality;
        });
        await _loadServerSubtitles(path);
      } else {
        final provider =
            Provider.of<JellyfinTranscodeProvider>(context, listen: false);
        await provider.initialize();
        setState(() {
          _currentQuality = provider.currentVideoQuality;
        });
        if (path != null) {
          await _loadServerSubtitles(path);
        }
      }
    } catch (e) {
      setState(() {
        _currentQuality = JellyfinVideoQuality.bandwidth5m;
      });
    }
  }

  Future<void> _loadServerSubtitles(String path) async {
    if (path.startsWith('jellyfin://')) {
      final itemId = path.replaceFirst('jellyfin://', '');
      final tracks = await JellyfinService.instance.getSubtitleTracks(itemId);
      setState(() {
        _serverSubtitles = tracks;
        final defaultTrack = tracks.firstWhere(
          (t) => t['isDefault'] == true,
          orElse: () => {},
        );
        _selectedServerSubtitle = defaultTrack.isEmpty
            ? null
            : defaultTrack['index'] as int?;
      });
    } else if (path.startsWith('emby://')) {
      final itemId = path.replaceFirst('emby://', '');
      final tracks = await EmbyService.instance.getSubtitleTracks(itemId);
      setState(() {
        _serverSubtitles = tracks;
        final defaultTrack = tracks.firstWhere(
          (t) => t['isDefault'] == true,
          orElse: () => {},
        );
        _selectedServerSubtitle = defaultTrack.isEmpty
            ? null
            : defaultTrack['index'] as int?;
      });
    }
  }

  Future<void> _applySelection() async {
    if (_currentQuality == null) return;
    setState(() => _isLoading = true);

    try {
      final path = widget.videoState.currentVideoPath;
      if (path != null && path.startsWith('emby://')) {
        final provider =
            Provider.of<EmbyTranscodeProvider>(context, listen: false);
        await provider.setDefaultVideoQuality(_currentQuality!);
        if (_currentQuality! != JellyfinVideoQuality.original) {
          await provider.setTranscodeEnabled(true);
        }
        await widget.videoState.reloadCurrentEmbyStream(
          quality: _currentQuality!,
          serverSubtitleIndex: _selectedServerSubtitle,
          burnInSubtitle: _burnIn,
        );
      } else {
        final provider =
            Provider.of<JellyfinTranscodeProvider>(context, listen: false);
        await provider.setDefaultVideoQuality(_currentQuality!);
        if (_currentQuality! != JellyfinVideoQuality.original) {
          await provider.setTranscodeEnabled(true);
        }
        await widget.videoState.reloadCurrentJellyfinStream(
          quality: _currentQuality!,
          serverSubtitleIndex: _selectedServerSubtitle,
          burnInSubtitle: _burnIn,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '清晰度与字幕',
                  style:
                      CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
                const SizedBox(height: 4),
                Text(
                  '选择转码质量，并可指定服务器字幕',
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context),
                      ),
                ),
              ],
            ),
          ),
        ),
        if (quality == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CupertinoActivityIndicator(radius: 16),
            ),
          )
        else
          SliverList(
            delegate: SliverChildListDelegate([
              CupertinoListSection.insetGrouped(
                header: const Text('清晰度'),
                children: JellyfinVideoQuality.values.map((option) {
                  final selected = option == quality;
                  return CupertinoListTile(
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
                CupertinoListSection.insetGrouped(
                  header: const Text('服务器字幕'),
                  children: [
                    ..._serverSubtitles.map((track) {
                      final index = track['index'] as int?;
                      final selected = index == _selectedServerSubtitle;
                      final name = track['display']?.toString() ??
                          track['title']?.toString() ??
                          '字幕 $index';
                      return CupertinoListTile(
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
                    CupertinoListTile(
                      title: const Text('烧录字幕'),
                      subtitle: const Text('转码时将字幕写入画面'),
                      trailing: CupertinoSwitch(
                        value: _burnIn,
                        onChanged: (value) => setState(() => _burnIn = value),
                      ),
                    ),
                  ],
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: CupertinoButton.filled(
                  onPressed: _isLoading ? null : _applySelection,
                  child: _isLoading
                      ? const CupertinoActivityIndicator()
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
