import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'interaction_notification.dart';

@internal
class GlassDragBuilder extends StatefulWidget {
  const GlassDragBuilder({
    required this.builder,
    this.behavior = HitTestBehavior.opaque,
    this.suppressInteractionOnChildren = true,
    this.child,
    super.key,
  });

  final HitTestBehavior behavior;
  final bool suppressInteractionOnChildren;
  final ValueWidgetBuilder<Offset?> builder;
  final Widget? child;

  @override
  State<GlassDragBuilder> createState() => _GlassDragBuilderState();
}

class _GlassDragBuilderState extends State<GlassDragBuilder> {
  Offset? currentDragOffset;
  bool _shouldIgnoreCurrentPointer = false;

  bool get isDragging => currentDragOffset != null;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<InteractionNotification>(
      onNotification: (notification) {
        if (widget.suppressInteractionOnChildren) {
          _shouldIgnoreCurrentPointer = true;
        }
        return false; // Let it bubble
      },
      child: Listener(
        behavior: widget.behavior,
        onPointerDown: (event) {
          if (widget.suppressInteractionOnChildren &&
              _shouldIgnoreCurrentPointer) {
            _shouldIgnoreCurrentPointer = false;
            return;
          }
          if (!mounted) return;
          setState(() => currentDragOffset = Offset.zero);
        },
        onPointerMove: (event) {
          if (currentDragOffset == null) return;
          if (!mounted) return;
          setState(() {
            currentDragOffset =
                (currentDragOffset ?? Offset.zero) + event.delta;
          });
        },
        onPointerUp: (event) {
          _shouldIgnoreCurrentPointer = false;
          if (!mounted) return;
          setState(() => currentDragOffset = null);
        },
        onPointerCancel: (event) {
          _shouldIgnoreCurrentPointer = false;
          if (!mounted) return;
          setState(() => currentDragOffset = null);
        },
        child: widget.builder(context, currentDragOffset, widget.child),
      ),
    );
  }
}
