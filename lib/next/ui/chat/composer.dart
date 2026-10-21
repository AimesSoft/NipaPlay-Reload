import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../conversation/next_sayings.dart';
import '../conversation/nipa_chat.dart';
import '../shell/nipa_setup.dart';
import '../theme/tokens.dart';
import '../widgets/attachments.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/poster_art.dart';
import '../widgets/progress.dart';
import '../widgets/words.dart';

/// Where you talk to Nipa, under the conversation: what this conversation
/// set going that is still under way, the work it is about, the files
/// dropped in, and the input. Enter sends (a new turn, or more for the
/// running one), Shift-Enter starts a new line. While a turn runs and the
/// input is empty, the send button stops it.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.chat,
    required this.controller,
    required this.focusNode,
    this.onSent,
    this.textSize = 14.5,
  });

  final NipaChat chat;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// After something was said.
  final VoidCallback? onSent;
  final double textSize;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.focusNode.onKeyEvent = _key;
  }

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (old.focusNode != widget.focusNode) {
      old.focusNode.onKeyEvent = null;
      widget.focusNode.onKeyEvent = _key;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    if (widget.focusNode.onKeyEvent == _key) widget.focusNode.onKeyEvent = null;
    super.dispose();
  }

  void _changed() => setState(() {});

  KeyEventResult _key(FocusNode node, KeyEvent event) =>
      composerKey(widget.controller, event, _send);

  void _send() {
    final chat = widget.chat;
    final text = widget.controller.text.trim();
    if ((text.isEmpty && chat.attachments.isEmpty) || !chat.acceptsTyping) {
      return;
    }
    widget.controller.clear();
    chat.say(text);
    widget.onSent?.call();
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final empty =
        widget.controller.text.trim().isEmpty && chat.attachments.isEmpty;
    final underway = chat.underway;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (underway.isNotEmpty) UnderwayBar(items: underway),
      Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xE616161C),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: NextColors.line2),
          boxShadow: const [
            BoxShadow(
                color: Color(0x59000000),
                blurRadius: 30,
                offset: Offset(0, 12)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chat.about != null || chat.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, right: 10),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (chat.about case final work?)
                    AboutTag(work: work, onRemove: () => chat.setAbout(null)),
                  if (chat.attachments.isNotEmpty)
                    AttachmentStrip(
                        paths: chat.attachments, onRemove: chat.detach),
                ]),
              ),
            const NipaSetupChip(padding: EdgeInsets.only(bottom: 8)),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    enabled: chat.acceptsTyping,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    cursorColor: NextColors.accent,
                    cursorWidth: 1.5,
                    style: NextText.sans(widget.textSize, height: 1.5),
                    decoration: InputDecoration.collapsed(
                      hintText: chat.hint,
                      hintStyle:
                          NextText.sans(widget.textSize, color: NextColors.p3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SendOrStop(
                stop: chat.running && empty,
                onSend: _send,
                onStop: chat.stop,
              ),
            ]),
          ],
        ),
      ),
    ]);
  }
}

/// Enter sends, Shift-Enter is a new line; while an input method is
/// composing, Enter is its own.
KeyEventResult composerKey(
    TextEditingController controller, KeyEvent event, VoidCallback send) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final enter = event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter;
  if (!enter) return KeyEventResult.ignored;
  if (controller.value.composing.isValid) return KeyEventResult.ignored;
  if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
  send();
  return KeyEventResult.handled;
}

/// The send button; while a turn runs and there is nothing to send, it
/// stops the turn.
class SendOrStop extends StatelessWidget {
  const SendOrStop(
      {super.key,
      required this.stop,
      required this.onSend,
      required this.onStop,
      this.size = 36});
  final bool stop;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: stop
            ? Pressable(
                key: const ValueKey('stop'),
                onTap: onStop,
                semanticLabel: '停止',
                builder: (context, hovered) => AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hovered ? NextColors.paper : const Color(0xDDF5F1EA),
                  ),
                  child: Container(
                    width: size * 0.3,
                    height: size * 0.3,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111116),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
              )
            : SendButton(
                key: const ValueKey('send'), onTap: onSend, size: size),
      );
}

