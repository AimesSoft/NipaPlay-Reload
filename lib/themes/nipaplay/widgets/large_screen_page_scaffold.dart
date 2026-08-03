import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tvos_remote_text_input_scope.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

/// Blank content placed at the start of a large-screen page so its initial
/// title is not covered by the overlaid top status bar.
///
/// This deliberately remains a page child instead of padding the outer app
/// viewport, which stays full-screen underneath the status-bar overlay.
class NipaplayLargeScreenPageTopSpacer extends StatelessWidget {
  const NipaplayLargeScreenPageTopSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    if (!NipaplayLargeScreenModeScope.isActiveOf(context)) {
      return const SizedBox.shrink();
    }
    return const SizedBox(
      key: ValueKey<String>('large-screen-page-top-spacer'),
      height: kNipaplayLargeScreenBottomHintHeight,
    );
  }
}

class NipaplayLargeScreenPageScaffold extends StatelessWidget {
  const NipaplayLargeScreenPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.actions = const <Widget>[],
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(44, 28, 44, 32),
    this.headerBottomSpacing = 24,
    this.showBackgroundEffects = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final double headerBottomSpacing;
  final bool showBackgroundEffects;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF151820);
    final mutedColor = textColor.withValues(alpha: 0.64);

    return Stack(
      children: [
        if (showBackgroundEffects) ...[
          Positioned.fill(
            child: ColoredBox(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.34)
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: isDark ? 0.08 : 0.00),
                    Colors.black.withValues(alpha: isDark ? 0.28 : 0.04),
                  ],
                ),
              ),
            ),
          ),
        ],
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NipaplayLargeScreenPageTopSpacer(),
              Expanded(
                child: Padding(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900,
                                    height: 1.0,
                                  ),
                                ),
                                if (subtitle != null &&
                                    subtitle!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: mutedColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (actions.isNotEmpty) ...[
                            const SizedBox(width: 20),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: actions,
                            ),
                          ],
                          if (trailing != null) ...[
                            const SizedBox(width: 20),
                            trailing!,
                          ],
                        ],
                      ),
                      SizedBox(height: headerBottomSpacing),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class NipaplayLargeScreenSectionHeader extends StatelessWidget {
  const NipaplayLargeScreenSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.titleMaxLines = 1,
    this.titleOverflow = TextOverflow.ellipsis,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// 标题最大行数，默认 1（省略号截断）；传入 null 可多行完整显示
  final int? titleMaxLines;

  /// 标题溢出处理，默认省略号截断
  final TextOverflow titleOverflow;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF161922);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: titleMaxLines,
                overflow: titleOverflow,
                style: TextStyle(
                  color: textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.62),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class NipaplayLargeScreenPanel extends StatelessWidget {
  const NipaplayLargeScreenPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 8,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: clipBehavior,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.075)
                : Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class NipaplayLargeScreenActionButton extends StatelessWidget {
  const NipaplayLargeScreenActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.compact = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool autofocus;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = NipaplayLargeScreenFocusableAction(
      autofocus: autofocus,
      onActivate: onPressed,
      borderRadius: BorderRadius.circular(8),
      focusScale: 1.035,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 10 : 13,
      ),
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: Colors.white.withValues(alpha: 0.10),
        idleBackgroundLight: Colors.white.withValues(alpha: 0.82),
        focusStrokeWidth: 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 18 : 21),
          const SizedBox(width: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 13 : 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    if (tooltip == null) {
      return child;
    }
    return Tooltip(message: tooltip!, child: child);
  }
}

class NipaplayLargeScreenIconButton extends StatelessWidget {
  const NipaplayLargeScreenIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.autofocus = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: NipaplayLargeScreenFocusableAction(
        autofocus: autofocus,
        onActivate: onPressed,
        borderRadius: BorderRadius.circular(8),
        focusScale: 1.06,
        padding: const EdgeInsets.all(12),
        style: NipaplayLargeScreenFocusableStyle(
          idleBackgroundDark: Colors.white.withValues(alpha: 0.10),
          idleBackgroundLight: Colors.white.withValues(alpha: 0.82),
        ),
        child: Icon(icon, size: 22),
      ),
    );
  }
}

