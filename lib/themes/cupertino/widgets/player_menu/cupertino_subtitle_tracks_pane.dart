import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/services/remote_subtitle_service.dart';
import 'package:nipaplay/services/subtitle_service.dart';

class CupertinoSubtitleTracksPane extends StatefulWidget {
  const CupertinoSubtitleTracksPane({
    super.key,
    required this.videoState,
    required this.onBack,
  });

  final VideoPlayerState videoState;
  final VoidCallback onBack;

  @override
  State<CupertinoSubtitleTracksPane> createState() =>
      _CupertinoSubtitleTracksPaneState();
}

class _CupertinoSubtitleTracksPaneState
    extends State<CupertinoSubtitleTracksPane> {
  final SubtitleService _subtitleService = SubtitleService();
  List<Map<String, dynamic>> _externalSubtitles = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _loadExternalSubtitles();
    }
  }

  Future<void> _loadExternalSubtitles() async {
    final path = widget.videoState.currentVideoPath;
    if (path == null || kIsWeb) return;

    setState(() => _isLoading = true);
    try {
      final subtitles = await _subtitleService.loadExternalSubtitles(path);
      if (!mounted) return;
      setState(() {
        _externalSubtitles = subtitles;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadExternalSubtitleFile() async {
    if (kIsWeb) {
      _showMessage('当前平台暂不支持加载本地字幕');
      return;
    }
    final path = widget.videoState.currentVideoPath;
    if (path == null) {
      _showMessage('请先开始播放视频再加载字幕');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final fileInfo = await _subtitleService.pickAndLoadSubtitleFile();
      if (!mounted) return;
      if (fileInfo == null) {
        setState(() => _isLoading = false);
        return;
      }

      final existingIndex =
          _externalSubtitles.indexWhere((s) => s['path'] == fileInfo['path']);
      if (existingIndex >= 0) {
        await _applyExternalSubtitle(fileInfo['path'] as String, existingIndex);
        setState(() => _isLoading = false);
        _showMessage('已切换到字幕：${fileInfo['name']}');
        return;
      }

      await _subtitleService.addExternalSubtitle(path, fileInfo);
      await _loadExternalSubtitles();
      final newIndex = _externalSubtitles.length - 1;
      if (newIndex >= 0) {
        await _applyExternalSubtitle(fileInfo['path'] as String, newIndex);
      }
      _showMessage('已加载字幕文件：${fileInfo['name']}');
    } catch (error) {
      _showMessage('加载字幕失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRemoteSubtitleFile() async {
    if (kIsWeb) {
      _showMessage('当前平台暂不支持加载远程字幕');
      return;
    }

    final videoPath = widget.videoState.currentVideoPath;
    if (videoPath == null) {
      _showMessage('请先开始播放视频再加载字幕');
      return;
    }

    try {
      setState(() => _isLoading = true);
      final candidates =
          await RemoteSubtitleService.instance.listCandidatesForVideo(videoPath);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (candidates.isEmpty) {
        _showMessage('当前远程目录未找到字幕文件');
        return;
      }

      final selected = await CupertinoBottomSheet.show<RemoteSubtitleCandidate>(
        context: context,
        title: '选择远程字幕',
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              children: candidates
                  .map(
                    (candidate) => CupertinoListTile(
                      title: Text(candidate.name),
                      subtitle: Text(candidate.sourceLabel),
                      onTap: () => Navigator.of(context).pop(candidate),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );

      if (selected == null) return;

      setState(() => _isLoading = true);
      final cachedPath =
          await RemoteSubtitleService.instance.ensureSubtitleCached(selected);
      if (!mounted) return;

      final subtitleInfo = <String, dynamic>{
        'path': cachedPath,
        'name': selected.name,
        'type': selected.extension.substring(1),
        'addTime': DateTime.now().millisecondsSinceEpoch,
        'isActive': false,
        'remoteSource': selected.sourceLabel,
        if (selected is WebDavRemoteSubtitleCandidate) ...{
          'remoteType': 'webdav',
          'remoteConn': selected.connection.name,
          'remotePath': selected.remotePath,
        },
        if (selected is SmbRemoteSubtitleCandidate) ...{
          'remoteType': 'smb',
          'remoteConn': selected.connection.name,
          'remotePath': selected.smbPath,
        },
      };

      final existingIndex =
          _externalSubtitles.indexWhere((s) => s['path'] == cachedPath);
      if (existingIndex >= 0) {
        await _applyExternalSubtitle(cachedPath, existingIndex);
        _showMessage('已切换到字幕：${selected.name}');
        return;
      }

      await _subtitleService.addExternalSubtitle(videoPath, subtitleInfo);
      await _loadExternalSubtitles();

      final newIndex =
          _externalSubtitles.indexWhere((s) => s['path'] == cachedPath);
      if (newIndex >= 0) {
        await _applyExternalSubtitle(cachedPath, newIndex);
      } else {
        widget.videoState.forceSetExternalSubtitle(cachedPath);
      }

      _showMessage('已加载远程字幕：${selected.name}');
    } catch (error) {
      _showMessage('加载远程字幕失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _applyExternalSubtitle(String filePath, int index) async {
    final path = widget.videoState.currentVideoPath;
    if (path == null) return;

    await _subtitleService.setExternalSubtitleActive(path, index, true);
    widget.videoState.forceSetExternalSubtitle(filePath);
    setState(() {});
  }

  Future<void> _switchToEmbeddedSubtitle(int trackIndex) async {
    final path = widget.videoState.currentVideoPath;
    if (path != null) {
      await _subtitleService.setExternalSubtitleActive(path, -1, false);
    }

    widget.videoState.setExternalSubtitle("");
    if (trackIndex >= 0) {
      widget.videoState.player.activeSubtitleTracks = [trackIndex];
    } else {
      widget.videoState.player.activeSubtitleTracks = [];
    }
    setState(() {});
  }

  Future<void> _removeExternalSubtitle(int index) async {
    final path = widget.videoState.currentVideoPath;
    if (path == null) return;
    if (index < 0 || index >= _externalSubtitles.length) return;

    final subtitle = _externalSubtitles[index];
    final bool isActive = subtitle['isActive'] == true;
    if (isActive) {
      await _switchToEmbeddedSubtitle(-1);
    }

    await _subtitleService.removeExternalSubtitle(path, index);
    await _loadExternalSubtitles();
    _showMessage('已移除字幕：${subtitle['name']}');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    BlurSnackBar.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final embeddedTracks = widget.videoState.player.mediaInfo.subtitle;
    final canLoadRemote = !kIsWeb &&
        widget.videoState.currentVideoPath != null &&
        RemoteSubtitleService.instance
            .isPotentialRemoteVideoPath(widget.videoState.currentVideoPath!);

    final children = <Widget>[
      CupertinoListSection.insetGrouped(
        header: const Text('字幕控制'),
        children: [
          CupertinoListTile(
            padding: const EdgeInsets.symmetric(vertical: 10),
            leading: const Icon(CupertinoIcons.multiply_circle),
            title: const Text('关闭字幕'),
            subtitle: const Text('停用所有字幕轨道'),
            trailing: widget.videoState.player.activeSubtitleTracks.isEmpty &&
                    !_externalSubtitles.any((s) => s['isActive'] == true)
                ? Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    color: CupertinoTheme.of(context).primaryColor,
                  )
                : null,
            onTap: () => _switchToEmbeddedSubtitle(-1),
          ),
        ],
      ),
    ];

    if (!kIsWeb) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: CupertinoButton.filled(
            onPressed: _isLoading ? null : _loadExternalSubtitleFile,
            child: _isLoading
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CupertinoActivityIndicator(radius: 10),
                      SizedBox(width: 8),
                      Text('加载中…'),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(CupertinoIcons.add_circled),
                      SizedBox(width: 6),
                      Text('加载本地字幕文件'),
                    ],
                  ),
          ),
        ),
      );

      if (canLoadRemote) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: CupertinoButton.filled(
              onPressed: _isLoading ? null : _loadRemoteSubtitleFile,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(CupertinoIcons.cloud_download),
                  SizedBox(width: 6),
                  Text('从远程媒体库加载字幕'),
                ],
              ),
            ),
          ),
        );
      }
    }

    if (_externalSubtitles.isNotEmpty) {
      children.add(
        CupertinoListSection.insetGrouped(
          header: const Text('外部字幕'),
          children: _externalSubtitles.asMap().entries.map((entry) {
            final index = entry.key;
            final data = entry.value;
            final bool isActive = data['isActive'] == true;
            final String name = data['name']?.toString() ?? '字幕 $index';
            final String type = data['type']?.toString().toUpperCase() ?? '';

            return CupertinoListTile(
              leading: Icon(
                isActive
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: isActive
                    ? CupertinoTheme.of(context).primaryColor
                    : CupertinoColors.inactiveGray,
              ),
              title: Text(name),
              subtitle: Text('类型：$type'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _removeExternalSubtitle(index),
                    child: const Icon(
                      CupertinoIcons.delete,
                      size: 20,
                    ),
                  ),
                ],
              ),
              onTap: () async {
                if (isActive) {
                  await _switchToEmbeddedSubtitle(-1);
                } else {
                  await _applyExternalSubtitle(
                      data['path'] as String, index);
                }
                setState(() {});
              },
            );
          }).toList(),
        ),
      );
    }

    if (embeddedTracks != null && embeddedTracks.isNotEmpty) {
      children.add(
        CupertinoListSection.insetGrouped(
          header: const Text('内嵌字幕'),
          children: embeddedTracks.asMap().entries.map((entry) {
            final index = entry.key;
            final track = entry.value;
            final bool hasExternal =
                _externalSubtitles.any((s) => s['isActive'] == true);
            final bool isActive = !hasExternal &&
                widget.videoState.player.activeSubtitleTracks.contains(index);
            final String language =
                _languageName(track.language ?? track.toString());
            final String title =
                track.title?.trim().isNotEmpty == true ? track.title! : '轨道 ${index + 1}';

            return CupertinoListTile(
              leading: Icon(
                isActive
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: isActive
                    ? CupertinoTheme.of(context).primaryColor
                    : CupertinoColors.inactiveGray,
              ),
              title: Text(title),
              subtitle: Text('语言：$language'),
              onTap: () => _switchToEmbeddedSubtitle(index),
            );
          }).toList(),
        ),
      );
    }

    final bool noSubtitles =
        _externalSubtitles.isEmpty && (embeddedTracks?.isEmpty ?? true);

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) {
        if (noSubtitles) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.textformat,
                    size: 44,
                    color:
                        CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '没有可用的字幕轨道',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .textStyle
                        .copyWith(
                          fontSize: 16,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                  ),
                  if (!kIsWeb)
                    Text(
                      '点击上方按钮加载本地字幕',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
                            fontSize: 13,
                            color: CupertinoColors.tertiaryLabel
                                .resolveFrom(context),
                          ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: CupertinoPaneBackButton(onPressed: widget.onBack),
          ),
        ];
      }

      return [
        SliverPadding(
          padding: EdgeInsets.only(top: topSpacing, bottom: 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate(children),
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: widget.onBack),
        ),
      ];
      },
    );
  }

  String _languageName(String input) {
    final String value = input.toLowerCase();
    if (value.contains('chi') || value.contains('zh')) return '中文';
    if (value.contains('eng') || value.contains('en')) return '英文';
    if (value.contains('jpn') || value.contains('ja')) return '日语';
    if (value.contains('kor') || value.contains('ko')) return '韩语';
    if (value.contains('fra') || value.contains('fr')) return '法语';
    if (value.contains('deu') || value.contains('de')) return '德语';
    if (value.contains('spa') || value.contains('es')) return '西班牙语';
    if (value.contains('ita') || value.contains('it')) return '意大利语';
    if (value.contains('rus') || value.contains('ru')) return '俄语';
    return input;
  }
}
