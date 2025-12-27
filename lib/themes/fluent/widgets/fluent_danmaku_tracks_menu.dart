import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'dart:convert';
import 'dart:io' as io;
import 'package:file_selector/file_selector.dart';

class FluentDanmakuTracksMenu extends StatefulWidget {
  final VideoPlayerState videoState;

  const FluentDanmakuTracksMenu({
    super.key,
    required this.videoState,
  });

  @override
  State<FluentDanmakuTracksMenu> createState() => _FluentDanmakuTracksMenuState();
}

class _FluentDanmakuTracksMenuState extends State<FluentDanmakuTracksMenu> {
  bool _isLoadingLocalDanmaku = false;

  Future<void> _loadLocalDanmakuFile() async {
    if (_isLoadingLocalDanmaku) return;

    final videoState = widget.videoState;
    final initialVideoPath = videoState.currentVideoPath;
    if (mounted) {
      setState(() => _isLoadingLocalDanmaku = true);
    } else {
      _isLoadingLocalDanmaku = true;
    }

    try {
      final XTypeGroup jsonTypeGroup = XTypeGroup(
        label: 'JSON弹幕文件',
        extensions: const ['json'],
        uniformTypeIdentifiers: io.Platform.isIOS 
            ? ['public.json', 'public.text', 'public.plain-text'] 
            : null,
      );
      
      final XTypeGroup xmlTypeGroup = XTypeGroup(
        label: 'XML弹幕文件',
        extensions: const ['xml'],
        uniformTypeIdentifiers: io.Platform.isIOS 
            ? ['public.xml', 'public.text', 'public.plain-text'] 
            : null,
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: [jsonTypeGroup, xmlTypeGroup],
      );

      if (file == null) return;

      if (videoState.isDisposed || videoState.currentVideoPath != initialVideoPath) {
        debugPrint('视频已切换或播放器已销毁，取消加载本地弹幕');
        return;
      }

      // 读取文件内容
      final content = utf8.decode(await file.readAsBytes());
      final fileName = file.name.toLowerCase();

      Map<String, dynamic> jsonData;
      if (fileName.endsWith('.xml')) {
        jsonData = _convertXmlToJson(content);
      } else if (fileName.endsWith('.json')) {
        final decoded = json.decode(content);
        if (decoded is Map) {
          jsonData = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
        } else if (decoded is List) {
          jsonData = {'comments': decoded};
        } else {
          throw Exception('JSON 文件格式不正确，根节点必须是对象或数组');
        }
      } else {
        throw Exception('不支持的文件格式');
      }

      final commentCount = _countDanmakuComments(jsonData);
      if (commentCount == 0) {
        throw Exception('弹幕文件中没有弹幕数据');
      }

      final localTrackCount = videoState.danmakuTracks.values
          .where((track) => track['source'] == 'local')
          .length;
      final trackName = '本地弹幕${localTrackCount + 1}';

      if (videoState.isDisposed || videoState.currentVideoPath != initialVideoPath) {
        debugPrint('视频已切换或播放器已销毁，取消加载本地弹幕');
        return;
      }
      await videoState.loadDanmakuFromLocal(jsonData, trackName: trackName);
      _showSuccessInfo('弹幕轨道添加成功：$trackName（$commentCount条）');

    } catch (e) {
      _showErrorInfo('加载弹幕文件失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocalDanmaku = false);
      } else {
        _isLoadingLocalDanmaku = false;
      }
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

    // 解析B站XML弹幕格式: <d p="参数">内容</d>
    final RegExp danmakuRegex = RegExp(r'<d p="([^"]+)">([^<]+)</d>');
    final Iterable<RegExpMatch> matches = danmakuRegex.allMatches(xmlContent);

    for (final match in matches) {
      try {
        final String pAttr = match.group(1) ?? '';
        final String textContent = match.group(2) ?? '';
        if (textContent.isEmpty) continue;

        final List<String> pParams = pAttr.split(',');
        if (pParams.length < 4) continue;

        // XML弹幕格式参数：时间,类型,字号,颜色,时间戳,池,用户id,弹幕id
        final double time = double.tryParse(pParams[0]) ?? 0.0;
        final int typeCode = int.tryParse(pParams[1]) ?? 1;
        final int fontSize = int.tryParse(pParams[2]) ?? 25;
        final int colorCode = int.tryParse(pParams[3]) ?? 16777215; // 默认白色

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

  void _showSuccessInfo(String message) {
    if (!mounted) return;
    displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: const Text('成功'),
        content: Text(message),
        severity: InfoBarSeverity.success,
        isLong: false,
      );
    });
  }

  void _showErrorInfo(String message) {
    if (!mounted) return;
    displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: const Text('错误'),
        content: Text(message),
        severity: InfoBarSeverity.error,
        isLong: true,
      );
    });
  }

  Widget _buildCurrentDanmakuInfo() {
    if (widget.videoState.animeTitle == null || widget.videoState.episodeTitle == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.info,
                    size: 16,
                    color: FluentTheme.of(context).resources.textFillColorSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '当前弹幕状态',
                    style: FluentTheme.of(context).typography.body,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '未加载弹幕',
                style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: FluentTheme.of(context).resources.textFillColorSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  FluentIcons.check_mark,
                  size: 16,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  '当前弹幕',
                  style: FluentTheme.of(context).typography.body,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '动画: ${widget.videoState.animeTitle}',
              style: FluentTheme.of(context).typography.caption?.copyWith(
                color: FluentTheme.of(context).resources.textFillColorPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '剧集: ${widget.videoState.episodeTitle}',
              style: FluentTheme.of(context).typography.caption?.copyWith(
                color: FluentTheme.of(context).resources.textFillColorPrimary,
              ),
            ),
            if (widget.videoState.danmakuList.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '弹幕数量: ${widget.videoState.danmakuList.length}条',
                style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: FluentTheme.of(context).resources.textFillColorSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 提示信息
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '弹幕轨道',
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
              const SizedBox(height: 4),
              Text(
                '管理和切换不同的弹幕来源',
                style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: FluentTheme.of(context).resources.textFillColorTertiary,
                ),
              ),
            ],
          ),
        ),
        
        // 分隔线
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 当前弹幕信息
              _buildCurrentDanmakuInfo(),
              
              const SizedBox(height: 16),
              
              // 加载本地弹幕文件
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '加载本地弹幕文件',
                        style: FluentTheme.of(context).typography.body,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '支持JSON格式和XML格式的弹幕文件',
                        style: FluentTheme.of(context).typography.caption?.copyWith(
                          color: FluentTheme.of(context).resources.textFillColorSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: _isLoadingLocalDanmaku
                            ? FilledButton(
                                onPressed: null,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: ProgressRing(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('加载中...'),
                                  ],
                                ),
                              )
                            : FilledButton(
                                onPressed: _loadLocalDanmakuFile,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(FluentIcons.open_file, size: 16),
                                    const SizedBox(width: 8),
                                    const Text('选择弹幕文件'),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 在线弹幕源选择
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '在线弹幕源',
                        style: FluentTheme.of(context).typography.body,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '从在线数据库获取弹幕',
                        style: FluentTheme.of(context).typography.caption?.copyWith(
                          color: FluentTheme.of(context).resources.textFillColorSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // 弹幕源列表
                      ..._buildDanmakuSourceList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDanmakuSourceList() {
    final sources = [
      {'name': 'DandanPlay', 'enabled': true, 'description': '弹弹Play官方弹幕库'},
      {'name': 'Bilibili', 'enabled': false, 'description': '哔哩哔哩弹幕（需配置）'},
      {'name': 'AcFun', 'enabled': false, 'description': 'AcFun弹幕（需配置）'},
    ];

    return sources.map((source) {
      final isEnabled = source['enabled'] as bool;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          decoration: BoxDecoration(
            color: isEnabled 
                ? FluentTheme.of(context).accentColor.withValues(alpha: 0.1)
                : FluentTheme.of(context).resources.controlFillColorDefault,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isEnabled
                  ? FluentTheme.of(context).accentColor.withValues(alpha: 0.3)
                  : FluentTheme.of(context).resources.controlStrokeColorDefault,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  isEnabled ? FluentIcons.radio_btn_on : FluentIcons.radio_btn_off,
                  size: 16,
                  color: isEnabled
                      ? FluentTheme.of(context).accentColor
                      : FluentTheme.of(context).resources.textFillColorSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source['name'] as String,
                        style: FluentTheme.of(context).typography.body?.copyWith(
                          color: isEnabled
                              ? FluentTheme.of(context).accentColor
                              : FluentTheme.of(context).resources.textFillColorPrimary,
                          fontWeight: isEnabled ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        source['description'] as String,
                        style: FluentTheme.of(context).typography.caption?.copyWith(
                          color: isEnabled
                              ? FluentTheme.of(context).accentColor.withValues(alpha: 0.8)
                              : FluentTheme.of(context).resources.textFillColorSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isEnabled)
                  Icon(
                    FluentIcons.check_mark,
                    size: 16,
                    color: FluentTheme.of(context).accentColor,
                  ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }
}
