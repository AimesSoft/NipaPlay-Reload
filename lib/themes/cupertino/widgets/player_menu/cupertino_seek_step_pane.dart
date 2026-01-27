import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = Provider.of<SeekStepPaneController>(context, listen: false);
    _skipSecondsController =
        TextEditingController(text: _controller.skipSeconds.toString());
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
    _skipSecondsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.only(top: topSpacing),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              CupertinoListSection.insetGrouped(
                header: const Text('快进 / 快退时间'),
                children: _controller.seekStepOptions.map((seconds) {
                  final isSelected = _controller.seekStepSeconds == seconds;
                  return CupertinoListTile(
                    title: Text('$seconds 秒'),
                    subtitle: const Text('用于点击键盘方向键时的跳跃时长'),
                    trailing: _buildCheckmark(isSelected),
                    onTap: () => _controller.setSeekStepSeconds(seconds),
                  );
                }).toList(),
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('长按右键倍速'),
                children: _controller.speedBoostOptions.map((speed) {
                  final isSelected = _controller.speedBoostRate == speed;
                  return CupertinoListTile(
                    title: Text('${speed}x'),
                    trailing: _buildCheckmark(isSelected),
                    onTap: () => _controller.setSpeedBoostRate(speed),
                  );
                }).toList(),
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('跳过时间'),
                children: [
                  CupertinoListTile(
                    title: Text('${_controller.skipSeconds} 秒'),
                    subtitle: const Text('用于跳过片头/片尾等片段'),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          color:
              CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
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
