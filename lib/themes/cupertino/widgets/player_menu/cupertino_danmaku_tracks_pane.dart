import 'dart:convert';
import 'dart:io' as io;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';

import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoDanmakuTracksPane extends StatefulWidget {
  const CupertinoDanmakuTracksPane({
    super.key,
    required this.videoState,
    required this.onBack,
  });

  final VideoPlayerState videoState;
  final VoidCallback onBack;

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

      final fileBytes = await file.readAsBytes();
      final content = utf8.decode(fileBytes);
      final fileName = file.name.toLowerCase();

      Map<String, dynamic> jsonData;
      if (fileName.endsWith('.xml')) {
        jsonData = _convertXmlToJson(content);
      } else {
        final decoded = json.decode(content);
        if (decoded is Map) {
          jsonData =
              Map<String, dynamic>.from(decoded.cast<String, dynamic>());
        } else if (decoded is List) {
          jsonData = {'comments': decoded};
        } else {
          throw Exception('JSON 文件格式不正确，根节点必须是对象或数组');
        }
      }

      final commentCount = _countDanmakuComments(jsonData);
      if (commentCount == 0) {
        throw Exception('弹幕文件中没有弹幕数据');
      }

      final localTrackCount = widget.videoState.danmakuTracks.values
          .where((track) => track['source'] == 'local')
          .length;
      final trackName = '本地弹幕${localTrackCount + 1}';

      await widget.videoState.loadDanmakuFromLocal(
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

  int _countDanmakuComments(Map<String, dynamic> jsonData) {
    final comments = jsonData['comments'];
    if (comments is List) return comments.length;

    final data = jsonData['data'];
    if (data is List) return data.length;
    if (data is String) {
      try {
        final parsed = json.decode(data);
        if (parsed is List) return parsed.length;
      } catch (_) {
        return 0;
      }
    }

    return 0;
  }

  Map<String, dynamic> _convertXmlToJson(String xmlContent) {
    final List<Map<String, dynamic>> comments = [];

    final RegExp danmakuRegex = RegExp(r'<d p="([^"]+)">([^<]+)</d>');
    final Iterable<RegExpMatch> matches = danmakuRegex.allMatches(xmlContent);

    for (final match in matches) {
      try {
        final String pAttr = match.group(1) ?? '';
        final String textContent = match.group(2) ?? '';

        if (textContent.isEmpty) continue;

        final List<String> pParams = pAttr.split(',');
        if (pParams.length < 4) continue;

        final double time = double.tryParse(pParams[0]) ?? 0.0;
        final int typeCode = int.tryParse(pParams[1]) ?? 1;
        final int fontSize = int.tryParse(pParams[2]) ?? 25;
        final int colorCode = int.tryParse(pParams[3]) ?? 16777215;

        String danmakuType;
        switch (typeCode) {
          case 4:
            danmakuType = 'bottom';
            break;
          case 5:
            danmakuType = 'top';
            break;
          case 1:
          case 6:
          default:
            danmakuType = 'scroll';
            break;
        }

        final int r = (colorCode >> 16) & 0xFF;
        final int g = (colorCode >> 8) & 0xFF;
        final int b = colorCode & 0xFF;
        final String color = 'rgb($r,$g,$b)';

        comments.add({
          't': time,
          'c': textContent,
          'y': danmakuType,
          'r': color,
          'fontSize': fontSize,
          'originalType': typeCode,
        });
      } catch (_) {
        continue;
      }
    }

    return {
      'count': comments.length,
      'comments': comments,
    };
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
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: widget.onBack),
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
