import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../player/ports/session_playback.dart';
import 'package:nipaplay/widgets/in_view_dialog.dart';

Future<void> showNextGifDialog(
        BuildContext context, SessionPlayback playback) =>
    showInViewDialog<void>(
        context: context, builder: (_) => _GifDialog(playback: playback));

class _GifDialog extends StatefulWidget {
  const _GifDialog({required this.playback});
  final SessionPlayback playback;
  @override
  State<_GifDialog> createState() => _GifDialogState();
}

class _GifDialogState extends State<_GifDialog> {
  late final _start = TextEditingController(
      text:
          (widget.playback.position.inMilliseconds / 1000).toStringAsFixed(3));
  late final _end = TextEditingController(
      text: ((widget.playback.position.inMilliseconds + 5000)
                  .clamp(0, widget.playback.duration.inMilliseconds) /
              1000)
          .toStringAsFixed(3));
  final _fps = TextEditingController(text: '12');
  final _width = TextEditingController(text: '480');
  final _height = TextEditingController(text: '270');
  bool _high = false;
  bool _working = false;
  String? _message;

  @override
  void dispose() {
    for (final c in [_start, _end, _fps, _width, _height]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _export() async {
    final session = widget.playback.session;
    final start = double.tryParse(_start.text);
    final end = double.tryParse(_end.text);
    final fps = int.tryParse(_fps.text);
    final width = int.tryParse(_width.text);
    final height = int.tryParse(_height.text);
    if (session == null ||
        start == null ||
        end == null ||
        !start.isFinite ||
        !end.isFinite ||
        start < 0 ||
        end <= start ||
        end - start > 30 ||
        end * 1000 > session.duration.inMilliseconds ||
        fps == null ||
        fps < 1 ||
        fps > 30 ||
        width == null ||
        height == null ||
        width < 16 ||
        height < 16 ||
        width > 1920 ||
        height > 1080) {
      setState(() =>
          _message = '请输入视频内最长 30 秒的区间、1–30 FPS 和有效尺寸（16–1920 × 16–1080）。');
      return;
    }
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final location = await getSaveLocation(
          suggestedName: 'NipaPlay.gif',
          acceptedTypeGroups: [
            const XTypeGroup(label: 'GIF', extensions: ['gif'])
          ]);
      if (location == null) return;
      final result = await widget.playback.controls.capture({
        'sessionId': session.id,
        'kind': 'gif',
        'outputPath': location.path,
        'startMs': (start * 1000).round(),
        'endMs': (end * 1000).round(),
        'fps': fps,
        'width': width,
        'height': height,
        'quality': _high ? 'high' : 'normal',
      });
      if (mounted) setState(() => _message = '已导出：${result['path']}');
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('截取 GIF'),
        content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (label, controller) in [
                ('开始（秒）', _start),
                ('结束（秒）', _end),
                ('FPS', _fps),
                ('宽度', _width),
                ('高度', _height)
              ])
                TextField(
                    controller: controller,
                    enabled: !_working,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: label)),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('高质量'),
                  value: _high,
                  onChanged:
                      _working ? null : (v) => setState(() => _high = v!)),
              if (_working) const LinearProgressIndicator(),
              if (_message != null) SelectableText(_message!),
            ]))),
        actions: [
          TextButton(
              onPressed: _working ? null : () => Navigator.pop(context),
              child: const Text('关闭')),
          TextButton(
              onPressed: _working ? null : _export, child: const Text('导出'))
        ],
      );
}