/// “关于《X》”: what you say goes with this work until × takes it off.
class AboutTag extends StatelessWidget {
  const AboutTag({super.key, required this.work, required this.onRemove});
  final UiWork work;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.fromLTRB(5, 5, 4, 5),
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NextColors.line2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 15,
              height: 22,
              child: PosterArt(work.artwork.poster,
                  tint: work.artwork.tint, read: false),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text('关于《${work.title}》',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(12.5, color: NextColors.p2)),
          ),
          const SizedBox(width: 2),
          Pressable(
            onTap: onRemove,
            semanticLabel: '不再关于这部',
            builder: (context, hovered) => Padding(
              padding: const EdgeInsets.all(6),
              child: NextIcon(NextGlyph.close,
                  size: 10, color: hovered ? NextColors.paper : NextColors.p3),
            ),
          ),
        ]),
      );
}

/// What this conversation set going that is still under way, in one thin
/// line over the input (“《迷宫饭》下载 47% · 然后补上弹幕”); tapped, every
/// one of them with its progress.
class UnderwayBar extends StatefulWidget {
  const UnderwayBar({super.key, required this.items});
  final List<Underway> items;

  @override
  State<UnderwayBar> createState() => _UnderwayBarState();
}

class _UnderwayBarState extends State<UnderwayBar> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final first = items.first;
    final more = items.length - 1;
    final head = Pressable(
      onTap: () => setState(() => _open = !_open),
      semanticLabel: '后台的事',
      pressScale: 0.99,
      builder: (context, hovered) => SizedBox(
        height: 34,
        child: Row(children: [
          const SizedBox(width: 2),
          const PulseDot(size: 6),
          const SizedBox(width: 10),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                if (!_open)
                  TextSpan(
                      text: first.isWork
                          ? '《${first.title}》 '
                          : '${first.title} ',
                      style: NextText.sans(12.5,
                          weight: FontWeight.w600, color: NextColors.paper)),
                TextSpan(
                    text: _open ? '这次对话在后台做的事' : first.line,
                    style: NextText.sans(12.5, color: NextColors.p2)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (more > 0 && !_open) ...[
            const SizedBox(width: 8),
            NumText('还有 $more 件',
                style: NextText.sans(12, color: NextColors.p3)),
          ],
          const SizedBox(width: 8),
          AnimatedRotation(
            turns: _open ? 0.25 : -0.25,
            duration: const Duration(milliseconds: 160),
            child: NextIcon(NextGlyph.chevronRight,
                size: 10, color: hovered ? NextColors.p2 : NextColors.p4),
          ),
        ]),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xD916161C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NextColors.line),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: NextMotion.ease,
        alignment: Alignment.bottomCenter,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          head,
          if (_open)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12, top: 2),
                child: Column(children: [
                  for (final (i, item) in items.indexed) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _UnderwayRow(item: item),
                  ],
                ]),
              ),
            )
          else if (first.progress case final progress?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ThinBar(
                  progress: progress,
                  height: 2,
                  live: true,
                  track: const Color(0x14FFFFFF)),
            ),
        ]),
      ),
    );
  }
}

class _UnderwayRow extends StatelessWidget {
  const _UnderwayRow({required this.item});
  final Underway item;

  @override
  Widget build(BuildContext context) => Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 30,
            height: 44,
            child: PosterArt(item.artwork?.poster,
                tint: item.artwork?.tint, read: false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(13, weight: FontWeight.w600)),
              const SizedBox(height: 3),
              NumText(item.line,
                  style: NextText.sans(12, color: NextColors.p3)),
              if (item.progress case final progress?) ...[
                const SizedBox(height: 7),
                ThinBar(
                    progress: progress,
                    height: 3,
                    live: true,
                    track: const Color(0x1AFFFFFF)),
              ],
            ],
          ),
        ),
      ]);
}
