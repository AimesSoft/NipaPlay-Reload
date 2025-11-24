import 'dart:convert';
import 'dart:io' as io;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';

import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
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
    setState(() => _isLoadingLocal = true);

    try {
      final jsonType = XTypeGroup(
        label: 'JSON弹幕',
        extensions: const ['json'],
        uniformTypeIdentifiers: io.Platform.isIOS
            ? ['public.json', 'public.text', 'public.plain-text']
            : null,
      );
      final xmlType = XTypeGroup(
        label: 'XML弹幕',
        extensions: const ['xml'],
        uniformTypeIdentifiers: io.Platform.isIOS
            ? ['public.xml', 'public.text', 'public.plain-text']
            : null,
      );

      final file = await openFile(acceptedTypeGroups: [jsonType, xmlType]);
      if (file == null) return;

      final content = await file.readAsString();
      if (file.name.toLowerCase().endsWith('.json')) {
        final decoded = json.decode(content);
        if (decoded is List) {
          _showMessage('成功加载 JSON 弹幕：${file.name}');
        } else {
          _showMessage('无效的 JSON 弹幕格式');
        }
      } else {
        if (content.contains('<d ') || content.contains('<item>')) {
          _showMessage('成功加载 XML 弹幕：${file.name}');
        } else {
          _showMessage('XML 文件格式无法识别');
        }
      }
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
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '弹幕来源',
                  style:
                      CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
                const SizedBox(height: 4),
                Text(
                  '管理当前弹幕状态并切换不同的来源',
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
        SliverList(
          delegate: SliverChildListDelegate([
            CupertinoListSection.insetGrouped(
              header: const Text('当前状态'),
              children: [
                CupertinoListTile(
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
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .textStyle
                        .copyWith(
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('本地弹幕'),
              children: [
                CupertinoListTile(
                  title: const Text('加载本地弹幕文件'),
                  subtitle: const Text('支持 JSON / XML 格式'),
                  trailing: _isLoadingLocal
                      ? const CupertinoActivityIndicator()
                      : const Icon(CupertinoIcons.cloud_download),
                  onTap: _isLoadingLocal ? null : _loadLocalDanmakuFile,
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
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
    return CupertinoListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(
        enabled ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle,
        color: enabled
            ? CupertinoTheme.of(context).primaryColor
            : CupertinoColors.inactiveGray,
      ),
    );
  }
}
