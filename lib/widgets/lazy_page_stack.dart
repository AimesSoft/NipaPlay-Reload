import 'package:flutter/widgets.dart';

/// Creates pages on first visit and retains them by identity, even after reorder.
/// Hidden pages cannot animate, receive input, or retain keyboard focus.
class LazyPageStack extends StatefulWidget {
  const LazyPageStack(
      {super.key,
      required this.pageIds,
      required this.selectedId,
      required this.builder});
  final List<String> pageIds;
  final String selectedId;
  final Widget Function(BuildContext, String) builder;

  @override
  State<LazyPageStack> createState() => _LazyPageStackState();
}

class _LazyPageStackState extends State<LazyPageStack> {
  final Set<String> _visited = {};

  @override
  Widget build(BuildContext context) {
    _visited.removeWhere((id) => !widget.pageIds.contains(id));
    _visited.add(widget.selectedId);
    return Stack(fit: StackFit.expand, children: [
      for (final id in widget.pageIds)
        if (_visited.contains(id))
          Offstage(
            key: ValueKey(id),
            offstage: id != widget.selectedId,
            child: TickerMode(
              enabled: id == widget.selectedId,
              child: ExcludeFocus(
                excluding: id != widget.selectedId,
                child: RepaintBoundary(child: widget.builder(context, id)),
              ),
            ),
          ),
    ]);
  }
}
