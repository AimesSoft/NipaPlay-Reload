import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/services/manual_danmaku_matcher.dart';
import 'package:nipaplay/utils/danmaku_history_sync.dart';

class FluentDanmakuSettingsMenu extends StatefulWidget {
  final VideoPlayerState videoState;

  const FluentDanmakuSettingsMenu({
    super.key,
    required this.videoState,
  });

  @override
  State<FluentDanmakuSettingsMenu> createState() => _FluentDanmakuSettingsMenuState();
}

class _FluentDanmakuSettingsMenuState extends State<FluentDanmakuSettingsMenu> {
  final TextEditingController _blockWordController = TextEditingController();
  bool _hasBlockWordError = false;
  String _blockWordErrorMessage = '';

  @override
  void dispose() {
    _blockWordController.dispose();
    super.dispose();
  }

  void _addBlockWord() {
    final word = _blockWordController.text.trim();
    
    if (word.isEmpty) {
      setState(() {
        _hasBlockWordError = true;
        _blockWordErrorMessage = '屏蔽词不能为空';
      });
      return;
    }
    
    if (widget.videoState.danmakuBlockWords.contains(word)) {
      setState(() {
        _hasBlockWordError = true;
        _blockWordErrorMessage = '该屏蔽词已存在';
      });
      return;
    }
    
    widget.videoState.addDanmakuBlockWord(word);
    
    _blockWordController.clear();
    setState(() {
      _hasBlockWordError = false;
      _blockWordErrorMessage = '';
    });
  }

  Widget _buildBlockWordsList() {
    if (widget.videoState.danmakuBlockWords.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Text(
          '暂无屏蔽词',
          style: FluentTheme.of(context).typography.body?.copyWith(
            color: FluentTheme.of(context).resources.textFillColorSecondary,
          ),
        ),
      );
    }
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.videoState.danmakuBlockWords.map((word) {
        return Container(
          decoration: BoxDecoration(
            color: FluentTheme.of(context).resources.controlFillColorDefault,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: FluentTheme.of(context).resources.controlStrokeColorDefault,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  word,
                  style: FluentTheme.of(context).typography.caption?.copyWith(
                    color: FluentTheme.of(context).resources.textFillColorPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => widget.videoState.removeDanmakuBlockWord(word),
                  child: Icon(
                    FluentIcons.chrome_close,
                    size: 12,
                    color: FluentTheme.of(context).resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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
                '弹幕设置',
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
              const SizedBox(height: 4),
              Text(
                '调整弹幕显示效果和过滤设置',
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
              // 弹幕开关
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '显示弹幕',
                            style: FluentTheme.of(context).typography.body,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '开启后在视频上显示弹幕内容',
                            style: FluentTheme.of(context).typography.caption?.copyWith(
                              color: FluentTheme.of(context).resources.textFillColorSecondary,
                            ),
                          ),
                        ],
                      ),
                      ToggleSwitch(
                        checked: widget.videoState.danmakuVisible,
                        onChanged: (value) {
                          widget.videoState.setDanmakuVisible(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 手动匹配弹幕
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '手动匹配弹幕',
                        style: FluentTheme.of(context).typography.body,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '手动搜索并选择匹配的弹幕文件',
                        style: FluentTheme.of(context).typography.caption?.copyWith(
                          color: FluentTheme.of(context).resources.textFillColorSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            final result = await ManualDanmakuMatcher.instance.showManualMatchDialog(context);
                              
                            if (result != null) {
                              final episodeId = result['episodeId']?.toString() ?? '';
                              final animeId = result['animeId']?.toString() ?? '';
                              
                              if (episodeId.isNotEmpty && animeId.isNotEmpty) {
                                try {
                                  final currentVideoPath = widget.videoState.currentVideoPath;
                                  if (currentVideoPath != null) {
                                    await DanmakuHistorySync.updateHistoryWithDanmakuInfo(
                                      videoPath: currentVideoPath,
                                      episodeId: episodeId,
                                      animeId: animeId,
                                      animeTitle: result['animeTitle']?.toString(),
                                      episodeTitle: result['episodeTitle']?.toString(),
                                    );
                                    
                                    widget.videoState.setAnimeTitle(result['animeTitle']?.toString());
                                    widget.videoState.setEpisodeTitle(result['episodeTitle']?.toString());
                                  }
                                } catch (e) {
                                  // 继续加载弹幕
                                }
                                
                                widget.videoState.loadDanmaku(episodeId, animeId);
                              }
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(FluentIcons.search, size: 16),
                              const SizedBox(width: 8),
                              const Text('搜索弹幕'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 弹幕透明度
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '弹幕透明度',
                            style: FluentTheme.of(context).typography.body,
                          ),
                          Text(
                            '${(widget.videoState.danmakuOpacity * 100).round()}%',
                            style: FluentTheme.of(context).typography.caption?.copyWith(
                              color: FluentTheme.of(context).resources.textFillColorSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: widget.videoState.danmakuOpacity,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        onChanged: (value) {
                          widget.videoState.setDanmakuOpacity(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 弹幕字体大小
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '弹幕字体大小',
                            style: FluentTheme.of(context).typography.body,
                          ),
                          Text(
                            '${widget.videoState.danmakuFontSize.round()}px',
                            style: FluentTheme.of(context).typography.caption?.copyWith(
                              color: FluentTheme.of(context).resources.textFillColorSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: widget.videoState.danmakuFontSize,
                        min: 12.0,
                        max: 36.0,
                        divisions: 24,
                        onChanged: (value) {
                          widget.videoState.setDanmakuFontSize(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 弹幕屏蔽词管理
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '屏蔽词管理',
                        style: FluentTheme.of(context).typography.body,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '添加需要屏蔽的关键词，包含这些词的弹幕将不会显示',
                        style: FluentTheme.of(context).typography.caption?.copyWith(
                          color: FluentTheme.of(context).resources.textFillColorSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // 添加屏蔽词输入框
                      Row(
                        children: [
                          Expanded(
                            child: TextBox(
                              controller: _blockWordController,
                              placeholder: '输入要屏蔽的词汇',
                              onSubmitted: (_) => _addBlockWord(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Button(
                            onPressed: _addBlockWord,
                            child: const Text('添加'),
                          ),
                        ],
                      ),
                      
                      if (_hasBlockWordError) ...[
                        const SizedBox(height: 8),
                        Text(
                          _blockWordErrorMessage,
                          style: FluentTheme.of(context).typography.caption?.copyWith(
                            color: Colors.red,
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 16),
                      
                      // 屏蔽词列表
                      _buildBlockWordsList(),
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
}