import 'dart:async';

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart' as material;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart'
    show AdaptiveSlider, AdaptiveSwitch;
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class AdaptiveSettingsTile<T> extends material.StatelessWidget {
  const AdaptiveSettingsTile._({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.phoneIcon,
    required this.type,
    this.enabled = true,
    this.dropdownItems,
    this.onDropdownChanged,
    this.dropdownKey,
    this.switchValue,
    this.onSwitchChanged,
    this.onTap,
    this.trailingIcon,
    this.phoneTrailingIcon,
    this.isDestructive = false,
    this.sliderValue,
    this.sliderMin,
    this.sliderMax,
    this.sliderDivisions,
    this.onSliderChanged,
    this.sliderLabelFormatter,
    this.hotkeyText,
    this.isRecording = false,
    this.onHotkeyTap,
  });

  factory AdaptiveSettingsTile.dropdown({
    material.Key? key,
    required String title,
    String? subtitle,
    material.IconData? icon,
    material.IconData? phoneIcon,
    bool enabled = true,
    required List<DropdownMenuItemData<T>> items,
    required FutureOr<void> Function(T value) onChanged,
    material.GlobalKey? dropdownKey,
  }) {
    return AdaptiveSettingsTile<T>._(
      key: key,
      title: title,
      subtitle: subtitle,
      icon: icon,
      phoneIcon: phoneIcon,
      enabled: enabled,
      type: SettingsItemType.dropdown,
      dropdownItems: items,
      onDropdownChanged: onChanged,
      dropdownKey: dropdownKey,
    );
  }

  factory AdaptiveSettingsTile.toggle({
    material.Key? key,
    required String title,
    String? subtitle,
    material.IconData? icon,
    material.IconData? phoneIcon,
    bool enabled = true,
    required bool value,
    required material.ValueChanged<bool> onChanged,
  }) {
    return AdaptiveSettingsTile<T>._(
      key: key,
      title: title,
      subtitle: subtitle,
      icon: icon,
      phoneIcon: phoneIcon,
      enabled: enabled,
      type: SettingsItemType.toggle,
      switchValue: value,
      onSwitchChanged: onChanged,
    );
  }

  factory AdaptiveSettingsTile.card({
    material.Key? key,
    required String title,
    String? subtitle,
    material.IconData? icon,
    material.IconData? phoneIcon,
    bool enabled = true,
    required material.VoidCallback onTap,
    material.IconData? trailingIcon,
    material.IconData? phoneTrailingIcon,
    bool isDestructive = false,
  }) {
    return AdaptiveSettingsTile<T>._(
      key: key,
      title: title,
      subtitle: subtitle,
      icon: icon,
      phoneIcon: phoneIcon,
      enabled: enabled,
      type: SettingsItemType.button,
      onTap: onTap,
      trailingIcon: trailingIcon,
      phoneTrailingIcon: phoneTrailingIcon,
      isDestructive: isDestructive,
    );
  }

  factory AdaptiveSettingsTile.button({
    material.Key? key,
    required String title,
    String? subtitle,
    material.IconData? icon,
    material.IconData? phoneIcon,
    bool enabled = true,
    required material.VoidCallback onTap,
    material.IconData? trailingIcon,
    material.IconData? phoneTrailingIcon,
    bool isDestructive = false,
  }) {
    return AdaptiveSettingsTile<T>.card(
      key: key,
      title: title,
      subtitle: subtitle,
      icon: icon,
      phoneIcon: phoneIcon,
      enabled: enabled,
      onTap: onTap,
      trailingIcon: trailingIcon,
      phoneTrailingIcon: phoneTrailingIcon,
      isDestructive: isDestructive,
    );
  }

  factory AdaptiveSettingsTile.slider({
    material.Key? key,
    required String title,
    String? subtitle,
    material.IconData? icon,
    material.IconData? phoneIcon,
    bool enabled = true,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required material.ValueChanged<double> onChanged,
    String Function(double value)? labelFormatter,
  }) {
    return AdaptiveSettingsTile<T>._(
      key: key,
      title: title,
      subtitle: subtitle,
      icon: icon,
      phoneIcon: phoneIcon,
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

  factory AdaptiveSettingsTile.hotkey({
    material.Key? key,
    required String title,
    String? subtitle,
    material.IconData? icon,
    material.IconData? phoneIcon,
    bool enabled = true,
    required String hotkeyText,
    bool isRecording = false,
    required material.VoidCallback onTap,
  }) {
    return AdaptiveSettingsTile<T>._(
      key: key,
      title: title,
      subtitle: subtitle,
      icon: icon,
      phoneIcon: phoneIcon,
      enabled: enabled,
      type: SettingsItemType.hotkey,
      hotkeyText: hotkeyText,
      isRecording: isRecording,
      onHotkeyTap: onTap,
    );
  }

  final String title;
  final String? subtitle;
  final material.IconData? icon;
  final material.IconData? phoneIcon;
  final SettingsItemType type;
  final bool enabled;
  final List<DropdownMenuItemData<T>>? dropdownItems;
  final FutureOr<void> Function(T value)? onDropdownChanged;
  final material.GlobalKey? dropdownKey;
  final bool? switchValue;
  final material.ValueChanged<bool>? onSwitchChanged;
  final material.VoidCallback? onTap;
  final material.IconData? trailingIcon;
  final material.IconData? phoneTrailingIcon;
  final bool isDestructive;
  final double? sliderValue;
  final double? sliderMin;
  final double? sliderMax;
  final int? sliderDivisions;
  final material.ValueChanged<double>? onSliderChanged;
  final String Function(double value)? sliderLabelFormatter;
  final String? hotkeyText;
  final bool isRecording;
  final material.VoidCallback? onHotkeyTap;

  @override
  material.Widget build(material.BuildContext context) {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      return _buildPhone(context);
    }

    switch (type) {
      case SettingsItemType.dropdown:
        return SettingsItem.dropdown(
          title: title,
          subtitle: subtitle,
          icon: icon,
          enabled: enabled,
          items: dropdownItems ?? <DropdownMenuItemData<T>>[],
          onChanged: (value) => onDropdownChanged?.call(value as T),
          dropdownKey: dropdownKey,
        );
      case SettingsItemType.toggle:
        return SettingsItem.toggle(
          title: title,
          subtitle: subtitle,
          icon: icon,
          enabled: enabled,
          value: switchValue ?? false,
          onChanged: (value) => onSwitchChanged?.call(value),
        );
      case SettingsItemType.button:
        return SettingsItem.button(
          title: title,
          subtitle: subtitle,
          icon: icon,
          enabled: enabled,
          onTap: onTap ?? () {},
          trailingIcon: trailingIcon,
          isDestructive: isDestructive,
        );
      case SettingsItemType.slider:
        return SettingsItem.slider(
          title: title,
          subtitle: subtitle,
          icon: icon,
          enabled: enabled,
          value: sliderValue ?? sliderMin ?? 0,
          min: sliderMin ?? 0,
          max: sliderMax ?? 1,
          divisions: sliderDivisions,
          onChanged: (value) => onSliderChanged?.call(value),
          labelFormatter: sliderLabelFormatter,
        );
      case SettingsItemType.hotkey:
        return SettingsItem.hotkey(
          title: title,
          subtitle: subtitle,
          icon: icon,
          enabled: enabled,
          hotkeyText: hotkeyText ?? '',
          isRecording: isRecording,
          onTap: onHotkeyTap ?? () {},
        );
    }
  }

  material.Widget _buildPhone(material.BuildContext context) {
    final backgroundColor = resolveSettingsTileBackground(context);

    switch (type) {
      case SettingsItemType.dropdown:
        return CupertinoSettingsTile(
          leading: _buildPhoneLeading(context),
          title: material.Text(title),
          subtitle: _buildPhoneSubtitle(),
          trailing: enabled ? _buildPhoneDropdown(context) : null,
          backgroundColor: backgroundColor,
        );
      case SettingsItemType.toggle:
        final value = switchValue ?? false;
        return CupertinoSettingsTile(
          leading: _buildPhoneLeading(context),
          title: material.Text(title),
          subtitle: _buildPhoneSubtitle(),
          trailing: AdaptiveSwitch(
            value: value,
            onChanged: enabled ? onSwitchChanged : null,
          ),
          onTap: enabled && onSwitchChanged != null
              ? () => onSwitchChanged!(!value)
              : null,
          backgroundColor: backgroundColor,
        );
      case SettingsItemType.button:
        return CupertinoSettingsTile(
          leading: _buildPhoneLeading(context),
          title: material.Text(title),
          subtitle: _buildPhoneSubtitle(),
          trailing: phoneTrailingIcon != null || trailingIcon != null
              ? material.Icon(
                  phoneTrailingIcon ?? trailingIcon,
                  size: 18,
                  color: _phoneTrailingColor(context),
                )
              : null,
          showChevron: phoneTrailingIcon == null && trailingIcon == null,
          onTap: enabled ? onTap : null,
          backgroundColor: backgroundColor,
        );
      case SettingsItemType.slider:
        return _buildPhoneSlider(context, backgroundColor);
      case SettingsItemType.hotkey:
        return CupertinoSettingsTile(
          leading: _buildPhoneLeading(context),
          title: material.Text(title),
          subtitle: _buildPhoneSubtitle(),
          trailing: _buildHotkeyChip(context),
          onTap: enabled ? onHotkeyTap : null,
          backgroundColor: backgroundColor,
        );
    }
  }

  material.Widget? _buildPhoneLeading(material.BuildContext context) {
    final resolvedIcon = phoneIcon ?? icon;
    if (resolvedIcon == null) {
      return null;
    }
    return material.Icon(
      resolvedIcon,
      color: enabled
          ? resolveSettingsIconColor(context)
          : resolveSettingsIconColor(context).withValues(alpha: 0.42),
    );
  }

  material.Widget? _buildPhoneSubtitle() {
    if (subtitle == null || subtitle!.trim().isEmpty) {
      return null;
    }
    return material.Text(subtitle!);
  }

  material.Widget _buildPhoneDropdown(material.BuildContext context) {
    final items = dropdownItems ?? <DropdownMenuItemData<T>>[];
    DropdownMenuItemData<T>? selected;
    for (final item in items) {
      if (item.isSelected) {
        selected = item;
        break;
      }
    }
    final label =
        selected?.title ?? (items.isNotEmpty ? items.first.title : '');
    return cupertino.CupertinoButton(
      padding: material.EdgeInsets.zero,
      minimumSize: material.Size.zero,
      onPressed: items.isEmpty
          ? null
          : () async {
              final selectedIndex =
                  await CupertinoBottomSheet.showSelection<int>(
                context: context,
                title: title,
                options: [
                  for (final entry in items.asMap().entries)
                    CupertinoBottomSheetOption(
                      label: entry.value.title,
                      value: entry.key,
                      selected: entry.value.isSelected,
                      enabled: entry.value.enabled,
                    ),
                ],
              );
              if (selectedIndex != null) {
                onDropdownChanged?.call(items[selectedIndex].value);
              }
            },
      child: _PhoneMenuChip(label: label),
    );
  }

  material.Widget _buildPhoneSlider(
    material.BuildContext context,
    material.Color backgroundColor,
  ) {
    final min = sliderMin ?? 0;
    final max = sliderMax ?? 1;
    final current = (sliderValue ?? min).clamp(min, max).toDouble();
    final label =
        sliderLabelFormatter?.call(current) ?? current.toStringAsFixed(1);
    final slider = _buildPhonePlatformSlider(
      context,
      value: current,
      min: min,
      max: max,
      divisions: sliderDivisions,
      label: label,
    );

    return material.ColoredBox(
      color: backgroundColor,
      child: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        children: [
          CupertinoSettingsTile(
            leading: _buildPhoneLeading(context),
            title: material.Text(title),
            subtitle: _buildPhoneSubtitle(),
            trailing: material.Text(label),
            backgroundColor: backgroundColor,
          ),
          material.Padding(
            padding: const material.EdgeInsets.fromLTRB(56, 0, 16, 12),
            child: slider,
          ),
        ],
      ),
    );
  }

  material.Widget _buildPhonePlatformSlider(
    material.BuildContext context, {
    required double value,
    required double min,
    required double max,
    int? divisions,
    String? label,
  }) {
    final onChanged = enabled ? onSliderChanged : null;
    return AdaptiveSlider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      label: label,
      activeColor: AppAccentColors.current,
      onChanged: onChanged,
    );
  }

  material.Widget _buildHotkeyChip(material.BuildContext context) {
    final color = isRecording
        ? cupertino.CupertinoColors.systemRed.resolveFrom(context)
        : resolveSettingsPrimaryTextColor(context);
    final borderColor = isRecording
        ? color
        : resolveSettingsSeparatorColor(context).withValues(alpha: 0.9);

    return material.Container(
      padding: const material.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: material.BoxDecoration(
        borderRadius: material.BorderRadius.circular(8),
        border: material.Border.all(color: borderColor),
      ),
      child: material.Text(
        isRecording ? '按任意键...' : (hotkeyText ?? '未设置'),
        style: material.TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: material.FontWeight.w600,
        ),
      ),
    );
  }

  material.Color _phoneTrailingColor(material.BuildContext context) {
    if (isDestructive) {
      return cupertino.CupertinoColors.systemRed.resolveFrom(context);
    }
    return cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.tertiaryLabel,
      context,
    );
  }
}

