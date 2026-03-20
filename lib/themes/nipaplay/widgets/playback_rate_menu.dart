import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'base_settings_menu.dart';
import 'blur_button.dart';
import 'blur_snackbar.dart';
import 'settings_hint_text.dart';

class PlaybackRateMenu extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;

  const PlaybackRateMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
  });

  @override
  State<PlaybackRateMenu> createState() => _PlaybackRateMenuState();
}

class _PlaybackRateMenuState extends State<PlaybackRateMenu> {
  final TextEditingController _customRateController = TextEditingController();
  final FocusNode _customRateFocus = FocusNode();
  String? _customRateError;
  bool _customRateDirty = false;

  @override
  void dispose() {
    _customRateController.dispose();
    _customRateFocus.dispose();
    super.dispose();
  }

  String _trimTrailingZeros(String value) {
    if (!value.contains('.')) return value;
    return value
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _formatRate(double value) {
    return _trimTrailingZeros(value.toStringAsFixed(2));
  }

  String _normalizeNumberInput(String value) {
    return value
        .trim()
        .replaceAll('，', '.')
        .replaceAll(',', '.')
        .replaceAll('＋', '+')
        .replaceAll('－', '-');
  }

  void _syncCustomRateController(PlaybackRatePaneController controller) {
    if (_customRateFocus.hasFocus || _customRateDirty) return;
    final value = _formatRate(controller.currentRate);
    if (_customRateController.text != value) {
      _customRateController.text = value;
    }
  }

  Future<void> _applyCustomRate(PlaybackRatePaneController controller) async {
    final input = _normalizeNumberInput(_customRateController.text);
    if (input.isEmpty) {
      setState(() {
        _customRateError = '请输入倍速';
      });
      return;
    }

    final value = double.tryParse(input);
    if (value == null) {
      setState(() {
        _customRateError = '请输入有效数字';
      });
      return;
    }

    if (value < controller.minCustomRate || value > controller.maxCustomRate) {
      setState(() {
        _customRateError =
            '请输入 ${_formatRate(controller.minCustomRate)}x ~ ${_formatRate(controller.maxCustomRate)}x';
      });
      return;
    }

    await controller.setPlaybackRate(value);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _customRateError = null;
      _customRateDirty = false;
    });
    BlurSnackBar.show(context, '已设置播放速度为 ${_formatRate(value)}x');
  }

  void _handleCustomRateChanged(String _) {
    if (_customRateDirty && _customRateError == null) return;
    setState(() {
      _customRateDirty = true;
      _customRateError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaybackRatePaneController>(
      builder: (context, controller, child) {
        _syncCustomRateController(controller);
        return BaseSettingsMenu(
          title: '倍速设置',
          onClose: widget.onClose,
          onHoverChanged: widget.onHoverChanged,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '当前倍速',
                          locale: Locale("zh-Hans", "zh"),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${_formatRate(controller.currentRate)}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.isSpeedBoostActive
                          ? '正在倍速播放'
                          : '点击下方预设或输入精确倍速',
                      locale: Locale("zh-Hans", "zh"),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '手动输入倍速',
                      locale: Locale("zh-Hans", "zh"),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customRateController,
                            focusNode: _customRateFocus,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: false,
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,，]'),
                              ),
                            ],
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: '例如 0.01 / 1.25 / 3.5',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.08),
                              suffixText: 'x',
                              suffixStyle:
                                  const TextStyle(color: Colors.white70),
                              errorText: _customRateError,
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.2),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.6),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderSide:
                                    const BorderSide(color: Colors.redAccent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderSide:
                                    const BorderSide(color: Colors.redAccent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onSubmitted: (_) => _applyCustomRate(controller),
                            onChanged: _handleCustomRateChanged,
                          ),
                        ),
                        const SizedBox(width: 12),
                        BlurButton(
                          text: '应用',
                          icon: Icons.check,
                          onTap: () => _applyCustomRate(controller),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SettingsHintText(
                      '可输入 ${_formatRate(controller.minCustomRate)}x ~ ${_formatRate(controller.maxCustomRate)}x，常用预设仍保留在下方',
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              ...controller.speedOptions.map((speed) {
                final isSelected =
                    (controller.currentRate - speed).abs() < 0.0001;
                final isNormalSpeed = speed == 1.0;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      controller.setPlaybackRate(speed);
                      setState(() {
                        _customRateError = null;
                        _customRateDirty = false;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getSpeedIcon(speed, isNormalSpeed),
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${_formatRate(speed)}x ${_getSpeedDescription(speed, isNormalSpeed)}',
                              locale: Locale("zh-Hans", "zh"),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  IconData _getSpeedIcon(double speed, bool isNormalSpeed) {
    if (isNormalSpeed) {
      return Icons.play_circle_outline_rounded;
    } else if (speed < 1.0) {
      return Icons.slow_motion_video_rounded;
    } else if (speed <= 2.0) {
      return Icons.fast_forward_rounded;
    } else {
      return Icons.rocket_launch_rounded;
    }
  }

  String _getSpeedDescription(double speed, bool isNormalSpeed) {
    if (isNormalSpeed) {
      return '(正常速度)';
    } else if (speed < 1.0) {
      return '(慢速)';
    } else if (speed <= 2.0) {
      return '(快速)';
    } else {
      return '(极速)';
    }
  }
}
