export 'package:adaptive_platform_ui/adaptive_platform_ui.dart'
    hide
        AdaptiveAlertDialog,
        AdaptiveButton,
        AdaptiveSegmentedControl,
        AdaptiveSlider,
        AdaptiveSnackBar,
        AdaptiveSwitch;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as platform_ui;
import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';

typedef AdaptiveSnackBarType = platform_ui.AdaptiveSnackBarType;

bool _useLiquidGlassFallback(BuildContext context) {
  return AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone &&
      !platform_ui.PlatformInfo.isIOS26OrHigher();
}

class AdaptiveButton extends StatelessWidget {
  const AdaptiveButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.color,
    this.textColor,
    this.style = platform_ui.AdaptiveButtonStyle.filled,
    this.size = platform_ui.AdaptiveButtonSize.medium,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.enabled = true,
    this.useSmoothRectangleBorder = true,
  })  : child = null,
        icon = null,
        iconColor = null,
        sfSymbol = null;

  const AdaptiveButton.child({
    super.key,
    required this.onPressed,
    required this.child,
    this.color,
    this.style = platform_ui.AdaptiveButtonStyle.filled,
    this.size = platform_ui.AdaptiveButtonSize.medium,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.enabled = true,
    this.useSmoothRectangleBorder = true,
  })  : label = null,
        textColor = null,
        icon = null,
        iconColor = null,
        sfSymbol = null;

  const AdaptiveButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    this.color,
    this.iconColor,
    this.style = platform_ui.AdaptiveButtonStyle.filled,
    this.size = platform_ui.AdaptiveButtonSize.medium,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.enabled = true,
    this.useSmoothRectangleBorder = true,
  })  : label = null,
        textColor = null,
        child = null,
        sfSymbol = null;

  const AdaptiveButton.sfSymbol({
    super.key,
    required this.onPressed,
    required this.sfSymbol,
    this.color,
    this.style = platform_ui.AdaptiveButtonStyle.glass,
    this.size = platform_ui.AdaptiveButtonSize.medium,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.enabled = true,
    this.useSmoothRectangleBorder = true,
  })  : label = null,
        textColor = null,
        child = null,
        icon = null,
        iconColor = null;

  final VoidCallback? onPressed;
  final String? label;
  final Widget? child;
  final IconData? icon;
  final platform_ui.SFSymbol? sfSymbol;
  final Color? color;
  final Color? textColor;
  final Color? iconColor;
  final platform_ui.AdaptiveButtonStyle style;
  final platform_ui.AdaptiveButtonSize size;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Size? minSize;
  final bool enabled;
  final bool useSmoothRectangleBorder;

  @override
  Widget build(BuildContext context) {
    if (!_useLiquidGlassFallback(context)) {
      if (sfSymbol != null) {
        return platform_ui.AdaptiveButton.sfSymbol(
          key: key,
          onPressed: onPressed,
          sfSymbol: sfSymbol!,
          color: color,
          style: style,
          size: size,
          padding: padding,
          borderRadius: borderRadius,
          minSize: minSize,
          enabled: enabled,
          useSmoothRectangleBorder: useSmoothRectangleBorder,
        );
      }
      if (child != null) {
        return platform_ui.AdaptiveButton.child(
          key: key,
          onPressed: onPressed,
          color: color,
          style: style,
          size: size,
          padding: padding,
          borderRadius: borderRadius,
          minSize: minSize,
          enabled: enabled,
          useSmoothRectangleBorder: useSmoothRectangleBorder,
          child: child!,
        );
      }
      if (icon != null) {
        return platform_ui.AdaptiveButton.icon(
          key: key,
          onPressed: onPressed,
          icon: icon!,
          color: color,
          iconColor: iconColor,
          style: style,
          size: size,
          padding: padding,
          borderRadius: borderRadius,
          minSize: minSize,
          enabled: enabled,
          useSmoothRectangleBorder: useSmoothRectangleBorder,
        );
      }
      return platform_ui.AdaptiveButton(
        key: key,
        onPressed: onPressed,
        label: label ?? '',
        color: color,
        textColor: textColor,
        style: style,
        size: size,
        padding: padding,
        borderRadius: borderRadius,
        minSize: minSize,
        enabled: enabled,
        useSmoothRectangleBorder: useSmoothRectangleBorder,
      );
    }

    final effectiveOnPressed = enabled ? onPressed : null;
    final fallbackColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final content = Padding(
      padding: padding ?? _defaultPadding(size),
      child: IconTheme(
        data: IconThemeData(color: iconColor ?? fallbackColor, size: 20),
        child: DefaultTextStyle(
          style: TextStyle(
            color: textColor ?? fallbackColor,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          child: _buildContent(fallbackColor),
        ),
      ),
    );
    final radius = borderRadius?.topLeft.x ?? _buttonHeight(size) / 2;

    return Opacity(
      opacity: effectiveOnPressed == null ? 0.45 : 1,
      child: IgnorePointer(
        ignoring: effectiveOnPressed == null,
        child: GlassButton.custom(
          onTap: effectiveOnPressed ?? _noop,
          width: minSize != null && minSize!.width > 0 ? minSize!.width : null,
          height: minSize != null && minSize!.height > 0
              ? minSize!.height
              : _buttonHeight(size),
          useOwnLayer: true,
          quality: GlassQuality.standard,
          style: _glassButtonStyle(style),
          shape: useSmoothRectangleBorder
              ? LiquidRoundedSuperellipse(borderRadius: radius)
              : const LiquidOval(),
          settings: color == null
              ? null
              : LiquidGlassSettings(
                  glassColor: color!.withValues(alpha: 0.22),
                ),
          child: content,
        ),
      ),
    );
  }

  Widget _buildContent(Color fallbackColor) {
    if (child != null) return child!;
    if (icon != null) return Icon(icon, color: iconColor ?? fallbackColor);
    if (sfSymbol != null) {
      return Icon(
        _cupertinoIconForSymbol(sfSymbol!.name),
        color: sfSymbol!.color ?? fallbackColor,
        size: sfSymbol!.size,
      );
    }
    return Text(label ?? '');
  }

  static EdgeInsetsGeometry _defaultPadding(
    platform_ui.AdaptiveButtonSize size,
  ) =>
      switch (size) {
        platform_ui.AdaptiveButtonSize.small =>
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        platform_ui.AdaptiveButtonSize.medium =>
          const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        platform_ui.AdaptiveButtonSize.large =>
          const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      };

  static double _buttonHeight(platform_ui.AdaptiveButtonSize size) =>
      switch (size) {
        platform_ui.AdaptiveButtonSize.small => 28,
        platform_ui.AdaptiveButtonSize.medium => 36,
        platform_ui.AdaptiveButtonSize.large => 44,
      };
}

