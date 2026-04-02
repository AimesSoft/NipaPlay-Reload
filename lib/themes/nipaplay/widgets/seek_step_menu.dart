import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'base_settings_menu.dart';
import 'blur_button.dart';
import 'blur_snackbar.dart';
import 'settings_hint_text.dart';

class SeekStepMenu extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;

  const SeekStepMenu({super.key, required this.onClose, this.onHoverChanged});

  @override
  State<SeekStepMenu> createState() => _SeekStepMenuState();
}

class _SeekStepMenuState extends State<SeekStepMenu> {
  final TextEditingController _customSeekStepController =
      TextEditingController();
  final FocusNode _customSeekStepFocus = FocusNode();
  final TextEditingController _skipSecondsController = TextEditingController();
  String? _customSeekStepError;
  bool _customSeekStepDirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = Provider.of<SeekStepPaneController>(
        context,
        listen: false,
      );
      _skipSecondsController.text = controller.skipSeconds.toString();
    });
  }

  @override
  void dispose() {
    _customSeekStepController.dispose();
    _customSeekStepFocus.dispose();
    _skipSecondsController.dispose();
    super.dispose();
  }

  String _normalizeNumberInput(String value) {
    return value
        .trim()
        .replaceAll('，', '.')
        .replaceAll(',', '.')
        .replaceAll('＋', '+')
        .replaceAll('－', '-');
  }

  void _syncCustomSeekStepController(SeekStepPaneController controller) {
    if (_customSeekStepFocus.hasFocus || _customSeekStepDirty) return;
    final value = controller.seekStepInputValue;
    if (_customSeekStepController.text != value) {
      _customSeekStepController.text = value;
    }
  }

  Future<void> _applyCustomSeekStep(SeekStepPaneController controller) async {
    final input = _normalizeNumberInput(_customSeekStepController.text);
    if (input.isEmpty) {
      setState(() {
        _customSeekStepError = '请输入快进快退秒数';
      });
      return;
    }

    final value = double.tryParse(input);
    if (value == null || !value.isFinite) {
      setState(() {
        _customSeekStepError = '请输入有效数字';
      });
      return;
    }

    if (value < controller.seekStepMinSeconds ||
        value > controller.seekStepMaxSeconds) {
      setState(() {
        _customSeekStepError =
            '请输入 ${controller.seekStepMinimumInputValue} ~ ${controller.seekStepMaximumInputValue} 秒';
      });
      return;
    }

    await controller.setSeekStepSeconds(value);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _customSeekStepError = null;
      _customSeekStepDirty = false;
    });
    BlurSnackBar.show(
      context,
      '已设置快进快退时间为 ${controller.formatSeekStepLabel(value, preferFrameLabel: true, includeFrameApproximation: true)}',
    );
  }

  void _handleCustomSeekStepChanged(String _) {
    if (_customSeekStepDirty && _customSeekStepError == null) return;
    setState(() {
      _customSeekStepDirty = true;
      _customSeekStepError = null;
    });
  }

  void _selectSeekStepPreset(SeekStepPaneController controller, double value) {
    FocusScope.of(context).unfocus();
    controller.setSeekStepSeconds(value);
    setState(() {
      _customSeekStepDirty = false;
      _customSeekStepError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SeekStepPaneController>(
      builder: (context, controller, child) {
        _syncCustomSeekStepController(controller);

        return BaseSettingsMenu(
          title: '播放设置',
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
                          '快进快退时间',
                          locale: Locale('zh', 'CN'),
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        Text(
                          controller.seekStepSummaryLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '支持预设与手动输入，最小值为 1 帧',
                      locale: Locale('zh', 'CN'),
                      style: TextStyle(fontSize: 12, color: Colors.white),
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
                      '手动输入快进快退时间',
                      locale: Locale('zh', 'CN'),
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
                            controller: _customSeekStepController,
                            focusNode: _customSeekStepFocus,
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
                              hintText: '例如 0.5 / 1 / 12.5',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.08),
                              suffixText: '秒',
                              suffixStyle: const TextStyle(
                                color: Colors.white70,
                              ),
                              errorText: _customSeekStepError,
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
                                borderSide: const BorderSide(
                                  color: Colors.redAccent,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                  color: Colors.redAccent,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onSubmitted: (_) =>
                                _applyCustomSeekStep(controller),
                            onChanged: _handleCustomSeekStepChanged,
                          ),
                        ),
                        const SizedBox(width: 12),
                        BlurButton(
                          text: '应用',
                          icon: Icons.check,
                          onTap: () => _applyCustomSeekStep(controller),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SettingsHintText(controller.seekStepInputRangeHint),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              ...controller.seekStepOptions.map((seconds) {
                final isSelected = controller.isSeekStepSelected(seconds);
                final isFrame = controller.isFrameSeekStep(seconds);
                final title = controller.formatSeekStepLabel(
                  seconds,
                  preferFrameLabel: true,
                );
                final subtitle = isFrame
                    ? '按当前视频帧率计算，约 ${controller.formatSeekStepLabel(seconds)}'
                    : null;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _selectSeekStepPreset(controller, seconds),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.72),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const Divider(color: Colors.white24, height: 1),
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '长按右键倍速',
                          locale: Locale('zh', 'CN'),
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        Text(
                          '${controller.speedBoostRate}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '设置长按右方向键时的播放倍速',
                      locale: Locale('zh', 'CN'),
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              ...controller.speedBoostOptions.map((speed) {
                final isSelected = controller.speedBoostRate == speed;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      controller.setSpeedBoostRate(speed);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${speed}x',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const Divider(color: Colors.white24, height: 1),
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '跳过时间',
                          locale: Locale('zh', 'CN'),
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        Text(
                          '${controller.skipSeconds}秒',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '设置跳过功能的跳跃时间',
                      locale: Locale('zh', 'CN'),
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              final newValue = (controller.skipSeconds - 10)
                                  .clamp(
                                    SeekStepPaneController.minSkipSeconds,
                                    SeekStepPaneController.maxSkipSeconds,
                                  )
                                  .toInt();
                              controller.setSkipSeconds(newValue);
                              _skipSecondsController.text = newValue.toString();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white30),
                              ),
                              child: const Icon(
                                Icons.remove,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _skipSecondsController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.white30,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.white30,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.white,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.white10,
                              suffixText: '秒',
                              suffixStyle: const TextStyle(color: Colors.white),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (value) {
                              final intValue = int.tryParse(value);
                              if (intValue != null &&
                                  intValue >=
                                      SeekStepPaneController.minSkipSeconds &&
                                  intValue <=
                                      SeekStepPaneController.maxSkipSeconds) {
                                controller.setSkipSeconds(intValue);
                              }
                            },
                            onTap: () {
                              if (_skipSecondsController.text.isEmpty) {
                                _skipSecondsController.text = controller
                                    .skipSeconds
                                    .toString();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              final newValue = (controller.skipSeconds + 10)
                                  .clamp(
                                    SeekStepPaneController.minSkipSeconds,
                                    SeekStepPaneController.maxSkipSeconds,
                                  )
                                  .toInt();
                              controller.setSkipSeconds(newValue);
                              _skipSecondsController.text = newValue.toString();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white30),
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
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
