import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../adaptive_app_bar_action.dart';

/// Native iOS 26 UIToolbar widget using platform views
/// Implements Liquid Glass design with blur effects
class IOS26NativeToolbar extends StatefulWidget {
  const IOS26NativeToolbar({
    super.key,
    this.title,
    this.leading,
    this.leadingText,
    this.actions,
    this.onLeadingTap,
    this.onActionTap,
    this.height = 44.0,
  });

  final String? title;
  final Widget? leading;
  final String? leadingText;
  final List<AdaptiveAppBarAction>? actions;
  final VoidCallback? onLeadingTap;
  final ValueChanged<int>? onActionTap;
  final double height;

  @override
  State<IOS26NativeToolbar> createState() => _IOS26NativeToolbarState();
}

class _IOS26NativeToolbarState extends State<IOS26NativeToolbar> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) {
    // Only use native toolbar on iOS 26+
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return _buildFallbackToolbar();
    }

    final safePadding = MediaQuery.of(context).padding.top;

    // Priority: custom leading widget > leadingText
    // If custom leading widget provided, don't send leadingText to native
    final creationParams = <String, dynamic>{
      if (widget.title != null) 'title': widget.title!,
      if (widget.leading == null && widget.leadingText != null)
        'leading': widget.leadingText!,
      if (widget.actions != null && widget.actions!.isNotEmpty)
        'actions': widget.actions!
            .map((action) => action.toNativeMap())
            .toList(),
    };

    final toolbar = Container(
      height: widget.height + safePadding,
      decoration: BoxDecoration(
        gradient: Theme.brightnessOf(context) == Brightness.light
            ? const LinearGradient(
                colors: [
                  Color.fromARGB(229, 255, 255, 255),
                  Color.fromARGB(0, 255, 255, 255),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : const LinearGradient(
                colors: [
                  Color.fromARGB(234, 0, 0, 0),
                  Color.fromARGB(137, 0, 0, 0),
                  Color.fromARGB(0, 0, 0, 0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
      ),
      child: UiKitView(
        viewType: 'adaptive_platform_ui/ios26_toolbar',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
        hitTestBehavior: PlatformViewHitTestBehavior.translucent,
        // Enable Hybrid Composition mode for better layer integration
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      ),
    );

    // If custom leading widget provided, overlay it on top of native toolbar
    if (widget.leading != null) {
      return SizedBox(
        height: widget.height + safePadding,
        child: Stack(
          children: [
            toolbar,
            Positioned(
              left: 8,
              top: safePadding,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: IgnorePointer(ignoring: false, child: widget.leading!),
              ),
            ),
          ],
        ),
      );
    }

    return toolbar;
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('adaptive_platform_ui/ios26_toolbar_$id');
    _channel!.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLeadingTapped':
        widget.onLeadingTap?.call();
        break;
      case 'onActionTapped':
        if (call.arguments is Map) {
          final args = call.arguments as Map;
          final index = args['index'] as int?;
          if (index != null) {
            widget.onActionTap?.call(index);
          }
        }
        break;
    }
  }

  /// Fallback toolbar for non-iOS platforms or older iOS versions
  Widget _buildFallbackToolbar() {
    return Container(
      height: widget.height + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          bottom: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (widget.leading != null) widget.leading!,
          const Spacer(),
          if (widget.title != null)
            Text(
              widget.title!,
              style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
            ),
          const Spacer(),
          if (widget.actions != null && widget.actions!.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.actions!.map((action) {
                return CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: action.onPressed,
                  child: action.title != null
                      ? Text(action.title!)
                      : const Icon(CupertinoIcons.circle),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