class AdaptiveSwitch extends StatelessWidget {
  const AdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.thumbColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? thumbColor;

  @override
  Widget build(BuildContext context) {
    if (!_useLiquidGlassFallback(context)) {
      return platform_ui.AdaptiveSwitch(
        value: value,
        onChanged: onChanged,
        activeColor: activeColor,
        thumbColor: thumbColor,
      );
    }
    return Opacity(
      opacity: onChanged == null ? 0.45 : 1,
      child: IgnorePointer(
        ignoring: onChanged == null,
        child: GlassSwitch(
          value: value,
          onChanged: onChanged ?? _noopBool,
          activeColor: activeColor ?? CupertinoTheme.of(context).primaryColor,
          thumbColor: thumbColor ?? CupertinoColors.white,
          useOwnLayer: true,
          quality: GlassQuality.standard,
        ),
      ),
    );
  }
}

class AdaptiveSlider extends StatelessWidget {
  const AdaptiveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.activeColor,
    this.thumbColor,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final Color? activeColor;
  final Color? thumbColor;

  @override
  Widget build(BuildContext context) {
    if (!_useLiquidGlassFallback(context)) {
      return platform_ui.AdaptiveSlider(
        value: value,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        activeColor: activeColor,
        thumbColor: thumbColor,
      );
    }
    return GlassSlider(
      value: value,
      onChanged: onChanged,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
      min: min,
      max: max,
      divisions: divisions,
      label: label,
      activeColor: activeColor ?? CupertinoTheme.of(context).primaryColor,
      thumbColor: thumbColor ?? CupertinoColors.white,
      useOwnLayer: true,
      quality: GlassQuality.standard,
    );
  }
}

