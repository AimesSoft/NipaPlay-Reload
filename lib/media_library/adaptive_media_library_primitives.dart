import 'dart:math' as math;

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart' as material;
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';

enum AdaptiveMediaActionEmphasis {
  plain,
  primary,
  destructive,
}

class AdaptiveMediaActionButton extends material.StatelessWidget {
  const AdaptiveMediaActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.desktopIcon,
    this.phoneIcon,
    this.emphasis = AdaptiveMediaActionEmphasis.plain,
    this.compact = false,
    this.expand = false,
  });

  final String label;
  final material.VoidCallback? onPressed;
  final material.IconData? desktopIcon;
  final material.IconData? phoneIcon;
  final AdaptiveMediaActionEmphasis emphasis;
  final bool compact;
  final bool expand;

  @override
  material.Widget build(material.BuildContext context) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      final color = emphasis == AdaptiveMediaActionEmphasis.destructive
          ? cupertino.CupertinoColors.systemRed
          : null;
      final content = material.Row(
        mainAxisSize:
            expand ? material.MainAxisSize.max : material.MainAxisSize.min,
        mainAxisAlignment: material.MainAxisAlignment.center,
        children: [
          if (phoneIcon != null) ...[
            material.Icon(phoneIcon, size: compact ? 16 : 18),
            const material.SizedBox(width: 6),
          ],
          material.Flexible(
            child: material.Text(
              label,
              maxLines: 1,
              overflow: material.TextOverflow.ellipsis,
            ),
          ),
        ],
      );
      final padding = material.EdgeInsets.symmetric(
        horizontal: compact ? 8 : 14,
        vertical: compact ? 5 : 9,
      );
      if (emphasis == AdaptiveMediaActionEmphasis.primary) {
        return cupertino.CupertinoButton.filled(
          padding: padding,
          borderRadius: material.BorderRadius.circular(8),
          onPressed: onPressed,
          child: content,
        );
      }
      return cupertino.CupertinoButton(
        padding: padding,
        borderRadius: material.BorderRadius.circular(8),
        color: color,
        onPressed: onPressed,
        child: content,
      );
    }

    if (emphasis == AdaptiveMediaActionEmphasis.primary && onPressed != null) {
      return BlurButton(
        icon: desktopIcon,
        text: label,
        onTap: onPressed!,
        expandHorizontally: expand,
        padding: material.EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 5 : 8,
        ),
      );
    }

    final foreground = emphasis == AdaptiveMediaActionEmphasis.destructive
        ? material.Colors.redAccent
        : null;
    return HoverScaleTextButton(
      onPressed: onPressed,
      idleColor: foreground,
      hoverColor: foreground,
      padding: material.EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 4 : 7,
      ),
      child: material.Row(
        mainAxisSize: material.MainAxisSize.min,
        children: [
          if (desktopIcon != null) ...[
            material.Icon(desktopIcon, size: compact ? 16 : 18),
            const material.SizedBox(width: 6),
          ],
          material.Text(label),
        ],
      ),
    );
  }
}

class AdaptiveMediaIconButton extends material.StatelessWidget {
  const AdaptiveMediaIconButton({
    super.key,
    required this.desktopIcon,
    required this.phoneIcon,
    required this.onPressed,
    required this.tooltip,
    this.color,
    this.size = 20,
  });

  final material.IconData desktopIcon;
  final material.IconData phoneIcon;
  final material.VoidCallback? onPressed;
  final String tooltip;
  final material.Color? color;
  final double size;

  @override
  material.Widget build(material.BuildContext context) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return material.Semantics(
        button: true,
        label: tooltip,
        child: cupertino.CupertinoButton(
          padding: const material.EdgeInsets.all(7),
          minimumSize: const material.Size.square(34),
          onPressed: onPressed,
          child: material.Icon(phoneIcon, size: size, color: color),
        ),
      );
    }
    return material.Tooltip(
      message: tooltip,
      child: HoverScaleTextButton(
        onPressed: onPressed,
        idleColor: color,
        hoverColor: color,
        padding: const material.EdgeInsets.all(7),
        child: material.Icon(desktopIcon, size: size),
      ),
    );
  }
}

class AdaptiveMediaActivityIndicator extends material.StatelessWidget {
  const AdaptiveMediaActivityIndicator({
    super.key,
    this.color,
    this.size = 24,
  });

  final material.Color? color;
  final double size;

  @override
  material.Widget build(material.BuildContext context) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return cupertino.CupertinoActivityIndicator(
        radius: size / 2,
        color: color,
      );
    }
    return _NipaplayActivityIndicator(color: color, size: size);
  }
}

class AdaptiveMediaProgressBar extends material.StatelessWidget {
  const AdaptiveMediaProgressBar({
    super.key,
    required this.value,
    this.color,
    this.backgroundColor,
    this.height = 3,
  });

