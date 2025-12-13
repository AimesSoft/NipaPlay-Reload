import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

enum DesktopExitAction {
  cancelAndReturn,
  minimizeToTrayOrTaskbar,
  closePlayer,
}

class DesktopExitDecision {
  final DesktopExitAction action;
  final bool remember;

  const DesktopExitDecision({
    required this.action,
    required this.remember,
  });
}

class DesktopExitHandler with WindowListener, TrayListener {
  DesktopExitHandler._();

  static final DesktopExitHandler instance = DesktopExitHandler._();

  static const String _rememberedActionKey = 'desktop_exit_action';
  static const String _rememberedActionMinimize = 'minimize';
  static const String _rememberedActionClose = 'close';

  material.GlobalKey<material.NavigatorState>? _navigatorKey;

  bool _windowHooked = false;
  bool _trayReady = false;
  bool _handlingWindowClose = false;
  bool _quitting = false;

  Future<void> initialize(
    material.GlobalKey<material.NavigatorState> navigatorKey,
  ) async {
    if (kIsWeb || !globals.isDesktop) return;
    _navigatorKey ??= navigatorKey;
    if (_windowHooked) return;
    _windowHooked = true;

    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
  }

  @override
  void onWindowClose() async {
    if (kIsWeb || !globals.isDesktop) return;
    if (_quitting) {
      await windowManager.destroy();
      return;
    }

    if (_handlingWindowClose) return;
    _handlingWindowClose = true;
    try {
      final isPreventClose = await windowManager.isPreventClose();
      if (!isPreventClose) return;

      final action = await _resolveExitAction();
      switch (action) {
        case DesktopExitAction.cancelAndReturn:
          return;
        case DesktopExitAction.minimizeToTrayOrTaskbar:
          await _minimizeToTrayOrTaskbar();
          return;
        case DesktopExitAction.closePlayer:
          await _exitApp();
          return;
      }
    } finally {
      _handlingWindowClose = false;
    }
  }

  Future<DesktopExitAction> _resolveExitAction() async {
    final remembered = await _loadRememberedAction();
    if (remembered != null) return remembered;

    final context = _navigatorKey?.currentState?.overlay?.context;
    if (context == null || !context.mounted) {
      return DesktopExitAction.closePlayer;
    }

    final decision = await _showExitDialog(context);
    if (decision == null) return DesktopExitAction.cancelAndReturn;

    if (decision.remember &&
        (decision.action == DesktopExitAction.minimizeToTrayOrTaskbar ||
            decision.action == DesktopExitAction.closePlayer)) {
      await _saveRememberedAction(decision.action);
    }

    return decision.action;
  }

