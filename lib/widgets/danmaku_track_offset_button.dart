import 'package:flutter/material.dart';
import 'desktop_transient_overlay_scope.dart';

String formatDanmakuTrackOffset(double offset) {
  if (offset == 0) return '原始时间';
  return '${offset > 0 ? "提前" : "延后"}${offset.abs()}秒';
}

class DanmakuTrackOffsetButton extends StatelessWidget {
  const DanmakuTrackOffsetButton({
    super.key,
    required this.trackName,
    required this.offset,
    required this.onChanged,
  });

  final String trackName;
  final double offset;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: IconButton(
          tooltip: '轨道调轴：${formatDanmakuTrackOffset(offset)}',
          icon: const Icon(Icons.more_time, size: 18),
          onPressed: () async {
            final navigator = Navigator.of(context, rootNavigator: true);
            final themes = InheritedTheme.capture(
              from: context,
              to: navigator.context,
            );
            // Keep this player editor in the current view. Experimental
            // desktop windowing can promote showDialog to a native window,
            // whose first-frame ShowWindow blocks the Windows platform thread.
            final route = DialogRoute<double>(
              context: context,
              themes: themes,
              barrierColor: DialogTheme.of(context).barrierColor ??
                  Theme.of(context).dialogTheme.barrierColor ??
                  Colors.black54,
              traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
              builder: (_) =>
                  _OffsetDialog(trackName: trackName, offset: offset),
            );
            // A native popup's parent-view barrier sits above Navigator routes.
            // Close it before pushing, so the first dialog click reaches its UI.
            DesktopTransientOverlayScope.closeOf(context)?.call();
            final result = await navigator.push<double>(route);
            if (result != null) onChanged(result);
          },
        ),
      );
}

class _OffsetDialog extends StatefulWidget {
  const _OffsetDialog({required this.trackName, required this.offset});
  final String trackName;
  final double offset;

  @override
  State<_OffsetDialog> createState() => _OffsetDialogState();
}

class _OffsetDialogState extends State<_OffsetDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.offset.toString());
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final offset =
        double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (offset == null || !offset.isFinite) {
      setState(() => _error = '请输入有效的秒数');
      return;
    }
    Navigator.of(context).pop(offset);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.trackName} · 调轴'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          decoration: InputDecoration(
            labelText: '偏移秒数',
            helperText: '正数提前，负数延后；仅调整此轨道。\n整体偏移仍会叠加，调轴仅对当前播放有效。',
            helperMaxLines: 3,
            errorText: _error,
          ),
          onSubmitted: (_) => _apply(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(0.0),
            child: const Text('重置'),
          ),
          TextButton(onPressed: _apply, child: const Text('应用')),
        ],
      );
}
