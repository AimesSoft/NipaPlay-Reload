import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

/// 统一的媒体库操作按钮：悬停时图标放大并使用主题色
class SearchBarActionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;
  final Color? color;

  const SearchBarActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 20,
    this.tooltip,
    this.color,
  });

  @override
  State<SearchBarActionButton> createState() => _SearchBarActionButtonState();
}

class _SearchBarActionButtonState extends State<SearchBarActionButton> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isEnabled = widget.onPressed != null;
    final bool isLargeScreenModeActive =
        NipaplayLargeScreenModeScope.isActiveOf(context);
    final bool isActive = isEnabled && (_isHovered || _isFocused);

    // 默认颜色：深色模式白色透明度，浅色模式黑色透明度
    Color idleColor = widget.color ??
        (isDark
            ? Colors.white.withValues(alpha: 0.6)
            : Colors.black.withValues(alpha: 0.6));

    if (!isEnabled) {
      idleColor = idleColor.withValues(alpha: 0.3);
    }

    final activeColor = AppAccentColors.current;

    Widget result = FocusableActionDetector(
      enabled: isEnabled,
      onShowFocusHighlight: (value) {
        if (_isFocused == value) return;
        setState(() {
          _isFocused = value;
        });
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) => isEnabled ? setState(() => _isHovered = true) : null,
        onExit: (_) => isEnabled ? setState(() => _isHovered = false) : null,
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isLargeScreenModeActive && _isFocused
                    ? activeColor
                    : Colors.transparent,
                width: isLargeScreenModeActive && _isFocused ? 1.5 : 0,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: AnimatedScale(
              scale: isActive ? 1.25 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Icon(
                widget.icon,
                size: widget.size,
                color: isActive ? activeColor : idleColor,
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      result = Tooltip(
        message: widget.tooltip!,
        child: result,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: result,
    );
  }
}
