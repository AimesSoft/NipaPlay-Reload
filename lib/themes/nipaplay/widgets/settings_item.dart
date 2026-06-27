import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_editable_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

Color get _fluentAccentColor => AppAccentColors.current;

/// 设置项的类型枚举
enum SettingsItemType {
  /// 下拉菜单类型
  dropdown,

  /// 开关类型
  toggle,

  /// 按钮类型（可点击执行操作）
  button,

  /// 滑块类型
  slider,

  /// 快捷键设置类型
  hotkey,
}

/// 统一的设置项组件
///
/// 支持多种类型的设置项：
/// - 下拉菜单（dropdown）
/// - 开关（toggle）
/// - 按钮（button）
/// - 滑块（slider）
/// - 快捷键设置（hotkey）
class SettingsItem extends StatelessWidget {
  /// 设置项标题
  final String title;

  /// 设置项描述
  final String? subtitle;

  /// 设置项类型
  final SettingsItemType type;

  /// 图标（可选）
  final IconData? icon;

  /// 是否启用，默认为true
  final bool enabled;

  // === 下拉菜单相关参数 ===
  /// 下拉菜单的选项列表
  final List<DropdownMenuItemData>? dropdownItems;

  /// 下拉菜单选择回调
  final FutureOr<void> Function(dynamic)? onDropdownChanged;

  /// 下拉菜单的GlobalKey
  final GlobalKey? dropdownKey;

  // === 开关相关参数 ===
  /// 开关的当前值
  final bool? switchValue;

  /// 开关状态改变回调
  final Function(bool)? onSwitchChanged;

  // === 按钮相关参数 ===
  /// 按钮点击回调
  final VoidCallback? onTap;

  /// 按钮右侧图标（默认为箭头）
  final IconData? trailingIcon;

  /// 按钮是否为危险操作（使用红色图标）
  final bool isDestructive;

  // === 滑块相关参数 ===
  /// 滑块当前值
  final double? sliderValue;

  /// 滑块最小值
  final double? sliderMin;

  /// 滑块最大值
  final double? sliderMax;

  /// 滑块分段数量
  final int? sliderDivisions;

  /// 滑块值改变回调
  final Function(double)? onSliderChanged;

  /// 滑块值格式化函数
  final String Function(double)? sliderLabelFormatter;

  // === 快捷键相关参数 ===
  /// 当前快捷键文本
  final String? hotkeyText;

  /// 是否正在录制快捷键
  final bool isRecording;

  /// 快捷键点击回调
  final VoidCallback? onHotkeyTap;

