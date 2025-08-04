import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/services/dandanplay_service.dart';

class FluentSendDanmakuDialog extends StatefulWidget {
  final int episodeId;
  final double currentTime;
  final Function(Map<String, dynamic>) onDanmakuSent;

  const FluentSendDanmakuDialog({
    super.key,
    required this.episodeId,
    required this.currentTime,
    required this.onDanmakuSent,
  });

  @override
  State<FluentSendDanmakuDialog> createState() => _FluentSendDanmakuDialogState();
}

class _FluentSendDanmakuDialogState extends State<FluentSendDanmakuDialog> {
  final TextEditingController _textController = TextEditingController();
  bool _isSending = false;

  int _colorToInt(Color color) {
    return (color.red * 256 * 256) + (color.green * 256) + color.blue;
  }

  Future<void> _sendDanmaku() async {
    if (_textController.text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      final result = await DandanplayService.sendDanmaku(
        episodeId: widget.episodeId,
        time: widget.currentTime,
        mode: 1, // Default mode for now
        color: _colorToInt(Colors.white), // Default color for now
        comment: _textController.text,
      );

      if (result['success'] == true && result.containsKey('danmaku')) {
        widget.onDanmakuSent(result['danmaku']);
      }
      
      if (mounted) {
        Navigator.of(context).pop(true);
      }

    } catch (e) {
      debugPrint("Error sending danmaku: $e");
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('发送弹幕'),
      content: TextBox(
        controller: _textController,
        placeholder: '输入弹幕内容...',
        autofocus: true,
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSending ? null : _sendDanmaku,
          child: _isSending ? const ProgressRing() : const Text('发送'),
        ),
      ],
    );
  }
}