  final double? value;
  final material.Color? color;
  final material.Color? backgroundColor;
  final double height;

  @override
  material.Widget build(material.BuildContext context) {
    final foreground = color ??
        (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone
            ? cupertino.CupertinoTheme.of(context).primaryColor
            : material.Theme.of(context).colorScheme.primary);
    final track = backgroundColor ??
        material.Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1);
    final progress = value;
    if (progress == null) {
      return material.SizedBox(
        height: height,
        child: _NipaplayIndeterminateProgress(
          color: foreground,
          backgroundColor: track,
        ),
      );
    }
    return material.ClipRRect(
      borderRadius: material.BorderRadius.circular(height / 2),
      child: material.SizedBox(
        height: height,
        child: material.ColoredBox(
          color: track,
          child: material.FractionallySizedBox(
            alignment: material.Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child: material.ColoredBox(color: foreground),
          ),
        ),
      ),
    );
  }
}

class AdaptiveMediaScrollbar extends material.StatelessWidget {
  const AdaptiveMediaScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  final material.ScrollController? controller;
  final material.Widget child;

  @override
  material.Widget build(material.BuildContext context) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return cupertino.CupertinoScrollbar(
        controller: controller,
        child: child,
      );
    }
    return material.Scrollbar(
      controller: controller,
      radius: const material.Radius.circular(4),
      child: child,
    );
  }
}

class AdaptiveMediaExpansionTile extends material.StatelessWidget {
  const AdaptiveMediaExpansionTile({
    super.key,
    required this.title,
    required this.expanded,
    required this.onExpansionChanged,
    required this.children,
    this.leading,
    this.subtitle,
    this.trailing,
    this.iconColor,
  });

  final material.Widget title;
  final bool expanded;
  final material.ValueChanged<bool> onExpansionChanged;
  final List<material.Widget> children;
  final material.Widget? leading;
  final material.Widget? subtitle;
  final material.Widget? trailing;
  final material.Color? iconColor;

  @override
  material.Widget build(material.BuildContext context) {
    final phone = AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;
    final header = material.Padding(
      padding: const material.EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: material.Row(
        children: [
          if (leading != null) ...[
            leading!,
            const material.SizedBox(width: 10),
          ],
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                title,
                if (subtitle != null) ...[
                  const material.SizedBox(height: 4),
                  subtitle!,
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
          const material.SizedBox(width: 4),
          material.AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 180),
            child: material.Icon(
              phone
                  ? cupertino.CupertinoIcons.chevron_right
                  : material.Icons.chevron_right_rounded,
              size: 18,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
    final interactiveHeader = phone
        ? cupertino.CupertinoButton(
            padding: material.EdgeInsets.zero,
            borderRadius: material.BorderRadius.circular(8),
            onPressed: () => onExpansionChanged(!expanded),
            child: header,
          )
        : material.MouseRegion(
            cursor: material.SystemMouseCursors.click,
            child: material.GestureDetector(
              behavior: material.HitTestBehavior.opaque,
              onTap: () => onExpansionChanged(!expanded),
              child: header,
            ),
          );

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        interactiveHeader,
        material.AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: material.Curves.easeOutCubic,
          child: expanded
              ? material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.stretch,
                  children: children,
                )
              : const material.SizedBox.shrink(),
        ),
      ],
    );
  }
}

