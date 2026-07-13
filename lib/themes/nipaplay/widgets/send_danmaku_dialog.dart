import 'package:flutter/material.dart';
import 'package:nipaplay/constants/danmaku_color_presets.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/services/danmaku_matching_service.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/keyboard_activatable.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class SendDanmakuDialogContent extends StatefulWidget {
  const SendDanmakuDialogContent({
    super.key,
    required this.episodeId,
    required this.currentTime,
    this.onDanmakuSent,
  });

  final int episodeId;
  final double currentTime;
  final ValueChanged<Map<String, dynamic>>? onDanmakuSent;

  @override
  State<SendDanmakuDialogContent> createState() =>
      SendDanmakuDialogContentState();
}

class SendDanmakuDialogContentState extends State<SendDanmakuDialogContent> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController textController = TextEditingController();
  final TextEditingController _hexColorController = TextEditingController();
  final List<Color> _presetColors = DanmakuColorPresets.sendPresetColors;

  Color selectedColor = const Color(0xFFFFFFFF);
  String danmakuType = 'scroll';
  bool _isSending = false;

  @override
  void dispose() {
    _scrollController.dispose();
    textController.dispose();
    _hexColorController.dispose();
    super.dispose();
  }

  int get _selectedModeIndex => switch (danmakuType) {
        'top' => 1,
        'bottom' => 2,
        _ => 0,
      };

  int get _danmakuMode => switch (danmakuType) {
        'top' => 5,
        'bottom' => 4,
        _ => 1,
      };

  Color _strokeColor(Color color) =>
      color.computeLuminance() < 0.2 ? Colors.white : Colors.black;

  Color _darken(Color color, [double amount = .3]) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color _lighten(Color color, [double amount = .3]) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  int _colorToInt(Color color) => color.toARGB32() & 0x00FFFFFF;

  void _updateHexColor(String value) {
    if (value.length != 6) return;
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return;
    setState(() => selectedColor = Color(0xFF000000 | parsed));
  }

  Future<void> _sendDanmaku() async {
    final comment = textController.text.trim();
    if (comment.isEmpty) {
      BlurSnackBar.show(context, '弹幕内容不能为空');
      return;
    }

    setState(() => _isSending = true);
    try {
      final result = await DanmakuMatchingService.instance.sendDanmaku(
        episodeId: widget.episodeId,
        time: widget.currentTime,
        mode: _danmakuMode,
        color: _colorToInt(selectedColor),
        comment: comment,
      );
      if (!mounted) return;
      BlurSnackBar.show(context, '弹幕发送成功');
      final danmaku = result['danmaku'];
      if (result['success'] == true && danmaku is Map) {
        widget.onDanmakuSent?.call(Map<String, dynamic>.from(danmaku));
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) BlurSnackBar.show(context, '发送失败: $error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final inputThemeColor = AppAccentColors.current;
    final isPhone =
        globals.isPhone && MediaQuery.sizeOf(context).shortestSide < 600;
    final strokeColor = _strokeColor(selectedColor);
    final previewStyle = TextStyle(
      fontSize: 18,
      color: selectedColor,
      shadows: [
        for (final offset in [
          Offset(globals.strokeWidth, globals.strokeWidth),
          Offset(-globals.strokeWidth, -globals.strokeWidth),
          Offset(globals.strokeWidth, -globals.strokeWidth),
          Offset(-globals.strokeWidth, globals.strokeWidth),
        ])
          Shadow(offset: offset, color: strokeColor),
      ],
    );

    final form = Padding(
      padding: EdgeInsets.fromLTRB(
        isPhone ? 4 : 16,
        isPhone ? 4 : 16,
        isPhone ? 4 : 16,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdaptiveMediaTextField(
            controller: textController,
            style: previewStyle,
            cursorColor: inputThemeColor,
            minLines: 3,
            maxLines: 5,
            maxLength: 100,
            decoration: InputDecoration(
              hintText: '输入弹幕内容...',
              hintStyle: TextStyle(
                color: theme.hintColor,
                fontSize: 18,
                shadows: const [],
              ),
              fillColor: colors.surfaceContainerHighest,
              filled: true,
              contentPadding: const EdgeInsets.all(14),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: colors.onSurface.withValues(alpha: 0.16),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: inputThemeColor, width: 2),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Text('弹幕模式', style: TextStyle(color: colors.onSurface)),
          const SizedBox(height: 8),
          AdaptiveSegmentedControl(
            labels: const ['滚动', '顶部', '底部'],
            selectedIndex: _selectedModeIndex,
            onValueChanged: (index) {
              setState(() {
                danmakuType = const ['scroll', 'top', 'bottom'][index];
              });
            },
            color: inputThemeColor,
          ),
          const SizedBox(height: 16),
          Text('选择颜色', style: TextStyle(color: colors.onSurface)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _presetColors)
                _DanmakuColorSwatch(
                  color: color,
                  borderColor: selectedColor == color
                      ? (color.toARGB32() == 0xFFFFFFFF
                          ? colors.secondary
                          : _lighten(color))
                      : (color.toARGB32() == 0xFF000000 ||
                              color.toARGB32() == 0xFF222222
                          ? Colors.grey.shade800
                          : _darken(color)),
                  size: isPhone ? 28 : 32,
                  selected: selectedColor == color,
                  onSelected: () => setState(() => selectedColor = color),
                ),
            ],
          ),
          const SizedBox(height: 14),
          AdaptiveMediaTextField(
            controller: _hexColorController,
            maxLength: 6,
            style: TextStyle(color: colors.onSurface),
            cursorColor: inputThemeColor,
            decoration: InputDecoration(
              hintText: '# 六位十六进制颜色值',
              hintStyle: TextStyle(color: theme.hintColor),
              fillColor: colors.surfaceContainerHighest,
              filled: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: colors.onSurface.withValues(alpha: 0.16),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: inputThemeColor, width: 2),
              ),
            ),
            onChanged: _updateHexColor,
          ),
          const SizedBox(height: 18),
          if (_isSending)
            const Center(child: AdaptiveMediaActivityIndicator())
          else
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: isPhone ? double.infinity : 150,
                child: AdaptiveMediaActionButton(
                  label: '发送弹幕',
                  onPressed: _sendDanmaku,
                  emphasis: AdaptiveMediaActionEmphasis.primary,
                  expand: true,
                ),
              ),
            ),
        ],
      ),
    );

    if (isPhone) return form;
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: form,
      ),
    );
  }
}

class _DanmakuColorSwatch extends StatefulWidget {
  const _DanmakuColorSwatch({
    required this.color,
    required this.borderColor,
    required this.size,
    required this.selected,
    required this.onSelected,
  });

  final Color color;
  final Color borderColor;
  final double size;
  final bool selected;
  final VoidCallback onSelected;

  @override
  State<_DanmakuColorSwatch> createState() => _DanmakuColorSwatchState();
}

class _DanmakuColorSwatchState extends State<_DanmakuColorSwatch> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _isHovered || _isFocused;
    return KeyboardActivatable(
      onActivate: widget.onSelected,
      onFocusChange: (value) => setState(() => _isFocused = value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onSelected,
          child: AnimatedScale(
            scale: active ? 1.12 : 1,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? Theme.of(context).colorScheme.onSurface
                      : widget.borderColor,
                  width: active ? 3 : 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
