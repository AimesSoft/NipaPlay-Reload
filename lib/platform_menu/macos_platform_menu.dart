import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 单个导航菜单项
class NavigationItem {
  const NavigationItem({required this.label, required this.onSelected});

  final String label;
  final VoidCallback onSelected;
}

/// macOS PlatformMenuBar wrapper for NipaPlay.
///
/// [navigationItems] 动态传入当前可见的导航页面，
/// 菜单会自动分配 Cmd+1, Cmd+2, ... 快捷键。
///
/// 或使用 [navigationItemsBuilder] 从 context 动态构建导航项。
class MacosPlatformMenu extends StatelessWidget {
  const MacosPlatformMenu({
    super.key,
    required this.child,
    this.navigationItems,
    this.navigationItemsBuilder,
    this.onUploadVideo,
    this.onOpenSettings,
    this.onShowAbout,
    this.onShowHelp,
    this.onOpenGitHub,
    this.onOpenWebsite,
    this.onCloseWindow,
  }) : assert(
          navigationItems != null || navigationItemsBuilder != null,
          'Either navigationItems or navigationItemsBuilder must be provided',
        );

  final Widget child;

  /// 当前可见的导航页面列表（静态传入）
  final List<NavigationItem>? navigationItems;

  /// 从 context 动态构建导航项（优先于 navigationItems）
  final List<NavigationItem> Function(BuildContext context)?
      navigationItemsBuilder;

  /// 上传视频 (Cmd+U)
  final VoidCallback? onUploadVideo;

  /// 偏好设置 (Cmd+,)
  final VoidCallback? onOpenSettings;

  /// 关于 NipaPlay
  final VoidCallback? onShowAbout;

  /// NipaPlay 帮助 (Cmd+?)
  final VoidCallback? onShowHelp;

  /// 打开 GitHub 页面
  final VoidCallback? onOpenGitHub;

  /// 打开网站
  final VoidCallback? onOpenWebsite;

  /// 关闭窗口 (Cmd+W)
  final VoidCallback? onCloseWindow;

  List<NavigationItem> _resolveNavigationItems(BuildContext context) {
    if (navigationItemsBuilder != null) {
      return navigationItemsBuilder!(context);
    }
    return navigationItems ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    // PlatformMenuBar 的 PlatformProvidedMenuItem 仅在 macOS 上支持，
    // 其他平台直接返回子组件。
    if (kIsWeb || !Platform.isMacOS) {
      return child;
    }
    return PlatformMenuBar(
      menus: _buildMenus(context),
      child: child,
    );
  }

  List<PlatformMenuItem> _buildMenus(BuildContext context) {
    return <PlatformMenuItem>[
      _buildAppMenu(),
      _buildFileMenu(),
      _buildNavigationMenu(context),
      _buildWindowMenu(),
      _buildHelpMenu(),
    ];
  }

  /// 应用菜单 (NipaPlay)
  PlatformMenu _buildAppMenu() {
    return PlatformMenu(
      label: 'NipaPlay',
      menus: <PlatformMenuItem>[
        if (onShowAbout != null)
          PlatformMenuItem(
            label: '关于 NipaPlay',
            onSelected: onShowAbout,
          ),
        if (onOpenSettings != null)
          PlatformMenuItem(
            label: '偏好设置...',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: onOpenSettings,
          ),
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hide,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.quit,
            ),
          ],
        ),
      ],
    );
  }

  /// 文件菜单
  PlatformMenu _buildFileMenu() {
    return PlatformMenu(
      label: '文件',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            if (onUploadVideo != null)
              PlatformMenuItem(
                label: '上传视频',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyU,
                  meta: true,
                ),
                onSelected: onUploadVideo,
              ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            if (onCloseWindow != null)
              PlatformMenuItem(
                label: '关闭窗口',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyW,
                  meta: true,
                ),
                onSelected: onCloseWindow,
              ),
          ],
        ),
      ],
    );
  }

  /// 导航菜单 — 根据当前可见的 Tab 动态生成快捷键
  PlatformMenu _buildNavigationMenu(BuildContext context) {
    const digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];

    final navItems = _resolveNavigationItems(context);
    final items = <PlatformMenuItem>[];
    for (var i = 0; i < navItems.length && i < digitKeys.length; i++) {
      items.add(
        PlatformMenuItem(
          label: navItems[i].label,
          shortcut: SingleActivator(digitKeys[i], meta: true),
          onSelected: navItems[i].onSelected,
        ),
      );
    }

    return PlatformMenu(
      label: '导航',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(members: items),
      ],
    );
  }

  /// 窗口菜单 (系统提供)
  PlatformMenu _buildWindowMenu() {
    return const PlatformMenu(
      label: '窗口',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
      ],
    );
  }

  /// 帮助菜单
  PlatformMenu _buildHelpMenu() {
    return PlatformMenu(
      label: '帮助',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            if (onShowHelp != null)
              PlatformMenuItem(
                label: 'NipaPlay 帮助',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.question,
                  meta: true,
                ),
                onSelected: onShowHelp,
              ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            if (onOpenGitHub != null)
              PlatformMenuItem(
                label: 'GitHub',
                onSelected: onOpenGitHub,
              ),
            if (onOpenWebsite != null)
              PlatformMenuItem(
                label: '网站',
                onSelected: onOpenWebsite,
              ),
          ],
        ),
      ],
    );
  }
}
