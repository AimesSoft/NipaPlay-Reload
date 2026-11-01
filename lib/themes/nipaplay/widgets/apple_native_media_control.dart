import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as native;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show PlatformViewHitTestBehavior, RenderBox;
import 'package:flutter/services.dart';
import 'package:nipaplay/utils/platform_identity.dart';

/// Native media-detail controls with platform-owned content and interaction.
class AppleNativeMediaControl extends StatefulWidget {
  const AppleNativeMediaControl({
    super.key,
    required this.label,
    required this.symbol,
    this.detail,
    this.primary = false,
    this.color,
    this.onPressed,
    this.items,
    this.onSelected,
  });

  static const _capabilities = MethodChannel('nipaplay/native_media_controls');
  static bool _supported = false;
  static bool get supported => _supported;

  static Future<void> initialize() async {
    _supported = false;
    if (kIsWeb ||
        !(native.PlatformInfo.isMacOS || native.PlatformInfo.isIOS || isTvOS)) {
      return;
    }
    try {
      _supported =
          await _capabilities.invokeMethod<bool>('supportsGlass') ?? false;
    } on MissingPluginException {
      // Older/unregistered native builds retain the Flutter controls.
    } on PlatformException {
      // A failed capability query must never enable an unavailable view.
    }
  }

  final String label;
  final String symbol;
  final String? detail;
  final bool primary;
  final Color? color;
  final VoidCallback? onPressed;
  final List<Map<String, Object?>>? items;
  final ValueChanged<int>? onSelected;

  @override
  State<AppleNativeMediaControl> createState() =>
      _AppleNativeMediaControlState();
}

class _AppleNativeMediaControlState extends State<AppleNativeMediaControl>
    with WidgetsBindingObserver {
  MethodChannel? _channel;
  final _focusNode = FocusNode(debugLabel: 'native media control');
  bool _hovered = false;
  bool _pressed = false;
  bool _trackingPointer = false;
  bool _focused = false;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _focusNode.onKeyEvent = (_, event) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.space) {
        _setPressed(event is! KeyUpEvent);
        // A repeat that doesn't match our shortcut could otherwise bubble to
        // the application's default ActivateIntent binding.
        if (event is KeyRepeatEvent) return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) {
      _pressed = false;
      _trackingPointer = false;
      _hovered = false;
    }
    _sendInteraction();
  }

  void _setPressed(bool value) {
    value = _enabled && _appActive && value;
    if (_pressed == value) return;
    _pressed = value;
    _sendInteraction();
  }

  void _setHovered(bool value) {
    value = _enabled && _appActive && value;
    if (_hovered == value) return;
    _hovered = value;
    _sendInteraction();
  }

  Future<void> _sendInteraction() async {
    if (!native.PlatformInfo.isMacOS) return;
    try {
      await _channel?.invokeMethod<void>('setInteraction', {
        'hovered': _enabled && _appActive && _hovered,
        'pressed': _enabled && _appActive && _pressed,
        'focused': _enabled && _appActive && _focused,
      });
    } on MissingPluginException {
      // The native view may be removed while a route transition is in flight.
    } on PlatformException catch (error) {
      debugPrint('Native media control interaction failed: $error');
    }
  }

  bool get _enabled => widget.items != null || widget.onPressed != null;

  Future<void> _activateNative() async {
    if (!_enabled || !_appActive) return;
    _focusNode.requestFocus();
    try {
      await _channel?.invokeMethod<void>('activate');
    } on MissingPluginException {
      // A route transition may already have disposed this native view.
    } on PlatformException catch (error) {
      debugPrint('Native media control activation failed: $error');
    }
  }

  Map<String, Object?> get _parameters => {
        'label': widget.label,
        'symbol': widget.symbol,
        'detail': widget.detail,
        'primary': widget.primary,
        'color': widget.color?.toARGB32(),
        'enabled': _enabled,
        'items': widget.items,
      };

  void _onCreated(int id) {
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('nipaplay/native_media_control_$id');
    _channel!.setMethodCallHandler((call) async {
      if (call.method == 'pressed') widget.onPressed?.call();
      if (call.method == 'selected') {
        final index = call.arguments;
        if (index is int && index >= 0 && index < (widget.items?.length ?? 0)) {
          widget.onSelected?.call(index);
        }
      }
    });
    _update();
    _sendInteraction();
  }

  @override
  void didUpdateWidget(covariant AppleNativeMediaControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) {
      _pressed = false;
      _trackingPointer = false;
      _hovered = false;
      _focusNode.unfocus();
    }
    _update();
    _sendInteraction();
  }

  Future<void> _update() async {
    try {
      await _channel?.invokeMethod<void>('update', _parameters);
    } on MissingPluginException {
      // The platform view may have been removed by a route transition.
    } on PlatformException catch (error) {
      debugPrint('Native media control update failed: $error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel?.setMethodCallHandler(null);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Native views must not remain above a Flutter dialog or pushed route.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return const SizedBox(height: 44);
    }
    const codec = StandardMessageCodec();
    if (native.PlatformInfo.isMacOS) {
      // This project's SDK renders AppKitView but has no macOS platform-view
      // gesture forwarding. Keep input in Flutter and activate the real Swift
      // NSButton through the channel, including its native NSMenu action.
      return Semantics(
        button: true,
        enabled: _enabled,
        label: widget.label,
        onTap: _enabled ? _activateNative : null,
        child: FocusableActionDetector(
          focusNode: _focusNode,
          enabled: _enabled,
          onFocusChange: (value) {
            _focused = value;
            if (!value) _pressed = false;
            _sendInteraction();
          },
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
                ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
                ActivateIntent(),
          },
          mouseCursor:
              _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activateNative();
                return null;
              },
            ),
          },
          child: MouseRegion(
            onEnter: (_) => _setHovered(true),
            onExit: (_) => _setHovered(false),
            onHover: (_) => _setHovered(true),
            child: Listener(
              onPointerDown: (_) {
                _trackingPointer = _enabled && _appActive;
                _setPressed(true);
              },
              onPointerUp: (_) {
                _trackingPointer = false;
                _setPressed(false);
              },
              onPointerCancel: (_) {
                _trackingPointer = false;
                _setPressed(false);
              },
              onPointerMove: (event) {
                if (!_trackingPointer) return;
                final box = context.findRenderObject();
                if (box is RenderBox) {
                  _setPressed(
                      (Offset.zero & box.size).contains(event.localPosition));
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: _enabled ? _activateNative : null,
                onTapCancel: () {
                  _trackingPointer = false;
                  _setPressed(false);
                },
                child: IgnorePointer(
                  child: SizedBox(
                    height: 44,
                    child: ExcludeFocus(
                      child: AppKitView(
                        viewType: 'nipaplay/native_media_control',
                        hitTestBehavior:
                            PlatformViewHitTestBehavior.transparent,
                        creationParams: _parameters,
                        creationParamsCodec: codec,
                        onPlatformViewCreated: _onCreated,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: UiKitView(
        viewType: 'nipaplay/native_media_control',
        gestureRecognizers: {
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        creationParams: _parameters,
        creationParamsCodec: codec,
        onPlatformViewCreated: _onCreated,
      ),
    );
  }
}