class AdaptiveSegmentedControl extends StatelessWidget {
  const AdaptiveSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    this.enabled = true,
    this.color,
    this.height = 36,
    this.shrinkWrap = false,
    this.sfSymbols,
    this.iconSize,
    this.iconColor,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onValueChanged;
  final bool enabled;
  final Color? color;
  final double height;
  final bool shrinkWrap;
  final List<dynamic>? sfSymbols;
  final double? iconSize;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    if (!_useLiquidGlassFallback(context)) {
      return platform_ui.AdaptiveSegmentedControl(
        labels: labels,
        selectedIndex: selectedIndex,
        onValueChanged: onValueChanged,
        enabled: enabled,
        color: color,
        height: height,
        shrinkWrap: shrinkWrap,
        sfSymbols: sfSymbols,
        iconSize: iconSize,
        iconColor: iconColor,
      );
    }

    final segments = <GlassSegment>[
      for (var index = 0; index < labels.length; index++)
        GlassSegment(
          label: labels[index].isEmpty ? null : labels[index],
          icon: _segmentIcon(index),
          enabled: enabled,
        ),
    ];
    Widget control = GlassSegmentedControl(
      segments: segments,
      selectedIndex: selectedIndex,
      onSegmentSelected: enabled ? onValueChanged : _noopInt,
      height: height,
      indicatorColor: color?.withValues(alpha: 0.22),
      selectedIconColor: iconColor,
      unselectedIconColor: iconColor,
      useOwnLayer: true,
      quality: GlassQuality.standard,
    );
    if (shrinkWrap) {
      control = Center(child: IntrinsicWidth(child: control));
    }
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(opacity: enabled ? 1 : 0.45, child: control),
    );
  }

  Widget? _segmentIcon(int index) {
    if (sfSymbols == null || index >= sfSymbols!.length) return null;
    final symbol = sfSymbols![index];
    if (symbol is IconData) {
      return Icon(symbol, size: iconSize, color: iconColor);
    }
    if (symbol is String) {
      return Icon(
        _cupertinoIconForSymbol(symbol),
        size: iconSize,
        color: iconColor,
      );
    }
    return null;
  }
}

class AdaptiveAlertDialog {
  AdaptiveAlertDialog._();

  static Future<void> show({
    required BuildContext context,
    required String title,
    String? message,
    required List<platform_ui.AlertAction> actions,
    dynamic icon,
    double? iconSize,
    Color? iconColor,
    String? oneTimeCode,
  }) async {
    if (!_useLiquidGlassFallback(context)) {
      return platform_ui.AdaptiveAlertDialog.show(
        context: context,
        title: title,
        message: message,
        actions: actions,
        icon: icon,
        iconSize: iconSize,
        iconColor: iconColor,
        oneTimeCode: oneTimeCode,
      );
    }
    await GlassDialog.show<void>(
      context: context,
      title: title,
      message: message,
      content: _dialogContent(
        context,
        icon: icon,
        iconSize: iconSize,
        iconColor: iconColor,
        oneTimeCode: oneTimeCode,
      ),
      actions: _glassActions<void>(context, actions),
    );
  }

