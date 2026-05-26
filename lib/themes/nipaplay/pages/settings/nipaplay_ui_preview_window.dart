import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/pages/tab_labels.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_demo_section.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_main_tab_bar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_no_ripple_theme.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class NipaplayUiPreviewWindow extends StatefulWidget {
  const NipaplayUiPreviewWindow({super.key});

  @override
  State<NipaplayUiPreviewWindow> createState() =>
      _NipaplayUiPreviewWindowState();
}

class _NipaplayUiPreviewWindowState extends State<NipaplayUiPreviewWindow>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey _dropdownKey = GlobalKey();
  bool _switchValue = true;
  String _dropdownValue = 'Fluent UI';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NipaplayWindowScaffold(
      maxWidth: 1100,
      maxHeightFactor: 0.9,
      onClose: () => Navigator.of(context).maybePop(),
      child: SettingsNoRippleTheme(
        disableBlurEffect: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Row(
                children: [
                  Text(
                    'Nipaplay 设计 UI 预览',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  HoverScaleTextButton(
                    text: '重置示例',
                    onPressed: _resetDemoState,
                    idleColor: colorScheme.onSurface.withValues(alpha: 0.7),
                    hoverColor: AppAccentColors.current,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: colorScheme.onSurface.withValues(alpha: 0.12),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  NipaplayDemoSection(
                    title: '主 Tab',
                    subtitle: '与主界面一致的 Tab 样式',
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: NipaplayMainTabBar(
                          controller: _tabController,
                          tabs: createTabLabels(context),
                          showLeadingLogoOnMobile: false,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  NipaplayDemoSection(
                    title: '基础控件',
                    subtitle: '开关、下拉菜单、无背景按钮与设置项',
                    children: [
                      SettingsItem.toggle(
                        title: 'Fluent 开关',
                        subtitle: '使用项目统一的 Fluent 风格开关',
                        icon: Ionicons.toggle_outline,
                        value: _switchValue,
                        onChanged: (value) {
                          setState(() => _switchValue = value);
                        },
                      ),
                      SettingsItem.dropdown(
                        title: '项目下拉菜单',
                        subtitle: '展示 BlurDropdown 的交互样式',
                        icon: Ionicons.chevron_down_outline,
                        dropdownKey: _dropdownKey,
                        items: [
                          DropdownMenuItemData<String>(
                            title: 'Fluent UI',
                            value: 'Fluent UI',
                            isSelected: _dropdownValue == 'Fluent UI',
                          ),
                          DropdownMenuItemData<String>(
                            title: 'Nipaplay',
                            value: 'Nipaplay',
                            isSelected: _dropdownValue == 'Nipaplay',
                          ),
                          DropdownMenuItemData<String>(
                            title: 'Settings',
                            value: 'Settings',
                            isSelected: _dropdownValue == 'Settings',
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _dropdownValue = value as String);
                        },
                      ),
                      SettingsItem.button(
                        title: '悬浮放大变色按钮',
                        subtitle: 'HoverScaleTextButton 的示例',
                        icon: Ionicons.sparkles_outline,
                        trailingIcon: Ionicons.chevron_forward_outline,
                        onTap: () {},
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: HoverScaleTextButton(
                            text: '无背景容器按钮',
                            onPressed: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  NipaplayDemoSection(
                    title: '设置卡片',
                    subtitle: '承载设置内容的卡片与分割线容器',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SettingsCard(
                          child: Column(
                            children: [
                              SettingsItem.toggle(
                                title: '卡片内开关',
                                subtitle: '示例卡片中的设置项',
                                icon: Ionicons.options_outline,
                                value: true,
                                onChanged: (_) {},
                              ),
                              Divider(
                                height: 1,
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.12),
                              ),
                              SettingsItem.button(
                                title: '卡片内按钮',
                                subtitle: '带分割线的设置内容承载方式',
                                icon: Ionicons.folder_outline,
                                trailingIcon: Ionicons.chevron_forward_outline,
                                onTap: () {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  NipaplayDemoSection(
                    title: '部分内容卡片',
                    subtitle: '用于展示局部信息的卡片容器',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SettingsCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '卡片标题',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '这里适合承载说明、状态或局部动作，不需要像设置项那样强制分割。',
                                style: TextStyle(
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  NipaplayDemoSection(
                    title: '状态展示',
                    subtitle: '和项目配色一起观察当前控件状态',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Ionicons.color_palette_outline,
                              color: AppAccentColors.current,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '当前下拉选项: $_dropdownValue',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                            FluentSettingsSwitch(
                              value: _switchValue,
                              onChanged: (value) =>
                                  setState(() => _switchValue = value),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetDemoState() {
    setState(() {
      _switchValue = true;
      _dropdownValue = 'Fluent UI';
      _tabController.animateTo(0);
    });
  }
}
