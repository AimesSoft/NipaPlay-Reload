import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'player_menu_theme.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/utils/local_danmaku_file.dart';
import 'package:file_selector/file_selector.dart';

class DanmakuTracksMenu extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;

  const DanmakuTracksMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
  });

  @override
  State<DanmakuTracksMenu> createState() => _DanmakuTracksMenuState();
}

class _DanmakuTracksMenuState extends State<DanmakuTracksMenu> {
  bool _isLoadingLocalDanmaku = false;

  // 加载本地JSON弹幕文件
  Future<void> _loadLocalDanmakuFile() async {
    if (_isLoadingLocalDanmaku) return;

    // 重要：此菜单可能会因右侧控件自动隐藏而被销毁（鼠标移出/弹窗/文件选择器等）。
    // 为了避免“控件消失就加载失败”，提前拿到 videoState，后续不再依赖 context/provider。
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    final initialVideoPath = videoState.currentVideoPath;

    if (mounted) {
      setState(() {
        _isLoadingLocalDanmaku = true;
      });
    } else {
      _isLoadingLocalDanmaku = true;
    }

    try {
      // 使用文件选择器选择弹幕文件
      final file = await openFile(
        acceptedTypeGroups: localDanmakuFileTypes,
        confirmButtonText: '选择弹幕文件',
      );

      // 用户取消选择
      if (file == null) return;

      if (videoState.isDisposed ||
          videoState.currentVideoPath != initialVideoPath) {
        debugPrint('视频已切换或播放器已销毁，取消加载本地弹幕');
        return;
      }

      final jsonData = await readLocalDanmakuFile(file);
      final comments = jsonData['comments'] as List;

      final localTrackCount = videoState.danmakuTracks.values
          .where((track) => track['source'] == 'local')
          .length;
      final trackName = '本地弹幕${localTrackCount + 1}';

      // 添加弹幕轨道
      if (videoState.isDisposed ||
          videoState.currentVideoPath != initialVideoPath) {
        debugPrint('视频已切换或播放器已销毁，取消加载本地弹幕');
        return;
      }
      await videoState.loadDanmakuFromLocal(jsonData, trackName: trackName);

      if (mounted) {
        BlurSnackBar.show(context, '弹幕轨道添加成功，共${comments.length}条弹幕');
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '加载弹幕文件失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocalDanmaku = false);
      } else {
        _isLoadingLocalDanmaku = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final menuColors = PlayerMenuTheme.colorsOf(context);
        final tracks = videoState.danmakuTracks;
        final trackEnabled = videoState.danmakuTrackEnabled;
        final totalDanmakuCount = videoState.totalDanmakuCount;
        final filteredDanmakuCount = videoState.danmakuList.length;

        return BaseSettingsMenu(
          title: '弹幕轨道',
          onClose: widget.onClose,
          onHoverChanged: widget.onHoverChanged,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 总览信息
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: menuColors.controlBackground,
                  border: Border(
                    bottom: BorderSide(
                      color: menuColors.divider,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: menuColors.foreground,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '弹幕轨道总览',
                            locale: Locale("zh-Hans", "zh"),
                            style: TextStyle(
                              color: menuColors.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '共${tracks.length}个轨道，合计$totalDanmakuCount条弹幕',
                            locale: Locale("zh-Hans", "zh"),
                            style: TextStyle(
                              color: menuColors.secondaryForeground,
                              fontSize: 12,
                            ),
                          ),
                          if (totalDanmakuCount != filteredDanmakuCount)
                            Text(
                              '显示: $filteredDanmakuCount条 (已过滤${totalDanmakuCount - filteredDanmakuCount}条)',
                              locale: Locale("zh-Hans", "zh"),
                              style: TextStyle(
                                color: Colors.orange.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 轨道列表
              ...tracks.entries.map((entry) {
                final trackId = entry.key;
                if (trackId == 'timeline')
                  return const SizedBox.shrink(); // 不在列表中显示时间轴轨道
                final trackData = entry.value;
                final isEnabled = trackEnabled[trackId] ?? false;
                final trackName = trackData['name'] as String;
                final source = trackData['source'] as String;
                final count = trackData['count'] as int;

                IconData trackIcon;

                switch (source) {
                  case 'dandanplay':
                    trackIcon = Icons.cloud;
                    break;
                  case 'local':
                    trackIcon = Icons.folder;
                    break;
                  default:
                    trackIcon = Icons.track_changes;
                }

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () =>
                        videoState.toggleDanmakuTrack(trackId, !isEnabled),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? menuColors.selectedBackground
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: menuColors.divider,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isEnabled
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: isEnabled
                                ? menuColors.selectedForeground
                                : menuColors.foreground,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            trackIcon,
                            color: isEnabled
                                ? menuColors.selectedForeground
                                : menuColors.foreground,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trackName,
                                  locale: Locale("zh-Hans", "zh"),
                                  style: TextStyle(
                                    color: isEnabled
                                        ? menuColors.selectedForeground
                                        : menuColors.foreground,
                                    fontSize: 14,
                                    fontWeight: isEnabled
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                  ),
                                ),
                                Text(
                                  '$count条弹幕',
                                  locale: Locale("zh-Hans", "zh"),
                                  style: TextStyle(
                                    color: menuColors.secondaryForeground,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 删除按钮（本地轨道才显示）
                          if (source == 'local')
                            IconButton(
                              tooltip: '删除弹幕轨道',
                              onPressed: () =>
                                  videoState.removeDanmakuTrack(trackId),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              iconSize: 18,
                              icon: Icon(
                                Icons.delete_outline,
                                color: menuColors.secondaryForeground,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              // 添加本地弹幕轨道按钮
              _isLoadingLocalDanmaku
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '正在加载弹幕文件...',
                            locale: Locale("zh-Hans", "zh"),
                            style: TextStyle(
                              color: menuColors.secondaryForeground,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : BlurButton(
                      icon: Icons.add_circle_outline,
                      text: "加载本地弹幕文件",
                      onTap: _loadLocalDanmakuFile,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      margin: const EdgeInsets.symmetric(horizontal: 0),
                      expandHorizontally: true,
                      borderRadius: BorderRadius.zero,
                    ),
            ],
          ),
        );
      },
    );
  }
}