class AdaptiveSettingsColorOption<T> {
  const AdaptiveSettingsColorOption({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final T value;
  final material.Color color;
}

class AdaptiveSettingsColorTile<T> extends material.StatelessWidget {
  const AdaptiveSettingsColorTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.phoneIcon,
    this.enabled = true,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final material.IconData? icon;
  final material.IconData? phoneIcon;
  final bool enabled;
  final T value;
  final List<AdaptiveSettingsColorOption<T>> options;
  final material.ValueChanged<T> onChanged;

  @override
  material.Widget build(material.BuildContext context) {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      return CupertinoSettingsTile(
        leading: _buildPhoneLeading(context),
        title: material.Text(title),
        subtitle: _buildPhoneSubtitle(),
        trailing: _ColorSwatchGroup<T>(
          enabled: enabled,
          value: value,
          options: options,
          onChanged: onChanged,
          maxWidth: 188,
        ),
        backgroundColor: resolveSettingsTileBackground(context),
      );
    }

    final colorScheme = material.Theme.of(context).colorScheme;
    final titleColor = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.38);
    final subtitleColor = enabled
        ? colorScheme.onSurface.withValues(alpha: 0.7)
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return material.ListTile(
      enabled: enabled,
      leading: icon == null
          ? null
          : material.Icon(
              icon,
              color: colorScheme.onSurface.withValues(
                alpha: enabled ? 0.7 : 0.38,
              ),
            ),
      title: material.Text(
        title,
        locale: const material.Locale('zh-Hans', 'zh'),
        style: material.TextStyle(
          color: titleColor,
          fontWeight: material.FontWeight.bold,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : material.Text(
              subtitle!,
              locale: const material.Locale('zh-Hans', 'zh'),
              style: material.TextStyle(color: subtitleColor),
            ),
      trailing: _ColorSwatchGroup<T>(
        enabled: enabled,
        value: value,
        options: options,
        onChanged: onChanged,
        maxWidth: 220,
      ),
    );
  }

  material.Widget? _buildPhoneLeading(material.BuildContext context) {
    final resolvedIcon = phoneIcon ?? icon;
    if (resolvedIcon == null) {
      return null;
    }
    return material.Icon(
      resolvedIcon,
      color: enabled
          ? resolveSettingsIconColor(context)
          : resolveSettingsIconColor(context).withValues(alpha: 0.42),
    );
  }

  material.Widget? _buildPhoneSubtitle() {
    if (subtitle == null || subtitle!.trim().isEmpty) {
      return null;
    }
    return material.Text(subtitle!);
  }
}

class AdaptiveSettingsSwitch extends material.StatelessWidget {
  const AdaptiveSettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final material.ValueChanged<bool>? onChanged;

  @override
  material.Widget build(material.BuildContext context) {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      return AdaptiveSwitch(
        value: value,
        onChanged: onChanged,
      );
    }

    return FluentSettingsSwitch(
      value: value,
      onChanged: onChanged,
    );
  }
}

class AdaptiveSettingsActionButton extends material.StatelessWidget {
  const AdaptiveSettingsActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final material.VoidCallback? onPressed;
  final material.IconData? icon;
  final bool primary;
  final bool destructive;

