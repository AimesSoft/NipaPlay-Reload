import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ios26_native_view_route_guard.dart';

class IOS26ButtonGroupItem {
  const IOS26ButtonGroupItem({
    required this.label,
    required this.sfSymbol,
    this.enabled = true,
  });

  final String label;
  final String sfSymbol;
  final bool enabled;

  Map<String, Object> toCreationParams() => <String, Object>{
    'label': label,
    'sfSymbol': sfSymbol,
    'enabled': enabled,
  };
}

/// Native iOS 26 action capsule backed by grouped toolbar buttons.
class IOS26ButtonGroup extends StatefulWidget {
  const IOS26ButtonGroup({
    super.key,
    required this.items,
    required this.onPressed,
    this.height = 44,
    this.itemWidth = 44,
  });

  final List<IOS26ButtonGroupItem> items;
  final ValueChanged<int> onPressed;
  final double height;
  final double itemWidth;

  @override
  State<IOS26ButtonGroup> createState() => _IOS26ButtonGroupState();
}

class _IOS26ButtonGroupState extends State<IOS26ButtonGroup> {
  static int _nextId = 0;

  late final int _id = _nextId++;
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant IOS26ButtonGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.items, widget.items)) {
      _channel?.invokeMethod<void>('setItems', _itemsParams());
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.itemWidth * widget.items.length, widget.height);
    if (widget.items.isEmpty) return const SizedBox.shrink();
    if (kIsWeb || !Platform.isIOS || !ios26NativeViewRouteIsCurrent(context)) {
      return SizedBox.fromSize(size: size);
    }

    return SizedBox.fromSize(
      size: size,
      child: UiKitView(
        viewType: 'adaptive_platform_ui/ios26_button_group',
        creationParams: <String, Object>{'id': _id, 'items': _itemsParams()},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }

  List<Map<String, Object>> _itemsParams() => widget.items
      .map((item) => item.toCreationParams())
      .toList(growable: false);

  void _onPlatformViewCreated(int _) {
    _channel = MethodChannel('adaptive_platform_ui/ios26_button_group_$_id')
      ..setMethodCallHandler((call) async {
        if (call.method != 'pressed' || call.arguments is! Map) return;
        final index = (call.arguments as Map<Object?, Object?>)['index'];
        if (index is int && index >= 0 && index < widget.items.length) {
          widget.onPressed(index);
        }
      });
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}