  Future<DesktopExitAction?> _loadRememberedAction() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_rememberedActionKey);
    switch (value) {
      case _rememberedActionMinimize:
        return DesktopExitAction.minimizeToTrayOrTaskbar;
      case _rememberedActionClose:
        return DesktopExitAction.closePlayer;
      default:
        return null;
    }
  }

  Future<void> _saveRememberedAction(DesktopExitAction action) async {
    final prefs = await SharedPreferences.getInstance();
    switch (action) {
      case DesktopExitAction.minimizeToTrayOrTaskbar:
        await prefs.setString(_rememberedActionKey, _rememberedActionMinimize);
        return;
      case DesktopExitAction.closePlayer:
        await prefs.setString(_rememberedActionKey, _rememberedActionClose);
        return;
      case DesktopExitAction.cancelAndReturn:
        return;
    }
  }

  Future<DesktopExitDecision?> _showExitDialog(material.BuildContext context) {
    bool remember = false;
    final isFluent =
        Provider.of<UIThemeProvider>(context, listen: false).isFluentUITheme;

    final textStyle = isFluent
        ? const material.TextStyle()
        : const material.TextStyle(color: material.Colors.white70);
    final titleStyle = isFluent
        ? const material.TextStyle()
        : const material.TextStyle(
            color: material.Colors.white,
            fontSize: 16,
            fontWeight: material.FontWeight.w600,
          );

    return BlurDialog.show<DesktopExitDecision>(
      context: context,
      title: '退出播放器',
      barrierDismissible: true,
      contentWidget: material.StatefulBuilder(
        builder: (context, setState) {
          return material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Text('确定要退出 NipaPlay 吗？', style: titleStyle),
              const material.SizedBox(height: 12),
              material.Row(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  if (isFluent)
                    fluent.Checkbox(
                      checked: remember,
                      onChanged: (value) => setState(() {
                        remember = value ?? false;
                      }),
                    )
                  else
                    material.Checkbox(
                      value: remember,
                      onChanged: (value) => setState(() {
                        remember = value ?? false;
                      }),
                    ),
                  material.GestureDetector(
                    onTap: () => setState(() {
                      remember = !remember;
                    }),
                    child: material.Padding(
                      padding: const material.EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      child: material.Text('记住我的选择', style: textStyle),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      actions: [
        material.TextButton(
          onPressed: () => material.Navigator.of(context).pop(
            const DesktopExitDecision(
              action: DesktopExitAction.cancelAndReturn,
              remember: false,
            ),
          ),
          child: material.Text(
            '取消并返回',
            style: isFluent ? null : const material.TextStyle(color: material.Colors.white70),
          ),
        ),
        material.OutlinedButton(
          onPressed: () => material.Navigator.of(context).pop(
            DesktopExitDecision(
              action: DesktopExitAction.minimizeToTrayOrTaskbar,
              remember: remember,
            ),
          ),
          child: material.Text(
            '最小化到系统托盘/任务栏',
            style: isFluent ? null : const material.TextStyle(color: material.Colors.white),
          ),
        ),
        material.ElevatedButton(
          onPressed: () => material.Navigator.of(context).pop(
            DesktopExitDecision(
              action: DesktopExitAction.closePlayer,
              remember: remember,
            ),
          ),
          style: isFluent
              ? null
              : material.ElevatedButton.styleFrom(
                  backgroundColor: material.Colors.redAccent,
                  foregroundColor: material.Colors.white,
                ),
          child: const material.Text('关闭播放器'),
        ),
      ],
    );
  }

  Future<void> _minimizeToTrayOrTaskbar() async {
    try {
      final trayOk = await _ensureTray();
      if (trayOk) {
        await windowManager.setSkipTaskbar(true);
        await windowManager.hide();
        return;
      }
    } catch (_) {}

    await windowManager.minimize();
  }

  Future<void> _exitApp() async {
    _quitting = true;
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<bool> _ensureTray() async {
    if (_trayReady) return true;
    if (!globals.isDesktop) return false;

    try {
      final iconPath = await _prepareTrayIconPath();
      await trayManager.setIcon(
        iconPath,
        isTemplate: Platform.isMacOS,
      );
      await trayManager.setToolTip('NipaPlay');

      final menu = Menu(
        items: [
          MenuItem(key: 'show', label: '显示播放器'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出播放器'),
        ],
      );
      await trayManager.setContextMenu(menu);

      trayManager.addListener(this);
      _trayReady = true;
      return true;
    } catch (e) {
      debugPrint('[DesktopExitHandler] 初始化系统托盘失败: $e');
      return false;
    }
  }

  Future<String> _prepareTrayIconPath() async {
    if (Platform.isMacOS || Platform.isLinux) {
      return 'assets/nipaplay.png';
    }

    final data = await rootBundle.load('assets/nipaplay.png');
    final bytes = data.buffer.asUint8List();

    final baseDir = await getApplicationSupportDirectory();
    final trayDir = Directory(path.join(baseDir.path, 'tray'));
    if (!trayDir.existsSync()) {
      trayDir.createSync(recursive: true);
    }

    final icoFile = File(path.join(trayDir.path, 'nipaplay.ico'));
    if (!icoFile.existsSync() || icoFile.lengthSync() == 0) {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw StateError('无法解析 assets/nipaplay.png');
      }

      final resized = img.copyResize(decoded, width: 256, height: 256);
      final icoBytes = Uint8List.fromList(img.encodeIco(resized));
      await icoFile.writeAsBytes(icoBytes, flush: true);
    }
    return icoFile.path;
  }

  Future<void> _showMainWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() async {
    await _showMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await _showMainWindow();
        return;
      case 'exit':
        await _exitApp();
        return;
    }
  }
}