  @override
  material.Widget build(material.BuildContext context) {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      final child = _content(
        context,
        color: destructive
            ? cupertino.CupertinoColors.systemRed.resolveFrom(context)
            : null,
      );
      if (primary && !destructive) {
        return cupertino.CupertinoButton.filled(
          padding: const material.EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          onPressed: onPressed,
          child: child,
        );
      }
      return cupertino.CupertinoButton(
        padding: const material.EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        onPressed: onPressed,
        child: child,
      );
    }

    final colorScheme = material.Theme.of(context).colorScheme;
    final idleColor = destructive
        ? material.Colors.redAccent
        : primary
            ? AppAccentColors.current
            : colorScheme.onSurface.withValues(alpha: 0.74);
    final hoverColor =
        destructive ? material.Colors.redAccent : AppAccentColors.current;

    return HoverScaleTextButton(
      onPressed: onPressed,
      idleColor: idleColor,
      hoverColor: hoverColor,
      hoverScale: 1.06,
      child: _content(context),
    );
  }

  material.Widget _content(
    material.BuildContext context, {
    material.Color? color,
  }) {
    final text = material.Text(
      label,
      style: material.TextStyle(
        color: color,
        fontWeight:
            primary ? material.FontWeight.w800 : material.FontWeight.w700,
      ),
    );
    if (icon == null) {
      return text;
    }

    return material.Row(
      mainAxisSize: material.MainAxisSize.min,
      children: [
        material.Icon(icon, size: 16, color: color),
        const material.SizedBox(width: 6),
        text,
      ],
    );
  }
}

