import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';

class CupertinoPlaybackRatePane extends StatefulWidget {
  const CupertinoPlaybackRatePane({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<CupertinoPlaybackRatePane> createState() =>
      _CupertinoPlaybackRatePaneState();
}

class _CupertinoPlaybackRatePaneState extends State<CupertinoPlaybackRatePane> {
  final TextEditingController _customRateController = TextEditingController();
  final FocusNode _customRateFocus = FocusNode();
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
      BlurSnackBar.show(context, '请输入倍速');
      return;
    }

    final value = double.tryParse(input);
    if (value == null) {
      BlurSnackBar.show(context, '请输入有效数字');
      return;
    }
    if (!value.isFinite) {
      BlurSnackBar.show(context, '请输入有限数字');
      return;
    }

    if (value < controller.minCustomRate || value > controller.maxCustomRate) {
      BlurSnackBar.show(
        context,
        '请输入 ${_formatRate(controller.minCustomRate)}x ~ ${_formatRate(controller.maxCustomRate)}x',
      );
      return;
    }

    await controller.setPlaybackRate(value);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _customRateDirty = false;
    });
    BlurSnackBar.show(context, '已设置播放速度为 ${_formatRate(value)}x');
  }

  void _handleCustomRateChanged(String _) {
    if (_customRateDirty) return;
    setState(() {
      _customRateDirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlaybackRatePaneController>();
    _syncCustomRateController(controller);

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前倍速',
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(
                        fontSize: 15,
                        color:
                            CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatRate(controller.currentRate)}x',
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .navLargeTitleTextStyle
                      .copyWith(fontSize: 28),
                ),
                const SizedBox(height: 6),
                Text(
                  controller.isSpeedBoostActive ? '正在使用长按倍速' : '点选预设或输入精确倍速',
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(
                        fontSize: 13,
                        color: CupertinoColors.systemGrey2.resolveFrom(context),
                      ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              CupertinoListSection.insetGrouped(
                header: const Text('手动输入'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CupertinoTextField(
                          controller: _customRateController,
                          focusNode: _customRateFocus,
                          placeholder: '例如 0.01 / 1.25 / 3.5',
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: false,
                            decimal: true,
                          ),
                          suffix: const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Text('x'),
                          ),
                          onChanged: _handleCustomRateChanged,
                          onSubmitted: (_) => _applyCustomRate(controller),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '可输入 ${_formatRate(controller.minCustomRate)}x ~ ${_formatRate(controller.maxCustomRate)}x，常用预设仍保留在下方',
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .textStyle
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
                            onPressed: () => _applyCustomRate(controller),
                            child: const Text('应用'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('选择倍速'),
                children: controller.speedOptions.map((speed) {
                  final bool isSelected =
                      (controller.currentRate - speed).abs() < 0.0001;
                  return CupertinoListTile(
                    title: Text('${_formatRate(speed)}x'),
                    subtitle: Text(_speedDescription(speed)),
                    trailing: isSelected
                        ? Icon(
                            CupertinoIcons.check_mark,
                            color: CupertinoTheme.of(context).primaryColor,
                          )
                        : null,
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      controller.setPlaybackRate(speed);
                      setState(() {
                        _customRateDirty = false;
                      });
                    },
                  );
                }).toList(),
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

  String _speedDescription(double speed) {
    if (speed == 1.0) {
      return '正常速度';
    } else if (speed < 1.0) {
      return '慢速播放';
    } else if (speed <= 2.0) {
      return '快速播放';
    } else {
      return '极速播放';
    }
  }
}
