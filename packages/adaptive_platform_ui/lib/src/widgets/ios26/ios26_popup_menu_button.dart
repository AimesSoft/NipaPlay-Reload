import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Base type for entries in a popup menu
abstract class AdaptivePopupMenuEntry {
  /// Const constructor for subclasses
  const AdaptivePopupMenuEntry();
}

/// A selectable item in a popup menu
class AdaptivePopupMenuItem<T> extends AdaptivePopupMenuEntry {
  /// Creates a selectable popup menu item
  const AdaptivePopupMenuItem({
    required this.label,
    this.icon,
    this.enabled = true,
    this.value,
  });

  /// Display label for the item
  final String label;

  /// Optional icon (SF Symbol String for iOS 26+, IconData for iOS <26 and Android)
  final dynamic icon;

  /// Whether the item can be selected
  final bool enabled;

  /// Optional value of type T associated with this item
  final T? value;
}

/// A visual divider between popup menu items
class AdaptivePopupMenuDivider extends AdaptivePopupMenuEntry {
  /// Creates a visual divider between items
  const AdaptivePopupMenuDivider();
}

/// Button style for popup menu button
enum PopupButtonStyle {
  plain,
  gray,
  tinted,
  bordered,
  borderedProminent,
  filled,
  glass,
  prominentGlass,
}

/// Native iOS 26 popup menu button implementation using platform views
class IOS26PopupMenuButton<T> extends StatefulWidget {
  /// Creates a text-labeled popup menu button
  const IOS26PopupMenuButton({
    super.key,
    required this.buttonLabel,
    required this.items,
    required this.onSelected,
    this.tint,
    this.height = 32.0,
    this.shrinkWrap = false,
    this.buttonStyle = PopupButtonStyle.plain,
  }) : buttonIcon = null,
       child = null,
       width = null,
       round = false;

  /// Creates a round, icon-only popup menu button
  const IOS26PopupMenuButton.icon({
    super.key,
    required this.buttonIcon,
    required this.items,
    required this.onSelected,
    this.tint,
    double size = 44.0,
    this.buttonStyle = PopupButtonStyle.glass,
  }) : buttonLabel = null,
       child = null,
       round = true,
       width = size,
       height = size,
       shrinkWrap = false;

  /// Creates a popup menu button with a custom child widget
  const IOS26PopupMenuButton.widget({
    super.key,
    required this.items,
    required this.onSelected,
    this.tint,
    this.buttonStyle = PopupButtonStyle.plain,
    required this.child,
  }) : buttonLabel = null,
       buttonIcon = null,
       round = false,
       width = null,
       height = 32.0,
       shrinkWrap = true;

  /// Text for the button (null when using icon)
  final String? buttonLabel;

  /// Icon for the button (non-null in icon mode)
  final String? buttonIcon;

  /// Custom child widget (non-null in widget mode)
  final Widget? child;

  /// Fixed width in icon mode
  final double? width;

  /// Whether this is the round icon variant
  final bool round;

  /// Entries that populate the popup menu
  final List<AdaptivePopupMenuEntry> items;

  /// Called with the selected index when the user makes a selection
  final void Function(int index, AdaptivePopupMenuItem<T> entry) onSelected;

  /// Tint color for the control
  final Color? tint;

  /// Control height; icon mode uses diameter semantics
  final double height;

  /// If true, sizes the control to its intrinsic width
  final bool shrinkWrap;

  /// Visual style to apply to the button
  final PopupButtonStyle buttonStyle;

  /// Whether this instance is configured as an icon button variant
  bool get isIconButton => buttonIcon != null;

  @override
  State<IOS26PopupMenuButton<T>> createState() =>
      _IOS26PopupMenuButtonState<T>();
}

class _IOS26PopupMenuButtonState<T> extends State<IOS26PopupMenuButton<T>> {
  MethodChannel? _channel;
  bool? _lastIsDark;
  int? _lastTint;
  double? _intrinsicWidth;