  static Future<String?> inputShow({
    required BuildContext context,
    required String title,
    String? message,
    required List<platform_ui.AlertAction> actions,
    required platform_ui.AdaptiveAlertDialogInput input,
    dynamic icon,
    double? iconSize,
    Color? iconColor,
    bool allowEmpty = false,
  }) async {
    if (!_useLiquidGlassFallback(context)) {
      return platform_ui.AdaptiveAlertDialog.inputShow(
        context: context,
        title: title,
        message: message,
        actions: actions,
        input: input,
        icon: icon,
        iconSize: iconSize,
        iconColor: iconColor,
      );
    }

    final controller = TextEditingController(text: input.initialValue);
    try {
      return await GlassDialog.show<String?>(
        context: context,
        title: title,
        message: message,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_dialogContent(
              context,
              icon: icon,
              iconSize: iconSize,
              iconColor: iconColor,
            )
                case final content?) ...[
              content,
              const SizedBox(height: 12),
            ],
            GlassTextField(
              controller: controller,
              placeholder: input.placeholder,
              keyboardType: input.keyboardType,
              obscureText: input.obscureText,
              maxLength: input.maxLength,
              autofocus: true,
            ),
          ],
        ),
        actions: _glassActions<String?>(
          context,
          actions,
          resultForAction: (action) {
            if (action.style == platform_ui.AlertActionStyle.cancel) {
              return null;
            }
            final value = controller.text.trim();
            return value.isEmpty && !allowEmpty ? null : value;
          },
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  static Widget? _dialogContent(
    BuildContext context, {
    dynamic icon,
    double? iconSize,
    Color? iconColor,
    String? oneTimeCode,
  }) {
    if ((icon == null || icon is! IconData) && oneTimeCode == null) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon is IconData) ...[
          Icon(
            icon,
            size: iconSize ?? 28,
            color: iconColor ?? CupertinoTheme.of(context).primaryColor,
          ),
          const SizedBox(height: 10),
        ],
        if (oneTimeCode != null)
          Text(
            oneTimeCode,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  static List<GlassDialogAction> _glassActions<T>(
    BuildContext context,
    List<platform_ui.AlertAction> actions, {
    T Function(platform_ui.AlertAction action)? resultForAction,
  }) {
    return [
      for (final action in actions)
        GlassDialogAction(
          label: action.title,
          isPrimary: action.style == platform_ui.AlertActionStyle.primary,
          isDestructive:
              action.style == platform_ui.AlertActionStyle.destructive,
          onPressed: action.enabled
              ? () {
                  Navigator.of(context).pop<T>(resultForAction?.call(action));
                  action.onPressed();
                }
              : _noop,
        ),
    ];
  }
}

GlassButtonStyle _glassButtonStyle(platform_ui.AdaptiveButtonStyle style) {
  return switch (style) {
    platform_ui.AdaptiveButtonStyle.prominentGlass ||
    platform_ui.AdaptiveButtonStyle.filled =>
      GlassButtonStyle.prominent,
    platform_ui.AdaptiveButtonStyle.plain => GlassButtonStyle.transparent,
    _ => GlassButtonStyle.filled,
  };
}

IconData _cupertinoIconForSymbol(String symbol) => switch (symbol) {
      'chevron.left' => CupertinoIcons.chevron_back,
      'chevron.right' => CupertinoIcons.chevron_forward,
      'xmark' => CupertinoIcons.xmark,
      'checkmark' => CupertinoIcons.check_mark,
      'plus' || 'plus.circle' => CupertinoIcons.add,
      'trash' => CupertinoIcons.delete,
      _ => CupertinoIcons.circle,
    };

void _noop() {}
void _noopBool(bool _) {}
void _noopInt(int _) {}

/// 在手机布局下劫持 AdaptiveSnackBar，统一使用 Nipaplay 的通知控件。
class AdaptiveSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    AdaptiveSnackBarType type = AdaptiveSnackBarType.info,
    Duration duration = const Duration(seconds: 4),
    String? action,
    VoidCallback? onActionPressed,
  }) {
    // 目前 Nipaplay 通知不区分类型颜色，直接沿用统一样式。
    BlurSnackBar.show(
      context,
      message,
      actionText: action,
      onAction: onActionPressed,
      duration: duration,
    );
  }
}