class NipaplayLargeScreenEmptyState extends StatelessWidget {
  const NipaplayLargeScreenEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF151820);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 76, color: textColor.withValues(alpha: 0.46)),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.62),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class NipaplayLargeScreenTextInput extends StatefulWidget {
  const NipaplayLargeScreenTextInput({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon = Icons.search_rounded,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData prefixIcon;
  final Widget? suffix;

  @override
  State<NipaplayLargeScreenTextInput> createState() =>
      _NipaplayLargeScreenTextInputState();
}

class _NipaplayLargeScreenTextInputState
    extends State<NipaplayLargeScreenTextInput> {
  late final FocusNode _controlFocusNode;
  late final FocusNode _editingFocusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controlFocusNode = FocusNode(
      debugLabel: 'nipaplay_large_screen_text_input_control',
    );
    _editingFocusNode = FocusNode(
      debugLabel: 'nipaplay_large_screen_text_input_editing',
      skipTraversal: true,
    )..addListener(_handleEditingFocusChanged);
  }

  @override
  void dispose() {
    _editingFocusNode.removeListener(_handleEditingFocusChanged);
    _editingFocusNode.dispose();
    _controlFocusNode.dispose();
    super.dispose();
  }

  void _handleEditingFocusChanged() {
    if (_editingFocusNode.hasFocus || !_isEditing || !mounted) return;
    setState(() {
      _isEditing = false;
    });
  }

  void _beginEditing() {
    if (_isEditing) {
      _editingFocusNode.requestFocus();
      return;
    }
    setState(() {
      _isEditing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editingFocusNode.requestFocus();
    });
  }

  void _finishEditing({TraversalDirection? moveDirection}) {
    if (_isEditing) {
      setState(() {
        _isEditing = false;
      });
    }
    _controlFocusNode.requestFocus();
    if (moveDirection == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controlFocusNode.focusInDirection(moveDirection);
    });
  }

  KeyEventResult _handleEditingKeyEvent(FocusNode node, KeyEvent event) {
    if (!_isEditing || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _finishEditing(moveDirection: TraversalDirection.up);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _finishEditing(moveDirection: TraversalDirection.down);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.gameButtonB) {
      _finishEditing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF171923);
    return TvOSRemoteTextInputAnchor(
      title: widget.hintText,
      child: Focus(
        onKeyEvent: _handleEditingKeyEvent,
        child: NipaplayLargeScreenFocusableAction(
          focusNode: _controlFocusNode,
          onActivate: _beginEditing,
          borderRadius: BorderRadius.circular(8),
          focusScale: 1.01,
          padding: EdgeInsets.zero,
          style: const NipaplayLargeScreenFocusableStyle(
            idleBackgroundDark: Colors.transparent,
            idleBackgroundLight: Colors.transparent,
            focusStrokeWidth: 2,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _editingFocusNode,
            canRequestFocus: _isEditing,
            readOnly: !_isEditing,
            showCursor: _isEditing,
            enableInteractiveSelection: _isEditing,
            onTap: _beginEditing,
            onChanged: widget.onChanged,
            onSubmitted: (value) {
              widget.onSubmitted?.call(value);
              _finishEditing();
            },
            style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: TextStyle(color: textColor.withValues(alpha: 0.48)),
              prefixIcon: Icon(
                widget.prefixIcon,
                color: textColor.withValues(alpha: 0.58),
              ),
              suffixIcon: widget.suffix,
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.white.withValues(alpha: 0.82),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: textColor.withValues(alpha: 0.10),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: textColor.withValues(alpha: 0.10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppAccentColors.current,
                  width: 2,
                ),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ),
    );
  }
}
