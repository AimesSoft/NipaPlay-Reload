import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../platform/platform_info.dart';
import 'ios26_native_view_route_guard.dart';

/// A bare iOS 26 Liquid Glass surface under [child]: UIKit draws the glass,
/// Flutter draws [child] on it. A capsule unless [cornerRadius] is given.
/// The glass takes no touches; [child] handles them.
///
/// Only on iOS 26 and later ([supported]); elsewhere callers draw their own.
class IOS26Glass extends StatefulWidget {
  const IOS26Glass({
    super.key,
    this.cornerRadius,
    this.tint,
    this.clear = false,
    this.dark,
    this.child,
  });

  final double? cornerRadius;
  final Color? tint;

  /// The clear variant: more of what is behind shows through.
  final bool clear;

  /// The appearance the glass takes, whatever the system's; null follows it.
  final bool? dark;
  final Widget? child;

  static bool get supported => !kIsWeb && PlatformInfo.isIOS26OrHigher();

  @override
  State<IOS26Glass> createState() => _IOS26GlassState();
}

class _IOS26GlassState extends State<IOS26Glass> {
  MethodChannel? _channel;

  Map<String, Object?> get _params => {
        if (widget.cornerRadius != null) 'cornerRadius': widget.cornerRadius,
        if (widget.tint != null) 'tint': widget.tint!.toARGB32(),
        'style': widget.clear ? 'clear' : 'regular',
        if (widget.dark != null) 'dark': widget.dark,
      };

  @override
  void didUpdateWidget(IOS26Glass old) {
    super.didUpdateWidget(old);
    if (old.cornerRadius != widget.cornerRadius ||
        old.tint != widget.tint ||
        old.clear != widget.clear ||
        old.dark != widget.dark) {
      _channel?.invokeMethod('update', _params);
    }
  }

  @override
  Widget build(BuildContext context) {
    final glass = ios26NativeViewRouteIsCurrent(context)
        ? IgnorePointer(
            child: UiKitView(
              viewType: 'adaptive_platform_ui/ios26_glass',
              creationParams: _params,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: (id) => _channel =
                  MethodChannel('adaptive_platform_ui/ios26_glass_$id'),
            ),
          )
        : const SizedBox.shrink();
    return Stack(fit: StackFit.passthrough, children: [
      Positioned.fill(child: glass),
      if (widget.child != null) widget.child!,
    ]);
  }
}
