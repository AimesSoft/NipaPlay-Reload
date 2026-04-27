import 'package:flutter/material.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/themes/nipaplay/widgets/menu_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/system_resource_display.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

const double kNipaplayWindowCaptionHeight = 28;

class NipaplayLargeScreenModeActionsOverlay extends StatelessWidget {
  const NipaplayLargeScreenModeActionsOverlay({
    super.key,
    required this.isDarkMode,
    required this.isLargeScreenLayoutActive,
    required this.topPadding,
    required this.rightPadding,
    required this.showWindowsButtons,
    required this.isMaximized,
    required this.onToggleLargeScreen,
    required this.onToggleThemeFromOrigin,
    required this.onOpenSettings,
    required this.onMinimize,
    required this.onMaximizeRestore,
    required this.onClose,
  });

  final bool isDarkMode;
  final bool isLargeScreenLayoutActive;
  final double topPadding;
  final double rightPadding;
  final bool showWindowsButtons;
  final bool isMaximized;
  final VoidCallback onToggleLargeScreen;
  final Future<void> Function(Offset globalOrigin)? onToggleThemeFromOrigin;
  final VoidCallback onOpenSettings;
  final VoidCallback onMinimize;
  final VoidCallback onMaximizeRestore;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final windowButtons = showWindowsButtons
        ? buildWindowsWindowControlButtons(
            isMaximized: isMaximized,
            onMinimize: onMinimize,
            onMaximizeRestore: onMaximizeRestore,
            onClose: onClose,
          )
        : null;

    if (isLargeScreenLayoutActive) {
      if (windowButtons == null) {
        return const SizedBox.shrink();
      }
      return Positioned(
        top: topPadding,
        right: rightPadding,
        child: windowButtons,
      );
    }

    return Positioned(
      top: topPadding,
      right: rightPadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SystemResourceDisplay(),
          const SizedBox(width: 8),
          _NormalModeActionButtons(
            isDarkMode: isDarkMode,
            isLargeScreenLayoutActive: isLargeScreenLayoutActive,
            onToggleLargeScreen: onToggleLargeScreen,
            onToggleThemeFromOrigin: onToggleThemeFromOrigin,
            onOpenSettings: onOpenSettings,
          ),
          if (windowButtons != null) ...[
            const SizedBox(width: 8),
            windowButtons,
          ],
        ],
      ),
    );
  }
}

class LargeScreenModeToggleIconButton extends StatefulWidget {
  const LargeScreenModeToggleIconButton({
    super.key,
    required this.isActive,
    required this.onPressed,
  });

  final bool isActive;
  final VoidCallback onPressed;

  @override
  State<LargeScreenModeToggleIconButton> createState() =>
      _LargeScreenModeToggleIconButtonState();
}

class _LargeScreenModeToggleIconButtonState
    extends State<LargeScreenModeToggleIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bool isActive = widget.isActive;
    final double scale = _isPressed ? 0.92 : (_isHovered ? 1.1 : 1.0);
    final Color iconColor = isActive
        ? const Color(0xFFFF2E55)
        : (_isHovered
            ? const Color(0xFFFF2E55)
            : (isDarkMode ? Colors.white : Colors.black87));
    final icon = isActive ? Icons.view_day_rounded : Icons.view_sidebar_rounded;

    return Tooltip(
      message: isActive ? '退出大屏幕模式' : '大屏幕模式',
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 120),
            child: Icon(
              icon,
              size: 22,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _NormalModeActionButtons extends StatelessWidget {
  const _NormalModeActionButtons({
    required this.isDarkMode,
    required this.isLargeScreenLayoutActive,
    required this.onToggleLargeScreen,
    required this.onToggleThemeFromOrigin,
    required this.onOpenSettings,
  });

  final bool isDarkMode;
  final bool isLargeScreenLayoutActive;
  final VoidCallback onToggleLargeScreen;
  final Future<void> Function(Offset globalOrigin)? onToggleThemeFromOrigin;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: kNipaplayWindowCaptionHeight,
          child: Center(
            child: Image.asset(
              'assets/logo2.png',
              height: 24,
              fit: BoxFit.contain,
              color: isDarkMode ? Colors.white : Colors.black,
              colorBlendMode: BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: kNipaplayWindowCaptionHeight,
          child: Center(
            child: LargeScreenModeToggleIconButton(
              isActive: isLargeScreenLayoutActive,
              onPressed: onToggleLargeScreen,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: kNipaplayWindowCaptionHeight,
          child: Center(
            child: _ThemeToggleIconButton(
              onToggleFromOrigin: onToggleThemeFromOrigin,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: kNipaplayWindowCaptionHeight,
          child: Center(
            child: _SettingsIconButton(
              onPressed: onOpenSettings,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeToggleIconButton extends StatefulWidget {
  const _ThemeToggleIconButton({this.onToggleFromOrigin});

  final Future<void> Function(Offset globalOrigin)? onToggleFromOrigin;

  @override
  State<_ThemeToggleIconButton> createState() => _ThemeToggleIconButtonState();
}

class _ThemeToggleIconButtonState extends State<_ThemeToggleIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() {
      _isPressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final double scale = _isPressed ? 0.92 : (_isHovered ? 1.1 : 1.0);
    final Color iconColor = _isHovered
        ? const Color(0xFFFF2E55)
        : (isDarkMode ? Colors.white : Colors.black87);
    final icon =
        isDarkMode ? Icons.nightlight_rounded : Icons.light_mode_rounded;
    final tooltip = isDarkMode
        ? context.l10n.toggleToLightMode
        : context.l10n.toggleToDarkMode;

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: () => _toggleTheme(
            context,
            onToggleFromOrigin: widget.onToggleFromOrigin,
          ),
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 120),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale:
                        Tween<double>(begin: 0.85, end: 1.0).animate(animation),
                    child: RotationTransition(
                      turns: Tween<double>(begin: 0.9, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  ),
                );
              },
              child: Icon(
                icon,
                key: ValueKey<bool>(isDarkMode),
                size: 22,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsIconButton extends StatefulWidget {
  const _SettingsIconButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_SettingsIconButton> createState() => _SettingsIconButtonState();
}

class _SettingsIconButtonState extends State<_SettingsIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() {
      _isPressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final double scale = _isPressed ? 0.92 : (_isHovered ? 1.1 : 1.0);
    final Color iconColor = _isHovered
        ? const Color(0xFFFF2E55)
        : (isDarkMode ? Colors.white : Colors.black87);

    return Tooltip(
      message: context.l10n.settingsLabel,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 120),
            child: Icon(
              Icons.settings_rounded,
              size: 22,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

void _toggleTheme(
  BuildContext context, {
  Future<void> Function(Offset globalOrigin)? onToggleFromOrigin,
}) {
  if (onToggleFromOrigin != null) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final origin = renderObject.localToGlobal(renderObject.size.center(Offset.zero));
      onToggleFromOrigin(origin);
      return;
    }
  }

  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  context.read<ThemeNotifier>().themeMode =
      isDarkMode ? ThemeMode.light : ThemeMode.dark;
}

Widget buildWindowsWindowControlButtons({
  required bool isMaximized,
  required VoidCallback onMinimize,
  required VoidCallback onMaximizeRestore,
  required VoidCallback onClose,
}) {
  return SizedBox(
    height: kNipaplayWindowCaptionHeight,
    child: Center(
      child: WindowControlButtons(
        isMaximized: isMaximized,
        onMinimize: onMinimize,
        onMaximizeRestore: onMaximizeRestore,
        onClose: onClose,
      ),
    ),
  );
}
