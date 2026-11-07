import 'dart:async';
import 'package:flutter/widgets.dart';
import 'visible_updates.dart';

/// Only the live clock's text ticks; hidden and settled clocks have no timer.
class ElapsedText extends StatefulWidget {
  const ElapsedText(
      {super.key,
      required this.text,
      required this.style,
      this.running = true});
  final String Function() text;
  final TextStyle style;
  final bool running;
  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText>
    with VisibleUpdates<ElapsedText> {
  final _seconds = Stream<void>.multi((listener) {
    final timer =
        Timer.periodic(const Duration(seconds: 1), (_) => listener.add(null));
    listener.onCancel = timer.cancel;
  }, isBroadcast: true);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watch();
  }

  @override
  void didUpdateWidget(ElapsedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _watch();
  }

  void _watch() => watchUpdates(_seconds, () async {
        if (mounted) setState(() {});
      }, enabled: widget.running);
  @override
  Widget build(BuildContext context) =>
      Text(widget.text(), style: widget.style);
}
