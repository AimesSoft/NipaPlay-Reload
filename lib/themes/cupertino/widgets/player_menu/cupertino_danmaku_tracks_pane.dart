import 'package:file_selector/file_selector.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/adaptive_player_menu_primitives.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/utils/local_danmaku_file.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoDanmakuTracksPane extends StatefulWidget {
  const CupertinoDanmakuTracksPane({
    super.key,
    required this.videoState,
  });

  final VideoPlayerState videoState;

  @override
  State<CupertinoDanmakuTracksPane> createState() =>
      _CupertinoDanmakuTracksPaneState();
}

class _CupertinoDanmakuTracksPaneState
    extends State<CupertinoDanmakuTracksPane> {
  bool _isLoadingLocal = false;

  Future<void> _loadLocalDanmakuFile() async {
    if (_isLoadingLocal) return;
    final videoState = widget.videoState;
    final initialVideoPath = videoState.currentVideoPath;
    setState(() => _isLoadingLocal = true);

    try {
      final file = await openFile(
        acceptedTypeGroups: localDanmakuFileTypes,
        confirmButtonText: '选择弹幕文件',
      );

      if (file == null) return;

      final jsonData = await readLocalDanmakuFile(file);
      final commentCount = jsonData['count'] as int;
      if (videoState.isDisposed ||
          videoState.currentVideoPath != initialVideoPath) return;

      final localTrackCount = videoState.danmakuTracks.values
          .where((track) => track['source'] == 'local')
          .length;
      final trackName = '本地弹幕${localTrackCount + 1}';

      await videoState.loadDanmakuFromLocal(
        jsonData,
        trackName: trackName,
      );

      _showMessage('弹幕轨道添加成功：$trackName（$commentCount条）');
    } catch (e) {
      _showMessage('加载弹幕文件失败：$e');
    } finally {
      if (mounted) setState(() => _isLoadingLocal = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    BlurSnackBar.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = NipaplayLargeScreenModeScope.isActiveOf(context);
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Text(
              '管理当前弹幕状态并切换不同的来源',
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            AdaptivePlayerMenuSection(
              header: const Text('当前状态'),
              children: [
                AdaptivePlayerMenuTile(
                  title: Text(
                    widget.videoState.animeTitle ?? '未加载弹幕',
                  ),
                  subtitle: Text(
                    widget.videoState.episodeTitle ?? '暂无弹幕信息',
                  ),
                  trailing: Text(
                    widget.videoState.danmakuList.isEmpty
                        ? '0条'
                        : '${widget.videoState.danmakuList.length}条',
                    style:
                        CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                  ),
                ),
              ],
            ),
            if (!globals.isTelevision)
              AdaptivePlayerMenuSection(
                header: const Text('本地弹幕'),
                children: [
                  AdaptivePlayerMenuTile(
                    title: const Text('加载本地弹幕文件'),
                    subtitle: const Text('支持 JSON / XML 格式'),
                    trailing: _isLoadingLocal
                        ? const AdaptivePlayerMenuProgressIndicator()
                        : const Icon(CupertinoIcons.cloud_download),
                    onTap: _isLoadingLocal ? null : _loadLocalDanmakuFile,
                  ),
                ],
              ),
            if (!isLargeScreen)
              AdaptivePlayerMenuSection(
                header: const Text('在线来源'),
                children: [
                  _buildSourceTile(
                    context,
                    title: 'DandanPlay',
                    subtitle: '弹弹Play 官方弹幕库',
                    enabled: true,
                  ),
                  _buildSourceTile(
                    context,
                    title: 'Bilibili',
                    subtitle: '需在设置中配置账号',
                  ),
                  _buildSourceTile(
                    context,
                    title: 'AcFun',
                    subtitle: '即将开放',
                  ),
                ],
              ),
            const SizedBox(height: 24),
          ]),
        ),
      ],
    );
  }

  Widget _buildSourceTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    bool enabled = false,
  }) {
    return AdaptivePlayerMenuTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(
        enabled
            ? CupertinoIcons.check_mark_circled_solid
            : CupertinoIcons.circle,
        color: enabled
            ? CupertinoTheme.of(context).primaryColor
            : CupertinoColors.inactiveGray,
      ),
    );
  }
}
