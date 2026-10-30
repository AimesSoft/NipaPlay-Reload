import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/widgets.dart';

import '../../player/ports/session_playback.dart';
import '../settings/controls.dart' show BusyDots, NextToggle;
import '../theme/tokens.dart';
import '../widgets/dialog.dart';

/// 截取 GIF, in Next's own dialog over the player.
Future<void> showNextGifDialog(
        BuildContext context, SessionPlayback playback) =>
    Navigator.of(context, rootNavigator: true).push(
        NextDialogRoute<void>(builder: (_) => _GifDialog(playback: playback)));

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
  bool _failed = false;

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
      setState(() {
        _failed = true;
        _message = '请输入视频内最长 30 秒的区间、1–30 FPS 和有效尺寸（16–1920 × 16–1080）。';
      });
      return;
    }
    setState(() {
      _working = true;
      _failed = false;
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
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '$error';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _close() {
    if (!_working) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController controller) =>
        Expanded(child: NextDialogField(label: label, controller: controller));
    return NextDialog(
      title: '截取 GIF',
      subtitle: '视频内最长 30 秒',
      onCancel: _close,
      body: [
        Row(children: [
          field('开始（秒）', _start),
          const SizedBox(width: 12),
          field('结束（秒）', _end),
        ]),
        Row(children: [
          field('FPS', _fps),
          const SizedBox(width: 12),
          field('宽度', _width),
          const SizedBox(width: 12),
          field('高度', _height),
        ]),
        Row(children: [
          Expanded(
            child:
                Text('高质量', style: NextText.sans(13.5, color: NextColors.p2)),
          ),
          NextToggle(
              value: _high,
              label: '高质量',
              onChanged: _working ? null : (v) => setState(() => _high = v)),
        ]),
        if (_working)
          Row(children: [
            const BusyDots(color: NextColors.p2),
            const SizedBox(width: 10),
            Text('正在导出', style: NextText.sans(13, color: NextColors.p3)),
          ]),
        if (_message case final message?)
          SelectableText(message,
              style: NextText.sans(13,
                  color: _failed ? NextColors.accent2 : NextColors.p3,
                  height: 1.5)),
      ],
      actions: [
        NextDialogButton(label: '关闭', onTap: _working ? null : _close),
        NextDialogButton(
            label: '导出',
            kind: NextDialogButtonKind.primary,
            onTap: _working ? null : _export),
      ],
    );
  }
}
