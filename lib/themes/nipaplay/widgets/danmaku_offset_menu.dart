import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'base_settings_menu.dart';
import 'blur_button.dart';
import 'blur_snackbar.dart';
import 'settings_hint_text.dart';

class DanmakuOffsetMenu extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;

  const DanmakuOffsetMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
  });

  @override
  State<DanmakuOffsetMenu> createState() => _DanmakuOffsetMenuState();
}

class _DanmakuOffsetMenuState extends State<DanmakuOffsetMenu> {
  // 预设的偏移选项（秒）
  static const List<double> _offsetOptions = [-10, -5, -2, -1, -0.5, 0, 0.5, 1, 2, 5, 10];
  static const double _minCustomOffset = -60;
  static const double _maxCustomOffset = 60;
  final TextEditingController _customOffsetController = TextEditingController();
  String? _customOffsetError;

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
    final input = _customOffsetController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _customOffsetError = '请输入偏移值';
      });
      return;
    }

    final normalized = input.replaceAll('，', '.').replaceAll(',', '.');
    final offset = double.tryParse(normalized);
    if (offset == null) {
      setState(() {
        _customOffsetError = '请输入有效的数字';
      });
      return;
    }

    if (offset < _minCustomOffset || offset > _maxCustomOffset) {
      setState(() {
        _customOffsetError = '偏移值必须在-60到60秒之间';
      });
      return;
    }

    Provider.of<SettingsProvider>(context, listen: false).setDanmakuTimeOffset(offset);
    FocusScope.of(context).unfocus();
    _customOffsetController.clear();
    setState(() {
      _customOffsetError = null;
    });
    BlurSnackBar.show(context, '已设置弹幕偏移为${_formatOffset(offset)}');
  }

  Widget _buildOffsetButton(double offset, double currentOffset) {
    final bool isSelected = (offset - currentOffset).abs() < 0.01;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Provider.of<SettingsProvider>(context, listen: false)
                .setDanmakuTimeOffset(offset);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(isSelected ? 0.15 : 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(isSelected ? 0.5 : 0.2),
                width: 1,
              ),
            ),
            child: Text(
              _formatOffset(offset),
              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        return BaseSettingsMenu(
          title: '弹幕偏移',
          onClose: widget.onClose,
          onHoverChanged: widget.onHoverChanged,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 当前偏移状态
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '当前偏移',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            settingsProvider.danmakuTimeOffset > 0
                                ? Icons.fast_forward
                                : settingsProvider.danmakuTimeOffset < 0
                                    ? Icons.fast_rewind
                                    : Icons.sync,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatOffset(settingsProvider.danmakuTimeOffset),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SettingsHintText(
                      settingsProvider.danmakuTimeOffset > 0
                          ? '弹幕将提前${settingsProvider.danmakuTimeOffset}秒显示'
                          : settingsProvider.danmakuTimeOffset < 0
                              ? '弹幕将延后${(-settingsProvider.danmakuTimeOffset)}秒显示'
                              : '弹幕按原始时间显示',
                    ),
                  ],
                ),
              ),
              
              // 快速偏移选项
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '快速设置',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 后退选项
                    const Text(
                      '弹幕后退',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      children: _offsetOptions
                          .where((offset) => offset < 0)
                          .map((offset) => _buildOffsetButton(
                              offset, settingsProvider.danmakuTimeOffset))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    
                    // 无偏移
                    const Text(
                      '默认',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildOffsetButton(0, settingsProvider.danmakuTimeOffset),
                    const SizedBox(height: 8),
                    
                    // 前进选项
                    const Text(
                      '弹幕前进',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      children: _offsetOptions
                          .where((offset) => offset > 0)
                          .map((offset) => _buildOffsetButton(
                              offset, settingsProvider.danmakuTimeOffset))
                          .toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 自定义偏移
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '自定义偏移',
style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const SettingsHintText(
                      '输入 -60 ~ 60 之间的精确数值，负数表示弹幕提前，正数表示延迟',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customOffsetController,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              hintText: '例如 -2.5 或 1',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.08),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.6),
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.redAccent,
                                ),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.redAccent,
                                ),
                              ),
                              suffixText: '秒',
                              suffixStyle: const TextStyle(
                                color: Colors.white,
                              ),
                              errorText: _customOffsetError,
                              errorStyle: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                            onSubmitted: (_) => _applyCustomOffset(),
                            onChanged: (_) {
                              if (_customOffsetError != null) {
                                setState(() {
                                  _customOffsetError = null;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        BlurButton(
                          icon: Icons.check,
                          text: '应用',
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          onTap: _applyCustomOffset,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // 说明文字
              Container(
                padding: const EdgeInsets.all(16),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsHintText(
                      '弹幕偏移功能用于调整弹幕与视频的同步：',
                    ),
                    SizedBox(height: 4),
                    SettingsHintText(
                      '• 前进(+)：弹幕提前显示，适用于弹幕慢于视频的情况',
                    ),
                    SettingsHintText(
                      '• 后退(-)：弹幕延后显示，适用于弹幕快于视频的情况',
                    ),
                    SettingsHintText(
                      '• 也可以输入自定义偏移量，范围为 -60 ~ 60 秒',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