  bool get _isDark =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  Color? get _effectiveTint =>
      widget.tint ?? CupertinoTheme.of(context).primaryColor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
  }

  @override
  void didUpdateWidget(IOS26PopupMenuButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync any changes to brightness or tint
    _syncBrightnessIfNeeded();

    // Check if menu items have changed
    if (_hasMenuItemsChanged(oldWidget.items, widget.items)) {
      _updateMenuItems();
    }

    // Check if button label or icon has changed
    if (oldWidget.buttonLabel != widget.buttonLabel ||
        oldWidget.buttonIcon != widget.buttonIcon) {
      _updateButtonContent();
    }
  }

  Future<void> _updateButtonContent() async {
    final ch = _channel;
    if (ch == null) return;

    try {
      await ch.invokeMethod('updateButtonContent', {
        if (widget.buttonLabel != null) 'buttonTitle': widget.buttonLabel,
        if (widget.buttonIcon != null) 'buttonIconName': widget.buttonIcon,
      });
    } catch (_) {}
  }

  bool _hasMenuItemsChanged(
    List<AdaptivePopupMenuEntry> oldItems,
    List<AdaptivePopupMenuEntry> newItems,
  ) {
    if (oldItems.length != newItems.length) return true;

    for (int i = 0; i < oldItems.length; i++) {
      final oldItem = oldItems[i];
      final newItem = newItems[i];

      if (oldItem.runtimeType != newItem.runtimeType) return true;

      if (oldItem is AdaptivePopupMenuItem<T> &&
          newItem is AdaptivePopupMenuItem<T>) {
        if (oldItem.label != newItem.label ||
            oldItem.icon != newItem.icon ||
            oldItem.enabled != newItem.enabled ||
            oldItem.value != newItem.value) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _updateMenuItems() async {
    final ch = _channel;
    if (ch == null) return;

    // Flatten entries into parallel arrays for the platform view
    final labels = <String>[];
    final symbols = <String>[];
    final isDivider = <bool>[];
    final enabled = <bool>[];

    for (final e in widget.items) {
      if (e is AdaptivePopupMenuDivider) {
        labels.add('');
        symbols.add('');
        isDivider.add(true);
        enabled.add(false);
      } else if (e is AdaptivePopupMenuItem<T>) {
        labels.add(e.label);
        symbols.add(e.icon is String ? e.icon as String : '');
        isDivider.add(false);
        enabled.add(e.enabled);
      }
    }

    try {
      await ch.invokeMethod('updateMenuItems', {
        'labels': labels,
        'sfSymbols': symbols,
        'isDivider': isDivider,
        'enabled': enabled,
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  int _colorToARGB(Color color) {
    return ((color.a * 255.0).round() & 0xff) << 24 |
        ((color.r * 255.0).round() & 0xff) << 16 |
        ((color.g * 255.0).round() & 0xff) << 8 |
        ((color.b * 255.0).round() & 0xff);
  }

  /// Whether this instance uses a custom child widget
  bool get isCustomWidget => widget.child != null;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isIOS) {
      // Flatten entries into parallel arrays for the platform view
      final labels = <String>[];
      final symbols = <String>[];
      final isDivider = <bool>[];
      final enabled = <bool>[];

      for (final e in widget.items) {
        if (e is AdaptivePopupMenuDivider) {
          labels.add('');
          symbols.add('');
          isDivider.add(true);
          enabled.add(false);
        } else if (e is AdaptivePopupMenuItem<T>) {
          labels.add(e.label);
          symbols.add(e.icon is String ? e.icon as String : '');
          isDivider.add(false);
          enabled.add(e.enabled);
        }
      }

      final creationParams = <String, dynamic>{
        if (widget.buttonLabel != null) 'buttonTitle': widget.buttonLabel,
        if (widget.buttonIcon != null) 'buttonIconName': widget.buttonIcon,
        if (widget.isIconButton) 'round': true,
        if (isCustomWidget) 'customWidget': true, // Hide native button content
        'buttonStyle': widget.buttonStyle.name,
        'labels': labels,
        'sfSymbols': symbols,
        'isDivider': isDivider,
        'enabled': enabled,
        'isDark': _isDark,
        if (_effectiveTint != null) 'tint': _colorToARGB(_effectiveTint!),
      };

      // Create a unique key based on button label/icon and items to force recreation on change
      final itemsKey = widget.items
          .map((item) {
            if (item is AdaptivePopupMenuItem<T>) {
              return '${item.label}_${item.icon}_${item.enabled}_${item.value}';
            }
            return 'divider';
          })
          .join('_');

      final viewKey = ValueKey(
        '${widget.buttonLabel}_${widget.buttonIcon}_${widget.child?.runtimeType}_$itemsKey',
      );

      final platformView = UiKitView(
        key: viewKey,
        viewType: 'adaptive_platform_ui/ios26_popup_menu_button',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
        },
      );

      // Custom widget mode: Stack with custom widget determining size
      if (isCustomWidget) {
        return Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child!, // Determines size and is visible
            Positioned.fill(
              child:
                  platformView, // Native button overlay (transparent but catches touches)
            ),
          ],
        );
      }

      // Standard mode: Use LayoutBuilder for sizing
      return LayoutBuilder(
        builder: (context, constraints) {
          final hasBoundedWidth = constraints.hasBoundedWidth;
          final preferIntrinsic = widget.shrinkWrap || !hasBoundedWidth;

          double? width;
          if (widget.isIconButton) {
            width = widget.width ?? widget.height;
          } else if (preferIntrinsic) {
            width = _intrinsicWidth;
          }

          return SizedBox(
            height: widget.height,
            width:
                widget.width ??
                (preferIntrinsic
                    ? width
                    : (hasBoundedWidth ? constraints.maxWidth : null)),
            child: platformView,
          );
        },
      );
    }

    // Fallback to CupertinoButton with action sheet
    if (isCustomWidget) {
      return GestureDetector(
        onTap: () => _showContextMenu(context, Offset.zero),
        child: widget.child!,
      );
    }

    return SizedBox(
      height: widget.height,
      width: widget.isIconButton && widget.round
          ? (widget.width ?? widget.height)
          : null,
      child: CupertinoButton(
        padding: widget.isIconButton
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onPressed: () => _showContextMenu(context, Offset.zero),
        child: widget.isIconButton
            ? const Icon(CupertinoIcons.ellipsis)
            : Text(widget.buttonLabel ?? ''),
      ),
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel(
      'adaptive_platform_ui/ios26_popup_menu_button_$id',
    );
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    _lastTint = _effectiveTint != null ? _colorToARGB(_effectiveTint!) : null;
    _lastIsDark = _isDark;
    if (!widget.isIconButton) {
      _requestIntrinsicSize();
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'itemSelected') {
      final args = call.arguments as Map?;
      final idx = (args?['index'] as num?)?.toInt();

      if (idx != null) {
        // Native side skips dividers and only indexes selectable items
        final selectableItems = <AdaptivePopupMenuEntry>[];
        final originalIndices = <int>[];

        for (int i = 0; i < widget.items.length; i++) {
          if (widget.items[i] is AdaptivePopupMenuItem<T>) {
            selectableItems.add(widget.items[i]);
            originalIndices.add(i);
          }
        }

        if (idx >= 0 && idx < selectableItems.length) {
          final originalIndex = originalIndices[idx];
          final selectedEntry = widget.items[originalIndex];
          if (selectedEntry is AdaptivePopupMenuItem<T>) {
            widget.onSelected(originalIndex, selectedEntry);
          }
        }
      }
    }
    return null;
  }

  Future<void> _requestIntrinsicSize() async {
    final ch = _channel;
    if (ch == null) return;
    try {
      final size = await ch.invokeMethod<Map>('getIntrinsicSize');
      final w = (size?['width'] as num?)?.toDouble();
      if (w != null && mounted) {
        setState(() => _intrinsicWidth = w);
      }
    } catch (_) {}
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;

    final isDark = _isDark;
    final tint = _effectiveTint != null ? _colorToARGB(_effectiveTint!) : null;

    if (_lastIsDark != isDark) {
      try {
        await ch.invokeMethod('setBrightness', {'isDark': isDark});
        _lastIsDark = isDark;
      } catch (_) {}
    }

    if (_lastTint != tint && tint != null) {
      try {
        await ch.invokeMethod('setStyle', {'tint': tint});
        _lastTint = tint;
      } catch (_) {}
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final selected = await showCupertinoModalPopup<int>(
      context: context,
      builder: (ctx) {
        return CupertinoActionSheet(
          actions: [
            for (var i = 0; i < widget.items.length; i++)
              if (widget.items[i] is AdaptivePopupMenuItem<T>)
                CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(ctx).pop(i),
                  child: Text(
                    (widget.items[i] as AdaptivePopupMenuItem<T>).label,
                  ),
                )
              else
                const SizedBox(height: 8),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop(),
            isDefaultAction: true,
            child: Text(CupertinoLocalizations.of(ctx).cancelButtonLabel),
          ),
        );
      },
    );

    if (selected != null) {
      final selectedEntry = widget.items[selected];
      if (selectedEntry is AdaptivePopupMenuItem<T>) {
        widget.onSelected(selected, selectedEntry);
      }
    }
  }
}