  const SettingsItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.type,
    this.icon,
    this.enabled = true,
    // 下拉菜单
    this.dropdownItems,
    this.onDropdownChanged,
    this.dropdownKey,
    // 开关
    this.switchValue,
    this.onSwitchChanged,
    // 按钮
    this.onTap,
    this.trailingIcon,
    this.isDestructive = false,
    // 滑块
    this.sliderValue,
    this.sliderMin,
    this.sliderMax,
    this.sliderDivisions,
    this.onSliderChanged,
    this.sliderLabelFormatter,
    // 快捷键
    this.hotkeyText,
    this.isRecording = false,
    this.onHotkeyTap,
  });

  /// 创建下拉菜单类型的设置项
  factory SettingsItem.dropdown({
    required String title,
    String? subtitle,
    IconData? icon,
    bool enabled = true,
    required List<DropdownMenuItemData> items,
    required FutureOr<void> Function(dynamic) onChanged,
    GlobalKey? dropdownKey,
  }) {
    return SettingsItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      enabled: enabled,
      type: SettingsItemType.dropdown,
      dropdownItems: items,
      onDropdownChanged: onChanged,
      dropdownKey: dropdownKey,
    );
  }

  /// 创建开关类型的设置项
  factory SettingsItem.toggle({
    required String title,
    String? subtitle,
    IconData? icon,
    bool enabled = true,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return SettingsItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      enabled: enabled,
      type: SettingsItemType.toggle,
      switchValue: value,
      onSwitchChanged: onChanged,
    );
  }

  /// 创建按钮类型的设置项
  factory SettingsItem.button({
    required String title,
    String? subtitle,
    IconData? icon,
    bool enabled = true,
    required VoidCallback onTap,
    IconData? trailingIcon,
    bool isDestructive = false,
  }) {
    return SettingsItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      enabled: enabled,
      type: SettingsItemType.button,
      onTap: onTap,
      trailingIcon: trailingIcon,
      isDestructive: isDestructive,
    );
  }

  /// 创建滑块类型的设置项
  factory SettingsItem.slider({
    required String title,
    String? subtitle,
    IconData? icon,
    bool enabled = true,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required Function(double) onChanged,
    String Function(double)? labelFormatter,
  }) {
    return SettingsItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      enabled: enabled,
      type: SettingsItemType.slider,
      sliderValue: value,
      sliderMin: min,
      sliderMax: max,
      sliderDivisions: divisions,
      onSliderChanged: onChanged,
      sliderLabelFormatter: labelFormatter,
    );
  }

  /// 创建快捷键类型的设置项
  factory SettingsItem.hotkey({
    required String title,
    String? subtitle,
    IconData? icon,
    bool enabled = true,
    required String hotkeyText,
    bool isRecording = false,
    required VoidCallback onTap,
  }) {
    return SettingsItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      enabled: enabled,
      type: SettingsItemType.hotkey,
      hotkeyText: hotkeyText,
      isRecording: isRecording,
      onHotkeyTap: onTap,
    );
  }

  Widget? _buildDropdownSubtitle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final List<DropdownMenuItemData> items =
        dropdownItems ?? const <DropdownMenuItemData>[];
    final descriptionItems = items
        .where((item) =>
            item.description != null && item.description!.trim().isNotEmpty)
        .toList();

    if (subtitle == null && descriptionItems.isEmpty) {
      return null;
    }

    final subtitleStyle = TextStyle(
      color: enabled
          ? colorScheme.onSurface.withOpacity(0.7)
          : colorScheme.onSurface.withOpacity(0.38),
    );
    final descriptionStyle = TextStyle(
      fontSize: 12,
      height: 1.3,
      color: enabled
          ? colorScheme.onSurface.withOpacity(0.6)
          : colorScheme.onSurface.withOpacity(0.38),
    );

    final List<Widget> children = [];
    if (subtitle != null) {
      children.add(
        Text(
          subtitle!,
          locale: const Locale("zh-Hans", "zh"),
          style: subtitleStyle,
        ),
      );
    }

    if (descriptionItems.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(SizedBox(height: 4));
      }
      for (int i = 0; i < descriptionItems.length; i++) {
        final item = descriptionItems[i];
        children.add(
          Text(
            '${item.title}: ${item.description!.trim()}',
            locale: const Locale("zh-Hans", "zh"),
            style: descriptionStyle,
          ),
        );
        if (i != descriptionItems.length - 1) {
          children.add(SizedBox(height: 2));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  bool _hasDropdownDescriptions() {
    final List<DropdownMenuItemData> items =
        dropdownItems ?? const <DropdownMenuItemData>[];
    return items.any((item) =>
        item.description != null && item.description!.trim().isNotEmpty);
  }

  Color _largeScreenTextColor(BuildContext context, {double alpha = 1.0}) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF171A22);
    return color.withValues(alpha: enabled ? alpha : alpha * 0.54);
  }

  Widget _largeScreenIcon(BuildContext context) {
    if (icon == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Icon(
        icon,
        size: 24,
        color: _largeScreenTextColor(context, alpha: 0.70),
      ),
    );
  }

  Widget _largeScreenTextBlock(
    BuildContext context, {
    Widget? customSubtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          locale: const Locale("zh-Hans", "zh"),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _largeScreenTextColor(context),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (customSubtitle != null) ...[
          const SizedBox(height: 5),
          DefaultTextStyle.merge(
            style: TextStyle(
              color: _largeScreenTextColor(context, alpha: 0.62),
              fontSize: 13,
              height: 1.28,
              fontWeight: FontWeight.w600,
            ),
            child: customSubtitle,
          ),
        ] else if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            locale: const Locale("zh-Hans", "zh"),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _largeScreenTextColor(context, alpha: 0.62),
              fontSize: 13,
              height: 1.28,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLargeScreenRow(
    BuildContext context, {
    required Widget trailing,
    VoidCallback? onActivate,
    Widget? customSubtitle,
    bool isDestructiveAction = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDestructiveAction
        ? (enabled
            ? Colors.redAccent
            : Colors.redAccent.withValues(alpha: 0.38))
        : _largeScreenTextColor(context);
    final mutedForeground = isDestructiveAction
        ? foreground.withValues(alpha: 0.72)
        : _largeScreenTextColor(context, alpha: 0.70);
    final idleBackground = isDark
        ? Colors.white.withValues(alpha: 0.040)
        : Colors.black.withValues(alpha: 0.035);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: NipaplayLargeScreenFocusableAction(
        onActivate: enabled ? onActivate : null,
        borderRadius: BorderRadius.circular(8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        style: NipaplayLargeScreenFocusableStyle(
          idleBackgroundDark: idleBackground,
          idleBackgroundLight: idleBackground,
          contentColorDark: foreground,
          contentColorLight: foreground,
          focusStrokeColor: isDestructiveAction ? Colors.redAccent : null,
        ),
        focusScale: 1.012,
        child: Row(
          children: [
            _largeScreenIcon(context),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: mutedForeground),
                child: _largeScreenTextBlock(
                  context,
                  customSubtitle: customSubtitle,
                ),
              ),
            ),
            const SizedBox(width: 18),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildLargeScreen(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (type) {
      case SettingsItemType.dropdown:
        final dropdown =
            enabled && dropdownItems != null && onDropdownChanged != null
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: BlurDropdown(
                      dropdownKey: dropdownKey ?? GlobalKey(),
                      items: dropdownItems!,
                      onItemSelected: onDropdownChanged!,
                    ),
                  )
                : const SizedBox.shrink();
        return _buildLargeScreenRow(
          context,
          trailing: dropdown,
          customSubtitle: _buildDropdownSubtitle(context),
        );
      case SettingsItemType.toggle:
        final currentValue = switchValue ?? false;
        return _buildLargeScreenRow(
          context,
          trailing: FluentSettingsSwitch(
            value: currentValue,
            onChanged: enabled ? onSwitchChanged : null,
          ),
          onActivate: onSwitchChanged != null
              ? () => onSwitchChanged!(!currentValue)
              : null,
        );
      case SettingsItemType.button:
        final trailingColor = isDestructive
            ? (enabled ? Colors.redAccent : Colors.redAccent.withOpacity(0.38))
            : _largeScreenTextColor(context, alpha: 0.74);
        return _buildLargeScreenRow(
          context,
          trailing: Icon(
            trailingIcon ?? Ionicons.chevron_forward_outline,
            color: trailingColor,
            size: 24,
          ),
          onActivate: onTap,
          isDestructiveAction: isDestructive,
        );
      case SettingsItemType.slider:
        final double min = sliderMin ?? 0;
        final double max = sliderMax ?? 1;
        final double current = sliderValue ?? min;
        final int? divisions = sliderDivisions;
        final double step = (divisions != null && divisions > 0)
            ? ((max - min) / divisions)
            : ((max - min) / 20);
        final bool canAdjustByEnter =
            enabled && onSliderChanged != null && max > min && step > 0;
        final valueLabel = sliderLabelFormatter?.call(sliderValue ?? 0) ??
            (sliderValue ?? 0).toStringAsFixed(1);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: NipaplayLargeScreenFocusableAction(
            onActivate: canAdjustByEnter
                ? () {
                    double next = current + step;
                    if (next > max) {
                      next = min;
                    }
                    onSliderChanged!(next.clamp(min, max).toDouble());
                  }
                : null,
            borderRadius: BorderRadius.circular(8),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            focusScale: 1.012,
            style: NipaplayLargeScreenFocusableStyle(
              idleBackgroundDark: Colors.white.withValues(alpha: 0.040),
              idleBackgroundLight: Colors.black.withValues(alpha: 0.035),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _largeScreenIcon(context),
                    Expanded(child: _largeScreenTextBlock(context)),
                    const SizedBox(width: 18),
                    Text(
                      valueLabel,
                      locale: const Locale("zh-Hans", "zh"),
                      style: TextStyle(
                        color: _largeScreenTextColor(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                fluent.FluentTheme(
                  data: fluent.FluentThemeData(
                    brightness: Theme.of(context).brightness,
                    accentColor: fluent.AccentColor.swatch({
                      'normal': _fluentAccentColor,
                      'default': _fluentAccentColor,
                    }),
                  ),
                  child: NipaplayLargeScreenEditableSlider(
                    value: current,
                    min: min,
                    max: max,
                    divisions: sliderDivisions,
                    onChanged: enabled ? onSliderChanged : null,
                    label: sliderLabelFormatter?.call(sliderValue ?? 0),
                  ),
                ),
              ],
            ),
          ),
        );
      case SettingsItemType.hotkey:
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final hotkeyTextColor =
            isRecording ? Colors.redAccent : _largeScreenTextColor(context);
        return _buildLargeScreenRow(
          context,
          trailing: Container(
            constraints: const BoxConstraints(minWidth: 92),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isRecording
                    ? Colors.redAccent
                    : colorScheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
            child: Text(
              isRecording ? '按任意键...' : (hotkeyText ?? '未设置'),
              locale: const Locale("zh-Hans", "zh"),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: hotkeyTextColor,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          onActivate: onHotkeyTap,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (NipaplayLargeScreenModeScope.isActiveOf(context)) {
      return _buildLargeScreen(context);
    }

    final colorScheme = Theme.of(context).colorScheme;

    switch (type) {
      case SettingsItemType.dropdown:
        final bool alignDropdownToTop = _hasDropdownDescriptions();
        return ListTile(
          titleAlignment:
              alignDropdownToTop ? ListTileTitleAlignment.top : null,
          leading: icon != null
              ? Icon(icon, color: colorScheme.onSurface.withOpacity(0.7))
              : null,
          title: Text(
            title,
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withOpacity(0.54),
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: _buildDropdownSubtitle(context),
          trailing: enabled && dropdownItems != null
              ? ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.4,
                  ),
                  child: BlurDropdown(
                    dropdownKey: dropdownKey ?? GlobalKey(),
                    items: dropdownItems!,
                    onItemSelected: onDropdownChanged!,
                  ),
                )
              : null,
          onTap: null,
          enabled: enabled,
        );
      case SettingsItemType.toggle:
        final currentValue = switchValue ?? false;
        return ListTile(
          leading: icon != null
              ? Icon(icon, color: colorScheme.onSurface.withOpacity(0.7))
              : null,
          title: Text(
            title,
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withOpacity(0.54),
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle!,
                  locale: const Locale("zh-Hans", "zh"),
                  style: TextStyle(
                    color: enabled
                        ? colorScheme.onSurface.withOpacity(0.7)
                        : colorScheme.onSurface.withOpacity(0.38),
                  ),
                )
              : null,
          trailing: FluentSettingsSwitch(
            value: currentValue,
            onChanged: enabled ? onSwitchChanged : null,
          ),
          onTap: enabled && onSwitchChanged != null
              ? () => onSwitchChanged!(!currentValue)
              : null,
          enabled: enabled,
        );
      case SettingsItemType.button:
        return ListTile(
          leading: icon != null
              ? Icon(icon, color: colorScheme.onSurface.withOpacity(0.7))
              : null,
          title: Text(
            title,
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withOpacity(0.54),
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle!,
                  locale: const Locale("zh-Hans", "zh"),
                  style: TextStyle(
                    color: enabled
                        ? colorScheme.onSurface.withOpacity(0.7)
                        : colorScheme.onSurface.withOpacity(0.38),
                  ),
                )
              : null,
          trailing: Icon(
            trailingIcon ?? Ionicons.chevron_forward_outline,
            color: isDestructive
                ? (enabled ? Colors.red : Colors.red.withOpacity(0.5))
                : (enabled
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withOpacity(0.54)),
          ),
          onTap: enabled ? onTap : null,
          enabled: enabled,
        );
      case SettingsItemType.slider:
        final double min = sliderMin ?? 0;
        final double max = sliderMax ?? 1;
        final double current = sliderValue ?? min;
        final int? divisions = sliderDivisions;
        final double step = (divisions != null && divisions > 0)
            ? ((max - min) / divisions)
            : ((max - min) / 20);
        final bool canAdjustByEnter =
            enabled && onSliderChanged != null && max > min && step > 0;
        return Column(
          children: [
            ListTile(
              leading: icon != null
                  ? Icon(icon, color: colorScheme.onSurface.withOpacity(0.7))
                  : null,
              title: Text(
                title,
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: enabled
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withOpacity(0.54),
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: subtitle != null
                  ? Text(
                      subtitle!,
                      locale: const Locale("zh-Hans", "zh"),
                      style: TextStyle(
                        color: enabled
                            ? colorScheme.onSurface.withOpacity(0.7)
                            : colorScheme.onSurface.withOpacity(0.38),
                      ),
                    )
                  : null,
              trailing: Text(
                sliderLabelFormatter?.call(sliderValue ?? 0) ??
                    (sliderValue ?? 0).toStringAsFixed(1),
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: enabled
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withOpacity(0.54),
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: canAdjustByEnter
                  ? () {
                      double next = current + step;
                      if (next > max) {
                        next = min;
                      }
                      onSliderChanged!(next.clamp(min, max));
                    }
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: fluent.FluentTheme(
                data: fluent.FluentThemeData(
                  brightness: Theme.of(context).brightness,
                  accentColor: fluent.AccentColor.swatch({
                    'normal': _fluentAccentColor,
                    'default': _fluentAccentColor,
                  }),
                ),
                child: NipaplayLargeScreenEditableSlider(
                  value: current,
                  min: min,
                  max: max,
                  divisions: sliderDivisions,
                  onChanged: enabled ? onSliderChanged : null,
                  label: sliderLabelFormatter?.call(sliderValue ?? 0),
                ),
              ),
            ),
          ],
        );
      case SettingsItemType.hotkey:
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color hotkeyBackgroundColor =
            isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final Color hotkeyBorderColor = isRecording
            ? Colors.red
            : (isDark ? Colors.white24 : Colors.black12);
        final Color hotkeyTextColor = isRecording
            ? Colors.red
            : (enabled
                ? colorScheme.onSurface
                : colorScheme.onSurface.withOpacity(0.54));

        return ListTile(
          leading: icon != null
              ? Icon(icon, color: colorScheme.onSurface.withOpacity(0.7))
              : null,
          title: Text(
            title,
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withOpacity(0.54),
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle!,
                  locale: const Locale("zh-Hans", "zh"),
                  style: TextStyle(
                    color: enabled
                        ? colorScheme.onSurface.withOpacity(0.7)
                        : colorScheme.onSurface.withOpacity(0.38),
                  ),
                )
              : null,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: hotkeyBackgroundColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hotkeyBorderColor,
                width: 1,
              ),
            ),
            child: Text(
              isRecording ? '按任意键...' : (hotkeyText ?? '未设置'),
              locale: const Locale("zh-Hans", "zh"),
              style: TextStyle(
                color: hotkeyTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          onTap: enabled ? onHotkeyTap : null,
          enabled: enabled,
        );
    }
  }

  // Remove the unused private _build methods
}