class AdaptiveMediaListTile extends material.StatelessWidget {
  const AdaptiveMediaListTile({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.contentPadding = const material.EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 8,
    ),
  });

  final material.Widget title;
  final material.Widget? leading;
  final material.Widget? subtitle;
  final material.Widget? trailing;
  final material.VoidCallback? onTap;
  final material.EdgeInsetsGeometry contentPadding;

  @override
  material.Widget build(material.BuildContext context) {
    final content = material.Padding(
      padding: contentPadding,
      child: material.Row(
        children: [
          if (leading != null) ...[
            leading!,
            const material.SizedBox(width: 10),
          ],
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                title,
                if (subtitle != null) ...[
                  const material.SizedBox(height: 3),
                  subtitle!,
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const material.SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return cupertino.CupertinoButton(
        padding: material.EdgeInsets.zero,
        borderRadius: material.BorderRadius.circular(8),
        onPressed: onTap,
        child: content,
      );
    }
    return material.MouseRegion(
      cursor: material.SystemMouseCursors.click,
      child: material.GestureDetector(
        behavior: material.HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class AdaptiveMediaSearchField extends material.StatelessWidget {
  const AdaptiveMediaSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  final material.TextEditingController controller;
  final material.FocusNode focusNode;
  final String placeholder;
  final material.ValueChanged<String> onChanged;
  final material.ValueChanged<String>? onSubmitted;
  final material.VoidCallback? onClear;

  @override
  material.Widget build(material.BuildContext context) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return cupertino.CupertinoSearchTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onSuffixTap: _clear,
      );
    }

    final theme = material.Theme.of(context);
    final dark = theme.brightness == material.Brightness.dark;
    final textColor = dark ? material.Colors.white : material.Colors.black87;
    final secondary = textColor.withValues(alpha: 0.52);
    final active = theme.colorScheme.primary;
    return material.AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 40,
      padding: const material.EdgeInsets.symmetric(horizontal: 11),
      decoration: material.BoxDecoration(
        color: dark
            ? material.Colors.white.withValues(alpha: 0.12)
            : material.Colors.white,
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(
          color:
              focusNode.hasFocus ? active : textColor.withValues(alpha: 0.10),
          width: focusNode.hasFocus ? 1.5 : 1,
        ),
      ),
      child: material.Row(
        children: [
          material.Icon(
            material.Icons.search_rounded,
            size: 18,
            color: focusNode.hasFocus ? active : secondary,
          ),
          const material.SizedBox(width: 9),
          material.Expanded(
            child: material.Stack(
              alignment: material.Alignment.centerLeft,
              children: [
                if (controller.text.isEmpty)
                  material.IgnorePointer(
                    child: material.Text(
                      placeholder,
                      maxLines: 1,
                      overflow: material.TextOverflow.ellipsis,
                      style: material.TextStyle(
                        color: secondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                material.EditableText(
                  controller: controller,
                  focusNode: focusNode,
                  style: material.TextStyle(color: textColor, fontSize: 14),
                  cursorColor: active,
                  backgroundCursorColor: secondary,
                  selectionColor: active.withValues(alpha: 0.28),
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  textInputAction: material.TextInputAction.search,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          if (controller.text.isNotEmpty)
            AdaptiveMediaIconButton(
              desktopIcon: material.Icons.close_rounded,
              phoneIcon: cupertino.CupertinoIcons.clear,
              tooltip: '清空搜索',
              size: 17,
              onPressed: _clear,
            ),
        ],
      ),
    );
  }

  void _clear() {
    controller.clear();
    onChanged('');
    onClear?.call();
  }
}

class AdaptiveMediaCheckbox extends material.StatelessWidget {
  const AdaptiveMediaCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final material.ValueChanged<bool>? onChanged;

  @override
  material.Widget build(material.BuildContext context) {
    final phone = AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;
    final accent = phone
        ? cupertino.CupertinoTheme.of(context).primaryColor
        : material.Theme.of(context).colorScheme.primary;
    if (phone) {
      return cupertino.CupertinoCheckbox(
        value: value,
        activeColor: accent,
        onChanged:
            onChanged == null ? null : (next) => onChanged!.call(next ?? false),
      );
    }
    return material.GestureDetector(
      behavior: material.HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!.call(!value),
      child: material.AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 22,
        height: 22,
        decoration: material.BoxDecoration(
          color: value ? accent : material.Colors.transparent,
          borderRadius: material.BorderRadius.circular(6),
          border: material.Border.all(
            color: value
                ? accent
                : material.Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.38),
            width: 1.5,
          ),
        ),
        child: value
            ? const material.Icon(
                material.Icons.check_rounded,
                size: 16,
                color: material.Colors.white,
              )
            : null,
      ),
    );
  }
}

class AdaptiveMediaTextField extends material.StatefulWidget {
  const AdaptiveMediaTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.style,
    this.decoration,
    this.cursorColor,
    this.keyboardType,
    this.minLines,
    this.maxLines = 1,
    this.obscureText = false,
    this.textInputAction,
    this.textAlign = material.TextAlign.start,
    this.onChanged,
    this.onSubmitted,
  });

  final material.TextEditingController controller;
  final material.FocusNode? focusNode;
  final material.TextStyle? style;
  final material.InputDecoration? decoration;
  final material.Color? cursorColor;
  final material.TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;
  final bool obscureText;
  final material.TextInputAction? textInputAction;
  final material.TextAlign textAlign;
  final material.ValueChanged<String>? onChanged;
  final material.ValueChanged<String>? onSubmitted;

  @override
  material.State<AdaptiveMediaTextField> createState() =>
      _AdaptiveMediaTextFieldState();
}

class _AdaptiveMediaTextFieldState
    extends material.State<AdaptiveMediaTextField> {
  late final material.FocusNode _internalFocusNode;
  material.FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = material.FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AdaptiveMediaTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    (oldWidget.focusNode ?? _internalFocusNode)
        .removeListener(_handleFocusChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _internalFocusNode.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final decoration = widget.decoration;
    final placeholder = decoration?.hintText;
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return cupertino.CupertinoTextField(
        controller: widget.controller,
        focusNode: _focusNode,
        placeholder: placeholder,
        style: widget.style,
        cursorColor: widget.cursorColor,
        keyboardType: widget.keyboardType,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        obscureText: widget.obscureText,
        textInputAction: widget.textInputAction,
        textAlign: widget.textAlign,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        padding: decoration?.contentPadding ??
            const material.EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
        decoration: material.BoxDecoration(
          color: decoration?.fillColor ??
              cupertino.CupertinoDynamicColor.resolve(
                cupertino.CupertinoColors.secondarySystemGroupedBackground,
                context,
              ),
          borderRadius: material.BorderRadius.circular(8),
        ),
      );
    }

    final theme = material.Theme.of(context);
    final style = widget.style ?? theme.textTheme.bodyMedium!;
    final enabledBorder = decoration?.enabledBorder;
    final focusedBorder = decoration?.focusedBorder;
    final activeBorder = _focusNode.hasFocus ? focusedBorder : enabledBorder;
    final borderSide = activeBorder is material.OutlineInputBorder
        ? activeBorder.borderSide
        : material.BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.18),
          );
    final borderRadius = activeBorder is material.OutlineInputBorder
        ? activeBorder.borderRadius
        : material.BorderRadius.circular(8);
    return material.Container(
      padding: decoration?.contentPadding ??
          const material.EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: material.BoxDecoration(
        color: decoration?.fillColor,
        borderRadius: borderRadius,
        border: material.Border.fromBorderSide(borderSide),
      ),
      child: material.Stack(
        alignment: material.Alignment.centerLeft,
        children: [
          if (widget.controller.text.isEmpty && placeholder != null)
            material.IgnorePointer(
              child: material.Text(
                placeholder,
                maxLines: widget.maxLines,
                overflow: material.TextOverflow.ellipsis,
                style: decoration?.hintStyle,
              ),
            ),
          material.EditableText(
            controller: widget.controller,
            focusNode: _focusNode,
            style: style,
            cursorColor: widget.cursorColor ?? theme.colorScheme.primary,
            backgroundCursorColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.4),
            selectionColor: theme.colorScheme.primary.withValues(alpha: 0.25),
            keyboardType: widget.keyboardType,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            obscureText: widget.obscureText,
            textInputAction: widget.textInputAction,
            textAlign: widget.textAlign,
            onChanged: (value) {
              setState(() {});
              widget.onChanged?.call(value);
            },
            onSubmitted: widget.onSubmitted,
          ),
        ],
      ),
    );
  }
}

class _NipaplayActivityIndicator extends material.StatefulWidget {
  const _NipaplayActivityIndicator({
    required this.color,
    required this.size,
  });

  final material.Color? color;
  final double size;

  @override
  material.State<_NipaplayActivityIndicator> createState() =>
      _NipaplayActivityIndicatorState();
}

class _NipaplayActivityIndicatorState
    extends material.State<_NipaplayActivityIndicator>
    with material.SingleTickerProviderStateMixin {
  late final material.AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = material.AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final color =
        widget.color ?? material.Theme.of(context).colorScheme.primary;
    return material.RotationTransition(
      turns: _controller,
      child: material.CustomPaint(
        size: material.Size.square(widget.size),
        painter: _NipaplaySpinnerPainter(color),
      ),
    );
  }
}

