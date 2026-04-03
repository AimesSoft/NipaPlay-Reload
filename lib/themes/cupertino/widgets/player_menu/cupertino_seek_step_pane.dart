import 'package:flutter/services.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';

class CupertinoSeekStepPane extends StatefulWidget {
  const CupertinoSeekStepPane({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<CupertinoSeekStepPane> createState() => _CupertinoSeekStepPaneState();
}

class _CupertinoSeekStepPaneState extends State<CupertinoSeekStepPane> {
  late final SeekStepPaneController _controller;
  late final TextEditingController _skipSecondsController;
  late final VoidCallback _controllerListener;
  final TextEditingController _customSeekStepController =
      TextEditingController();
  final FocusNode _customSeekStepFocus = FocusNode();
  bool _customSeekStepDirty = false;

  @override
  void initState() {
    super.initState();
    _controller = Provider.of<SeekStepPaneController>(context, listen: false);
    _skipSecondsController = TextEditingController(
      text: _controller.skipSeconds.toString(),
    );
    _controllerListener = () {
      final String next = _controller.skipSeconds.toString();
      if (_skipSecondsController.text != next) {
        _skipSecondsController.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    };
    _controller.addListener(_controllerListener);
  }

  @override
  void dispose() {
    _controller.removeListener(_controllerListener);
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

  void _syncCustomSeekStepController() {
    if (_customSeekStepFocus.hasFocus || _customSeekStepDirty) return;
    final value = _controller.seekStepInputValue;
    if (_customSeekStepController.text != value) {
      _customSeekStepController.text = value;
    }
  }

  Future<void> _applyCustomSeekStep() async {
    final input = _normalizeNumberInput(_customSeekStepController.text);
    if (input.isEmpty) {
      BlurSnackBar.show(context, '请输入快进快退秒数');
      return;
    }

    final value = double.tryParse(input);
    if (value == null || !value.isFinite) {
      BlurSnackBar.show(context, '请输入有效数字');
      return;
    }

    if (value < _controller.seekStepMinSeconds ||
        value > _controller.seekStepMaxSeconds) {
      BlurSnackBar.show(
        context,
        '请输入 ${_controller.seekStepMinimumInputValue} ~ ${_controller.seekStepMaximumInputValue} 秒',
      );
      return;
    }

    await _controller.setSeekStepSeconds(value);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _customSeekStepDirty = false;
    });
    BlurSnackBar.show(
      context,
      '已设置快进快退时间为 ${_controller.formatSeekStepLabel(value, preferFrameLabel: true, includeFrameApproximation: true)}',
    );
  }

  void _handleCustomSeekStepChanged(String _) {
    if (_customSeekStepDirty) return;
    setState(() {
      _customSeekStepDirty = true;
    });
  }

  void _selectSeekStepPreset(double value) {
    FocusScope.of(context).unfocus();
    _controller.setSeekStepSeconds(value);
    setState(() {
      _customSeekStepDirty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SeekStepPaneController>();
    _syncCustomSeekStepController();

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.only(top: topSpacing),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              CupertinoListSection.insetGrouped(
                header: const Text('快进 / 快退时间'),
                children: [
                  CupertinoListTile(
                    title: Text(controller.seekStepSummaryLabel),
                    subtitle: const Text('支持预设与手动输入，最小值为 1 帧'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CupertinoTextField(
                          controller: _customSeekStepController,
                          focusNode: _customSeekStepFocus,
                          placeholder: '例如 0.5 / 1 / 12.5',
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: false,
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,，]'),
                            ),
                          ],
                          suffix: const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Text('秒'),
                          ),
                          onChanged: _handleCustomSeekStepChanged,
                          onSubmitted: (_) => _applyCustomSeekStep(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          controller.seekStepInputRangeHint,
                          style: CupertinoTheme.of(context).textTheme.textStyle
                              .copyWith(
                                fontSize: 13,
                                color: CupertinoColors.secondaryLabel
                                    .resolveFrom(context),
                              ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            onPressed: _applyCustomSeekStep,
                            child: const Text('应用'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...controller.seekStepOptions.map((seconds) {
                    final isSelected = controller.isSeekStepSelected(seconds);
                    final isFrame = controller.isFrameSeekStep(seconds);
                    return CupertinoListTile(
                      title: Text(
                        controller.formatSeekStepLabel(
                          seconds,
                          preferFrameLabel: true,
                        ),
                      ),
                      subtitle: Text(
                        isFrame
                            ? '按当前视频帧率计算，约 ${controller.formatSeekStepLabel(seconds)}'
                            : '用于点击键盘方向键时的跳跃时长',
                      ),
                      trailing: _buildCheckmark(isSelected),
                      onTap: () => _selectSeekStepPreset(seconds),
                    );
                  }),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('长按右键倍速'),
                children: controller.speedBoostOptions.map((speed) {
                  final isSelected = controller.speedBoostRate == speed;
                  return CupertinoListTile(
                    title: Text('${speed}x'),
                    trailing: _buildCheckmark(isSelected),
                    onTap: () => controller.setSpeedBoostRate(speed),
                  );
                }).toList(),
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('跳过时间'),
                children: [
                  CupertinoListTile(
                    title: Text('${controller.skipSeconds} 秒'),
                    subtitle: const Text('用于跳过片头/片尾等片段'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _buildStepperButton(
                          icon: CupertinoIcons.minus,
                          onTap: () => _updateSkipSeconds(-10),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CupertinoTextField(
                            controller: _skipSecondsController,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: BoxDecoration(
                              color: CupertinoColors
                                  .tertiarySystemGroupedBackground
                                  .resolveFrom(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onSubmitted: _handleSkipInput,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildStepperButton(
                          icon: CupertinoIcons.plus,
                          onTap: () => _updateSkipSeconds(10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: widget.onBack),
        ),
      ],
    );
  }

  Widget _buildCheckmark(bool selected) {
    if (!selected) return const SizedBox.shrink();
    return Icon(
      CupertinoIcons.check_mark,
      size: 20,
      color: CupertinoTheme.of(context).primaryColor,
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon),
      ),
    );
  }

  void _updateSkipSeconds(int delta) {
    final int next = (_controller.skipSeconds + delta)
        .clamp(
          SeekStepPaneController.minSkipSeconds,
          SeekStepPaneController.maxSkipSeconds,
        )
        .toInt();
    _controller.setSkipSeconds(next);
  }

  void _handleSkipInput(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      _skipSecondsController.text = _controller.skipSeconds.toString();
      return;
    }
    final clamped = parsed
        .clamp(
          SeekStepPaneController.minSkipSeconds,
          SeekStepPaneController.maxSkipSeconds,
        )
        .toInt();
    _controller.setSkipSeconds(clamped);
  }
}
