import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// macOS PlatformMenuBar wrapper for NipaPlay.
///
/// Replaces the native XIB-based menu bar with Flutter's PlatformMenuBar API,
/// allowing menu structure and callbacks to be defined entirely in Dart.
class MacosPlatformMenu extends StatelessWidget {
  const MacosPlatformMenu({
    super.key,
    required this.child,
    this.onUploadVideo,
    this.onOpenHome,
    this.onOpenVideoPlayback,
    this.onOpenMediaLibrary,
    this.onOpenSettings,
    this.onShowAbout,
    this.onShowHelp,
    this.onOpenGitHub,
    this.onOpenWebsite,
    this.onCloseWindow,
  });

  final Widget child;

  /// 上传视频 (Cmd+U)
  final VoidCallback? onUploadVideo;

  /// 主页 (Cmd+1)
  final VoidCallback? onOpenHome;

  /// 视频播放 (Cmd+2)
  final VoidCallback? onOpenVideoPlayback;

  /// 媒体库 (Cmd+3)
  final VoidCallback? onOpenMediaLibrary;

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

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: _buildMenus(),
      child: child,
    );
  }

  List<PlatformMenuItem> _buildMenus() {
    return <PlatformMenuItem>[
      _buildAppMenu(),
      _buildFileMenu(),
      _buildNavigationMenu(),
      _buildWindowMenu(),
      _buildHelpMenu(),
    ];
  }

  /// 应用菜单 (NipaPlay)
  PlatformMenu _buildAppMenu() {
    return PlatformMenu(
      label: 'NipaPlay',
      menus: <PlatformMenuItem>[
        // 关于 NipaPlay
        if (onShowAbout != null)
          PlatformMenuItem(
            label: '关于 NipaPlay',
            onSelected: onShowAbout,
          ),
        // 偏好设置 (Cmd+,)
        if (onOpenSettings != null)
          PlatformMenuItem(
            label: '偏好设置...',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: onOpenSettings,
          ),
        // Services 子菜单 (系统提供)
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ],
        ),
        // 隐藏 / 隐藏其他 / 显示全部 (系统提供)
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
        // 退出 (系统提供)
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

  /// 导航菜单
  PlatformMenu _buildNavigationMenu() {
    return PlatformMenu(
      label: '导航',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            if (onOpenHome != null)
              PlatformMenuItem(
                label: '主页',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit1,
                  meta: true,
                ),
                onSelected: onOpenHome,
              ),
            if (onOpenVideoPlayback != null)
              PlatformMenuItem(
                label: '视频播放',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit2,
                  meta: true,
                ),
                onSelected: onOpenVideoPlayback,
              ),
            if (onOpenMediaLibrary != null)
              PlatformMenuItem(
                label: '媒体库',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit3,
                  meta: true,
                ),
                onSelected: onOpenMediaLibrary,
              ),
          ],
        ),
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
