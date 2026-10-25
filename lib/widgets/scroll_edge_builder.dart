import 'package:flutter/widgets.dart';

/// Rebuilds controls only when scrolling crosses an end, rather than per pixel.
class ScrollEdgeBuilder extends StatefulWidget {
  const ScrollEdgeBuilder(
      {super.key, required this.controller, required this.builder});
  final ScrollController controller;
  final Widget Function(BuildContext, bool, bool) builder;
  @override
  State<ScrollEdgeBuilder> createState() => _ScrollEdgeBuilderState();
}

class _ScrollEdgeBuilderState extends State<ScrollEdgeBuilder>
    with WidgetsBindingObserver {
  (bool, bool) _edges = (false, false);
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_readEdges);
    WidgetsBinding.instance.addObserver(this);
    _scheduleRead();
  }

  void _scheduleRead() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _readEdges();
    });
  }

  @override
  void didChangeMetrics() => _scheduleRead();

  @override
  void didUpdateWidget(ScrollEdgeBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_readEdges);
      widget.controller.addListener(_readEdges);
    }
    _scheduleRead();
  }

  void _readEdges() {
    final positions = widget.controller.positions;
    final position = positions.length == 1 ? positions.single : null;
    final next = position == null || !position.hasContentDimensions
        ? (false, false)
        : (
            position.pixels > position.minScrollExtent + 5,
            position.pixels < position.maxScrollExtent - 5
          );
    if (next == _edges || !mounted) return;
    setState(() => _edges = next);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_readEdges);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _edges.$1, _edges.$2);
}
