import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

/// Where files can be dropped for Nipa: the side panel and the home's input
/// bar. Classic's window-wide drop (which plays a video) leaves the drops
/// that land on one of these alone, and hides its own hint over them.
abstract final class NextDropZones {
  static final _zones = <_NextDropZoneState>{};

  /// A drag or drop at [global] is over a zone that takes it now.
  static bool claims(Offset global) => _zones.any((z) => z._takes(global));
}

/// Takes files dropped on [builder]'s area while [enabled] and on screen,
/// telling [builder] while a drag is over it.
class NextDropZone extends StatefulWidget {
  const NextDropZone({
    super.key,
    required this.onDrop,
    required this.builder,
    this.enabled = true,
  });

  final ValueChanged<List<String>> onDrop;
  final Widget Function(BuildContext context, bool over) builder;
  final bool enabled;

  @override
  State<NextDropZone> createState() => _NextDropZoneState();
}

class _NextDropZoneState extends State<NextDropZone> {
  bool _over = false;

  @override
  void initState() {
    super.initState();
    NextDropZones._zones.add(this);
  }

  @override
  void dispose() {
    NextDropZones._zones.remove(this);
    super.dispose();
  }


  /// Hidden sections and Next behind Classic's player do not take drops.
  bool _live = false;

  bool _takes(Offset global) {
    if (!mounted || !_live) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    return (Offset.zero & box.size).contains(box.globalToLocal(global));
  }

  void _set(bool over) {
    if (over != _over) setState(() => _over = over);
  }

  @override
  Widget build(BuildContext context) {
    _live = widget.enabled && TickerMode.valuesOf(context).enabled;
    return DropTarget(
        enable: _live,
        onDragEntered: (_) => _set(true),
        onDragExited: (_) => _set(false),
        onDragDone: (details) {
          _set(false);
          final paths = [
            for (final f in details.files)
              if (f.path.isNotEmpty) f.path
          ];
          if (paths.isNotEmpty) widget.onDrop(paths);
        },
        child: widget.builder(context, _over));
  }
}
