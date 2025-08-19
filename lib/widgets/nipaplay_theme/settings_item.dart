import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dropdown.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

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
  final Function(dynamic)? onDropdownChanged;
  
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
    required Function(dynamic) onChanged,
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

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case SettingsItemType.dropdown:
        return _buildDropdownItem();
      case SettingsItemType.toggle:
        return _buildToggleItem();
      case SettingsItemType.button:
        return _buildButtonItem();
      case SettingsItemType.slider:
        return _buildSliderItem();
      case SettingsItemType.hotkey:
        return _buildHotkeyItem();
    }
  }

  /// 构建下拉菜单类型的设置项
  Widget _buildDropdownItem() {
    return ListTile(
      leading: icon != null ? Icon(icon, color: Colors.white70) : null,
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white54,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                color: enabled ? Colors.white70 : Colors.white38,
              ),
            )
          : null,
      trailing: enabled && dropdownItems != null
          ? BlurDropdown(
              dropdownKey: dropdownKey ?? GlobalKey(),
              items: dropdownItems!,
              onItemSelected: onDropdownChanged!,
            )
          : null,
      enabled: enabled,
    );
  }

  /// 构建开关类型的设置项
  Widget _buildToggleItem() {
    return SwitchListTile(
      secondary: icon != null ? Icon(icon, color: Colors.white70) : null,
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white54,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                color: enabled ? Colors.white70 : Colors.white38,
              ),
            )
          : null,
      value: switchValue ?? false,
      onChanged: enabled ? onSwitchChanged : null,
      activeColor: Colors.white,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: const Color.fromARGB(255, 0, 0, 0),
    );
  }

  /// 构建按钮类型的设置项
  Widget _buildButtonItem() {
    return ListTile(
      leading: icon != null ? Icon(icon, color: Colors.white70) : null,
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white54,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                color: enabled ? Colors.white70 : Colors.white38,
              ),
            )
          : null,
      trailing: Icon(
        trailingIcon ?? Ionicons.chevron_forward_outline,
        color: isDestructive 
            ? (enabled ? Colors.red : Colors.red.withOpacity(0.5))
            : (enabled ? Colors.white : Colors.white54),
      ),
      onTap: enabled ? onTap : null,
      enabled: enabled,
    );
  }

  /// 构建滑块类型的设置项
  Widget _buildSliderItem() {
    return Column(
      children: [
        ListTile(
          leading: icon != null ? Icon(icon, color: Colors.white70) : null,
          title: Text(
            title,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle!,
                  style: TextStyle(
                    color: enabled ? Colors.white70 : Colors.white38,
                  ),
                )
              : null,
          trailing: Text(
            sliderLabelFormatter?.call(sliderValue ?? 0) ?? 
            (sliderValue ?? 0).toStringAsFixed(1),
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Slider(
            value: sliderValue ?? 0,
            min: sliderMin ?? 0,
            max: sliderMax ?? 1,
            divisions: sliderDivisions,
            onChanged: enabled ? onSliderChanged : null,
            activeColor: Colors.white,
            inactiveColor: Colors.white38,
          ),
        ),
      ],
    );
  }

  /// 构建快捷键类型的设置项
  Widget _buildHotkeyItem() {
    return Builder(
      builder: (context) {
        final appearanceProvider = context.watch<AppearanceSettingsProvider>();
        final isBlurEnabled = appearanceProvider.enableWidgetBlurEffect;
        
        return ListTile(
          leading: icon != null ? Icon(icon, color: Colors.white70) : null,
          title: Text(
            title,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle!,
                  style: TextStyle(
                    color: enabled ? Colors.white70 : Colors.white38,
                  ),
                )
              : null,
          trailing: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: isBlurEnabled ? 10.0 : 0.0,
                sigmaY: isBlurEnabled ? 10.0 : 0.0,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isRecording 
                      ? Colors.red.withOpacity(0.2)
                      : Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isRecording 
                        ? Colors.red 
                        : Colors.white.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: Text(
                  isRecording ? '按任意键...' : (hotkeyText ?? '未设置'),
                  style: TextStyle(
                    color: isRecording 
                        ? Colors.red 
                        : (enabled ? Colors.white : Colors.white54),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          onTap: enabled ? onHotkeyTap : null,
          enabled: enabled,
        );
      },
    );
  }
}
