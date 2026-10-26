import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';

/// Copy a whole message, including Markdown and code fences, in one click.
class CopyChatMessage extends StatefulWidget {
  const CopyChatMessage({
    super.key,
    required this.text,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });
  final String text;
  final Widget child;
  final Alignment alignment;

  @override
  State<CopyChatMessage> createState() => _CopyChatMessageState();
}

class _CopyChatMessageState extends State<CopyChatMessage> {
  Timer? _feedback;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    _feedback?.cancel();
    setState(() => _copied = true);
    _feedback = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _feedback?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.child,
          if (widget.text.isNotEmpty)
            Align(
              alignment: widget.alignment,
              child: Pressable(
                onTap: _copy,
                semanticLabel: _copied ? '已复制' : '复制消息',
                builder: (context, hovered) => Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    NextIcon(_copied ? NextGlyph.check : NextGlyph.copy,
                        size: 12,
                        color: hovered ? NextColors.paper : NextColors.p3),
                    const SizedBox(width: 5),
                    Text(_copied ? '已复制' : '复制',
                        style: NextText.sans(11.5,
                            color: hovered ? NextColors.paper : NextColors.p3)),
                  ]),
                ),
              ),
            ),
        ],
      );
}