class _ColorSwatchGroup<T> extends material.StatelessWidget {
  const _ColorSwatchGroup({
    required this.enabled,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.maxWidth,
  });

  final bool enabled;
  final T value;
  final List<AdaptiveSettingsColorOption<T>> options;
  final material.ValueChanged<T> onChanged;
  final double maxWidth;

  @override
  material.Widget build(material.BuildContext context) {
    return material.ConstrainedBox(
      constraints: material.BoxConstraints(maxWidth: maxWidth),
      child: material.Wrap(
        alignment: material.WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            _ColorSwatch<T>(
              enabled: enabled,
              option: option,
              selected: option.value == value,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _ColorSwatch<T> extends material.StatelessWidget {
  const _ColorSwatch({
    required this.enabled,
    required this.option,
    required this.selected,
    required this.onChanged,
  });

  final bool enabled;
  final AdaptiveSettingsColorOption<T> option;
  final bool selected;
  final material.ValueChanged<T> onChanged;

  @override
  material.Widget build(material.BuildContext context) {
    final checkColor =
        material.ThemeData.estimateBrightnessForColor(option.color) ==
                material.Brightness.dark
            ? material.Colors.white
            : material.Colors.black87;
    final borderColor = selected
        ? AppAccentColors.current
        : material.Theme.of(context)
            .colorScheme
            .onSurface
            .withValues(alpha: 0.22);
    final color = enabled ? option.color : option.color.withValues(alpha: 0.42);

    return material.Tooltip(
      message: option.title,
      child: material.Semantics(
        button: true,
        selected: selected,
        label: option.title,
        child: material.GestureDetector(
          behavior: material.HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged(option.value) : null,
          child: material.AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: material.Curves.easeOutCubic,
            width: 30,
            height: 30,
            decoration: material.BoxDecoration(
              color: color,
              shape: material.BoxShape.circle,
              border: material.Border.all(
                color: borderColor,
                width: selected ? 3 : 1,
              ),
              boxShadow: [
                if (selected)
                  material.BoxShadow(
                    color: AppAccentColors.current.withValues(alpha: 0.22),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: selected
                ? material.Icon(
                    material.Icons.check_rounded,
                    size: 16,
                    color: checkColor,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class AdaptiveSettingsCanvas extends material.StatelessWidget {
  const AdaptiveSettingsCanvas({
    super.key,
    required this.child,
    this.padding = const material.EdgeInsets.all(16),
    this.margin,
  });

  final material.Widget child;
  final material.EdgeInsetsGeometry padding;
  final material.EdgeInsetsGeometry? margin;

  @override
  material.Widget build(material.BuildContext context) {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      return CupertinoSettingsGroupCard(
        margin: margin,
        backgroundColor: resolveSettingsSectionBackground(context),
        children: [
          material.Padding(
            padding: padding,
            child: child,
          ),
        ],
      );
    }

    return SettingsCard(
      margin: margin,
      padding: padding,
      borderRadius: 8,
      child: child,
    );
  }
}

class AdaptiveSettingsDragListItem<T> {
  const AdaptiveSettingsDragListItem({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.phoneIcon,
    this.enabled = true,
  });

  final T value;
  final String title;
  final String? subtitle;
  final material.IconData? icon;
  final material.IconData? phoneIcon;
  final bool enabled;
}

class AdaptiveSettingsDragList<T> extends material.StatelessWidget {
  const AdaptiveSettingsDragList({
    super.key,
    required this.items,
    required this.onReorder,
    this.onEnabledChanged,
  });

  final List<AdaptiveSettingsDragListItem<T>> items;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(T value, bool enabled)? onEnabledChanged;

  @override
  material.Widget build(material.BuildContext context) {
    return AdaptiveSettingsSection(
      addDividers: false,
      children: [
        material.ReorderableListView.builder(
          shrinkWrap: true,
          physics: const material.NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: items.length,
          onReorder: onReorder,
          proxyDecorator: (child, index, animation) {
            return material.Material(
              color: material.Colors.transparent,
              child: material.ScaleTransition(
                scale: material.Tween<double>(begin: 1, end: 1.02).animate(
                  material.CurvedAnimation(
                    parent: animation,
                    curve: material.Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            );
          },
          itemBuilder: (context, index) {
            final item = items[index];
            return _AdaptiveSettingsDragRow<T>(
              key: material.ValueKey(item.value),
              item: item,
              index: index,
              onEnabledChanged: onEnabledChanged,
            );
          },
        ),
      ],
    );
  }
}

class _AdaptiveSettingsDragRow<T> extends material.StatelessWidget {
  const _AdaptiveSettingsDragRow({
    super.key,
    required this.item,
    required this.index,
    this.onEnabledChanged,
  });

  final AdaptiveSettingsDragListItem<T> item;
  final int index;
  final void Function(T value, bool enabled)? onEnabledChanged;

  @override
  material.Widget build(material.BuildContext context) {
    final isPhoneLayout = AdaptiveSettingsScope.isPhoneLayout(context);
    final dragHandle = material.ReorderableDragStartListener(
      index: index,
      child: material.Icon(
        isPhoneLayout
            ? cupertino.CupertinoIcons.line_horizontal_3
            : Ionicons.reorder_three_outline,
        color: isPhoneLayout
            ? resolveSettingsSecondaryTextColor(context)
            : material.Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.62),
      ),
    );
    final toggle = onEnabledChanged == null
        ? null
        : AdaptiveSettingsSwitch(
            value: item.enabled,
            onChanged: (value) => onEnabledChanged!(item.value, value),
          );

    if (isPhoneLayout) {
      return CupertinoSettingsTile(
        leading: _leading(context),
        title: material.Text(item.title),
        subtitle: _subtitle(),
        trailing: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            if (toggle != null) ...[
              toggle,
              const material.SizedBox(width: 12),
            ],
            dragHandle,
          ],
        ),
        backgroundColor: resolveSettingsTileBackground(context),
      );
    }

    return material.ListTile(
      leading: _leading(context),
      title: material.Text(
        item.title,
        locale: const material.Locale('zh-Hans', 'zh'),
        style: const material.TextStyle(fontWeight: material.FontWeight.bold),
      ),
      subtitle: _subtitle(),
      trailing: material.Row(
        mainAxisSize: material.MainAxisSize.min,
        children: [
          if (toggle != null) ...[
            toggle,
            const material.SizedBox(width: 12),
          ],
          dragHandle,
        ],
      ),
    );
  }

  material.Widget? _leading(material.BuildContext context) {
    final isPhoneLayout = AdaptiveSettingsScope.isPhoneLayout(context);
    final icon = isPhoneLayout ? (item.phoneIcon ?? item.icon) : item.icon;
    if (icon == null) {
      return null;
    }
    return material.Icon(
      icon,
      color: isPhoneLayout
          ? resolveSettingsIconColor(context)
          : material.Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.7),
    );
  }

  material.Widget? _subtitle() {
    if (item.subtitle == null || item.subtitle!.trim().isEmpty) {
      return null;
    }
    return material.Text(item.subtitle!);
  }
}

class AdaptiveSettingsSection extends material.StatelessWidget {
  const AdaptiveSettingsSection({
    super.key,
    required this.children,
    this.margin,
    this.addDividers = true,
    this.dividerIndent = 20,
  });

  final List<material.Widget> children;
  final material.EdgeInsetsGeometry? margin;
  final bool addDividers;
  final double dividerIndent;

  @override
  material.Widget build(material.BuildContext context) {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      return CupertinoSettingsGroupCard(
        margin: margin,
        addDividers: addDividers,
        dividerIndent: dividerIndent,
        backgroundColor: resolveSettingsSectionBackground(context),
        children: children,
      );
    }

    return SettingsCard(
      margin: margin,
      padding: material.EdgeInsets.zero,
      borderRadius: 8,
      child: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        children: addDividers ? _withMaterialDividers(context) : children,
      ),
    );
  }

  List<material.Widget> _withMaterialDividers(material.BuildContext context) {
    if (children.length <= 1) {
      return children;
    }
    final dividerColor = material.Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.12);
    final result = <material.Widget>[];
    for (var i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i != children.length - 1) {
        result.add(material.Divider(color: dividerColor, height: 1));
      }
    }
    return result;
  }
}

class AdaptiveSettingsPage extends material.StatelessWidget {
  const AdaptiveSettingsPage({
    super.key,
    required this.children,
    this.nipaplayPadding = const material.EdgeInsets.all(24),
    this.cupertinoHorizontalPadding = 16,
    this.cupertinoBottomPadding = 32,
  });

  final List<material.Widget> children;
  final material.EdgeInsetsGeometry nipaplayPadding;
  final double cupertinoHorizontalPadding;
  final double cupertinoBottomPadding;

  @override
  material.Widget build(material.BuildContext context) {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      final backgroundColor = cupertino.CupertinoDynamicColor.resolve(
        cupertino.CupertinoColors.systemGroupedBackground,
        context,
      );
      return material.ColoredBox(
        color: backgroundColor,
        child: material.SafeArea(
          top: false,
          bottom: false,
          child: material.ListView(
            physics: const cupertino.BouncingScrollPhysics(
              parent: material.AlwaysScrollableScrollPhysics(),
            ),
            padding: material.EdgeInsets.fromLTRB(
              cupertinoHorizontalPadding,
              64,
              cupertinoHorizontalPadding,
              cupertinoBottomPadding +
                  material.MediaQuery.viewPaddingOf(context).bottom,
            ),
            children: children,
          ),
        ),
      );
    }

    return material.ListView(
      padding: nipaplayPadding,
      children: children,
    );
  }
}

class _PhoneMenuChip extends material.StatelessWidget {
  const _PhoneMenuChip({required this.label});

  final String label;

  @override
  material.Widget build(material.BuildContext context) {
    return material.Container(
      constraints: const material.BoxConstraints(minHeight: 30, maxWidth: 180),
      padding: const material.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: material.BoxDecoration(
        color: cupertino.CupertinoDynamicColor.resolve(
          cupertino.CupertinoColors.secondarySystemFill,
          context,
        ),
        borderRadius: material.BorderRadius.circular(8),
      ),
      child: material.Row(
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.Flexible(
            child: material.Text(
              label,
              maxLines: 1,
              overflow: material.TextOverflow.ellipsis,
              style: material.TextStyle(
                color: resolveSettingsPrimaryTextColor(context),
                fontSize: 14,
                fontWeight: material.FontWeight.w600,
              ),
            ),
          ),
          const material.SizedBox(width: 4),
          material.Icon(
            Ionicons.chevron_down,
            size: 14,
            color: resolveSettingsSecondaryTextColor(context),
          ),
        ],
      ),
    );
  }
}
