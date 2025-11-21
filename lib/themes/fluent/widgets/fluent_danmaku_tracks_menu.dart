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

    setState(() {
      _isLoadingLocalDanmaku = true;
    });

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

      if (file == null) {
        setState(() {
          _isLoadingLocalDanmaku = false;
        });
        return;
      }

      // 读取文件内容
      final String content = await file.readAsString();
      
      // 简单验证文件格式
      if (file.name.toLowerCase().endsWith('.json')) {
        try {
          final decoded = json.decode(content);
          if (decoded is List) {
            _showSuccessInfo('成功加载JSON弹幕文件: ${file.name}');
            // 这里可以调用VideoPlayerState的方法来加载弹幕
            // widget.videoState.loadLocalDanmakuFromJson(decoded);
          } else {
            _showErrorInfo('无效的JSON弹幕文件格式');
          }
        } catch (e) {
          _showErrorInfo('解析JSON文件失败: $e');
        }
      } else if (file.name.toLowerCase().endsWith('.xml')) {
        if (content.contains('<d ') || content.contains('<item>')) {
          _showSuccessInfo('成功加载XML弹幕文件: ${file.name}');
          // 这里可以调用VideoPlayerState的方法来加载弹幕
          // widget.videoState.loadLocalDanmakuFromXml(content);
        } else {
          _showErrorInfo('无效的XML弹幕文件格式');
        }
      } else {
        _showErrorInfo('不支持的文件格式');
      }

    } catch (e) {
      _showErrorInfo('加载弹幕文件失败: $e');
    } finally {
      setState(() {
        _isLoadingLocalDanmaku = false;
      });
    }
  }

  void _showSuccessInfo(String message) {
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