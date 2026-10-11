import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/nipa_avatar.dart';

/// `.askbar`: the input that stays under the hero, and 2–3 suggestions.
/// Tapping a suggestion says it.
class AskBar extends StatefulWidget {
  const AskBar({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.onSay,
    required this.mood,
    this.moodSentence,
    this.suggestions = const [],
    this.hint = '今天想看什么？',
    this.maxWidth = double.infinity,
  });

  final FocusNode focusNode;
  final TextEditingController controller;
  final ValueChanged<String> onSay;
  final NipaMood mood;
  final String? moodSentence;
  final List<String> suggestions;
  final String hint;
  final double maxWidth;

  @override
  State<AskBar> createState() => _AskBarState();
}

class _AskBarState extends State<AskBar> {
  TextEditingController get _text => widget.controller;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    widget.focusNode.addListener(_changed);
  }

  @override
  void didUpdateWidget(AskBar old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_changed);
      widget.focusNode.addListener(_changed);
    }
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_changed);
    _text.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _send([String? value]) {
    final text = (value ?? _text.text).trim();
    if (text.isEmpty) return;
    _text.clear();
    widget.onSay(text);
  }

  @override
  Widget build(BuildContext context) {
    final empty = _text.text.isEmpty;
    const fieldWidth = 640.0;
    final field = Glass(
      radius: BorderRadius.circular(28),
      color: const Color(0x9916161C),
      borderColor: const Color(0x24FFFFFF),
      shadows: const [
        BoxShadow(
            color: Color(0x73000000), blurRadius: 50, offset: Offset(0, 18)),
      ],
      child: SizedBox(
        width: fieldWidth,
        height: 56,
        child: Padding(
          padding: const EdgeInsets.only(left: 9, right: 8),
          child: Row(children: [
            NipaAvatar(
                size: 38, mood: widget.mood, sentence: widget.moodSentence),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: widget.focusNode,
                onSubmitted: _send,
                textInputAction: TextInputAction.send,
                maxLines: 1,
                cursorColor: NextColors.accent,
                cursorWidth: 1.5,
                cursorHeight: 18,
                style: NextText.sans(15.5),
                decoration: InputDecoration.collapsed(
                  hintText: widget.hint,
                  hintStyle: NextText.sans(15.5, color: NextColors.p3),
                ),
              ),
            ),
            if (empty && !widget.focusNode.hasFocus) ...[
              const KeyHint('⌘ K'),
              const SizedBox(width: 12),
            ] else
              const SizedBox(width: 12),
            SendButton(onTap: _send),
          ]),
        ),
      ),
    );

    final chips = widget.suggestions;
    return SizedBox(
      width: widget.maxWidth.isFinite ? widget.maxWidth : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          field,
          if (chips.isNotEmpty && empty)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: _FittingChips(chips: chips, onTap: _send),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows as many suggestions as fit in one line.
class _FittingChips extends StatelessWidget {
  const _FittingChips({required this.chips, required this.onTap});
  final List<String> chips;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final shown = <String>[];
        var used = 0.0;
        for (final chip in chips) {
          final painter = TextPainter(
            text: TextSpan(text: chip, style: NextText.sans(13)),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          final w = painter.width + 32 + (shown.isEmpty ? 0 : 10);
          painter.dispose();
          if (used + w > c.maxWidth) break;
          used += w;
          shown.add(chip);
        }
        return Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (i, chip) in shown.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            SuggestionChip(text: chip, onTap: () => onTap(chip)),
          ],
        ]);
      });
}