class _NipaplaySpinnerPainter extends material.CustomPainter {
  const _NipaplaySpinnerPainter(this.color);

  final material.Color color;

  @override
  void paint(material.Canvas canvas, material.Size size) {
    final strokeWidth = math.max(2.0, size.shortestSide * 0.11);
    final rect = material.Offset.zero & size;
    final paint = material.Paint()
      ..color = color
      ..style = material.PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = material.StrokeCap.round;
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -math.pi / 2,
      math.pi * 1.35,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_NipaplaySpinnerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _NipaplayIndeterminateProgress extends material.StatefulWidget {
  const _NipaplayIndeterminateProgress({
    required this.color,
    required this.backgroundColor,
  });

  final material.Color color;
  final material.Color backgroundColor;

  @override
  material.State<_NipaplayIndeterminateProgress> createState() =>
      _NipaplayIndeterminateProgressState();
}

class _NipaplayIndeterminateProgressState
    extends material.State<_NipaplayIndeterminateProgress>
    with material.SingleTickerProviderStateMixin {
  late final material.AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = material.AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.ClipRRect(
      borderRadius: material.BorderRadius.circular(2),
      child: material.ColoredBox(
        color: widget.backgroundColor,
        child: material.AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => material.FractionallySizedBox(
            alignment: material.Alignment(-1 + (_controller.value * 2), 0),
            widthFactor: 0.32,
            child: material.ColoredBox(color: widget.color),
          ),
        ),
      ),
    );
  }
}
