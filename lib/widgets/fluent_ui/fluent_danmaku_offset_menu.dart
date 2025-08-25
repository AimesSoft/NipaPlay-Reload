import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';

class FluentDanmakuOffsetMenu extends StatefulWidget {
  final VideoPlayerState videoState;

  const FluentDanmakuOffsetMenu({
    super.key,
    required this.videoState,
  });

  @override
  State<FluentDanmakuOffsetMenu> createState() => _FluentDanmakuOffsetMenuState();
}

class _FluentDanmakuOffsetMenuState extends State<FluentDanmakuOffsetMenu> {
  // 预设的偏移选项（秒）
  static const List<double> _offsetOptions = [-10, -5, -2, -1, -0.5, 0, 0.5, 1, 2, 5, 10];
  final TextEditingController _customOffsetController = TextEditingController();

  @override
  void dispose() {
    _customOffsetController.dispose();
    super.dispose();
  }

  String _formatOffset(double offset) {
    if (offset == 0) return '无偏移';
    if (offset > 0) return '+${offset}秒';
    return '${offset}秒';
  }

  void _applyCustomOffset() {
    final text = _customOffsetController.text.trim();
    if (text.isEmpty) return;

    try {
      final offset = double.parse(text);
      if (offset >= -60 && offset <= 60) {
        Provider.of<SettingsProvider>(context, listen: false).setDanmakuTimeOffset(offset);
        _customOffsetController.clear();
        
        displayInfoBar(context, builder: (context, close) {
          return InfoBar(
            title: const Text('成功'),
            content: Text('已设置弹幕偏移为${_formatOffset(offset)}'),
            severity: InfoBarSeverity.success,
            isLong: false,
          );
        });
      } else {
        _showErrorInfo('偏移值必须在-60到60秒之间');
      }
    } catch (e) {
      _showErrorInfo('请输入有效的数字');
    }
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

  Widget _buildOffsetButton(double offset, double currentOffset) {
    final bool isSelected = (offset - currentOffset).abs() < 0.01;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: HoverButton(
        onPressed: isSelected ? null : () {
          Provider.of<SettingsProvider>(context, listen: false).setDanmakuTimeOffset(offset);
        },
        builder: (context, states) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
                  : states.isHovered
                      ? FluentTheme.of(context).resources.subtleFillColorSecondary
                      : FluentTheme.of(context).resources.controlFillColorDefault,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? FluentTheme.of(context).accentColor
                    : FluentTheme.of(context).resources.controlStrokeColorDefault,
                width: 1,
              ),
            ),
            child: Text(
              _formatOffset(offset),
              style: FluentTheme.of(context).typography.body?.copyWith(
                color: isSelected
                    ? FluentTheme.of(context).accentColor
                    : FluentTheme.of(context).resources.textFillColorPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final currentOffset = settingsProvider.danmakuTimeOffset;
        
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
                    '弹幕时间偏移',
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '调整弹幕显示的时间偏移量',
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
                  // 当前偏移显示
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
                                '当前偏移',
                                style: FluentTheme.of(context).typography.body,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentOffset == 0
                                    ? '弹幕与视频同步显示'
                                    : currentOffset > 0
                                        ? '弹幕延迟${currentOffset}秒显示'
                                        : '弹幕提前${-currentOffset}秒显示',
                                style: FluentTheme.of(context).typography.caption?.copyWith(
                                  color: FluentTheme.of(context).resources.textFillColorSecondary,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: FluentTheme.of(context).accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: FluentTheme.of(context).accentColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              _formatOffset(currentOffset),
                              style: FluentTheme.of(context).typography.body?.copyWith(
                                color: FluentTheme.of(context).accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 快速选择
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '快速选择',
                            style: FluentTheme.of(context).typography.body,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '选择常用的偏移量',
                            style: FluentTheme.of(context).typography.caption?.copyWith(
                              color: FluentTheme.of(context).resources.textFillColorSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // 偏移按钮网格
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: _offsetOptions.map((offset) {
                              return _buildOffsetButton(offset, currentOffset);
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 自定义偏移
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '自定义偏移',
                            style: FluentTheme.of(context).typography.body,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '输入-60到60之间的数值（秒），负数表示提前，正数表示延迟',
                            style: FluentTheme.of(context).typography.caption?.copyWith(
                              color: FluentTheme.of(context).resources.textFillColorSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          Row(
                            children: [
                              Expanded(
                                child: TextBox(
                                  controller: _customOffsetController,
                                  placeholder: '输入偏移值（如：-2.5）',
                                  onSubmitted: (_) => _applyCustomOffset(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Button(
                                onPressed: _applyCustomOffset,
                                child: const Text('应用'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 重置按钮
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '重置偏移',
                            style: FluentTheme.of(context).typography.body,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '将弹幕偏移重置为无偏移状态',
                            style: FluentTheme.of(context).typography.caption?.copyWith(
                              color: FluentTheme.of(context).resources.textFillColorSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: Button(
                              onPressed: currentOffset == 0 ? null : () {
                                Provider.of<SettingsProvider>(context, listen: false).setDanmakuTimeOffset(0);
                                
                                displayInfoBar(context, builder: (context, close) {
                                  return InfoBar(
                                    title: const Text('成功'),
                                    content: const Text('已重置弹幕偏移'),
                                    severity: InfoBarSeverity.success,
                                    isLong: false,
                                  );
                                });
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(FluentIcons.refresh, size: 16),
                                  const SizedBox(width: 8),
                                  const Text('重置偏移'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 说明信息
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FluentTheme.of(context).resources.controlFillColorDefault,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: FluentTheme.of(context).resources.controlStrokeColorDefault,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          FluentIcons.info,
                          size: 16,
                          color: FluentTheme.of(context).resources.textFillColorPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '使用说明',
                                style: FluentTheme.of(context).typography.caption?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '• 负数：弹幕提前显示（如-2秒表示弹幕比原定时间提前2秒显示）\n• 正数：弹幕延迟显示（如+2秒表示弹幕比原定时间延迟2秒显示）\n• 调整后的偏移会立即应用到当前播放的弹幕',
                                style: FluentTheme.of(context).typography.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}