import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../cards/card_views.dart';
import '../conversation/conversation.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/progress.dart';

/// State B (`.stage`): what you said in small grey, Nipa's reply large and
/// streaming, the cards it presented below.
class ConverseStage extends StatelessWidget {
  const ConverseStage({
    super.key,
    required this.conversation,
    required this.callbacks,
    this.focusedWorkId,
  });

  final Conversation conversation;
  final CardCallbacks callbacks;
  final String? focusedWorkId;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final questions = c.questionItems;
    return SizedBox(
      width: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.said != null)
            Row(children: [
              Text('你', style: NextText.sans(14, color: NextColors.p3)),
              const SizedBox(width: 10),
              Flexible(
                child: Text(c.said!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(14, color: NextColors.p2)),
              ),
            ]),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: NipaAvatar(
                    size: 30, mood: c.mood, sentence: c.moodSentence),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: StreamingReply(
                    text: c.reply,
                    thinking: c.thinking || (c.working && c.question == null),
                  ),
                ),
              ),
            ],
          ),
          if (questions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 18),
              child: _Question(conversation: c, items: questions),
            ),
          if (c.quiet)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 18),
              child: _Quiet(conversation: c),
            ),
          if (c.trouble != null)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 14),
              child: Text(c.trouble!,
                  style: NextText.sans(14, color: NextColors.p2)),
            ),
          if (c.cards.isNotEmpty) ...[
            const SizedBox(height: 26),
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: CardStack(
                cards: c.cards,
                callbacks: callbacks,
                focusedWorkId: focusedWorkId,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Nipa's reply, revealed character by character as it streams, with the
/// three dots while it is still thinking.
class StreamingReply extends StatefulWidget {
  const StreamingReply({super.key, required this.text, required this.thinking});
  final String text;
  final bool thinking;

  @override
  State<StreamingReply> createState() => _StreamingReplyState();
}

class _StreamingReplyState extends State<StreamingReply>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  double _shown = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _shown = widget.text.length.toDouble();
  }

  @override
  void didUpdateWidget(StreamingReply old) {
    super.didUpdateWidget(old);
    if (!widget.text.startsWith(
        old.text.substring(0, _shown.floor().clamp(0, old.text.length)))) {
      _shown = 0;
    }
    if (_shown < widget.text.length && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final target = widget.text.length;
    final behind = target - _shown;
    if (behind <= 0) {
      _ticker.stop();
      return;
    }
    // At least 36 characters a second; faster when far behind.
    final rate = behind * 5 > 36 ? behind * 5 : 36.0;
    setState(() => _shown = (_shown + rate * dt).clamp(0, target.toDouble()));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        widget.text.substring(0, _shown.floor().clamp(0, widget.text.length));
    final style = NextText.sans(19,
        weight: FontWeight.w500, height: 1.6, letterSpacing: 0.19);
    return Text.rich(
      TextSpan(style: style, children: [
        TextSpan(text: visible),
        if (widget.thinking)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(left: visible.isEmpty ? 2 : 8),
              child: const ThinkingDots(),
            ),
          ),
      ]),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.conversation, required this.items});
  final Conversation conversation;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final first = items.first;
    final options = (first['options'] as List? ?? const [])
        .whereType<Map>()
        .map((o) => o['label'] as String? ?? '')
        .where((l) => l.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (first['question'] case final String q when q.isNotEmpty)
          Text(q, style: NextText.sans(16, weight: FontWeight.w500)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final option in options)
            NextButton.ghost(
              label: option,
              height: 38,
              onTap: () => conversation.answerText(option),
            ),
        ]),
      ],
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.conversation});
  final Conversation conversation;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('好像没有回应', style: NextText.sans(14, color: NextColors.p2)),
          const SizedBox(height: 12),
          Row(children: [
            NextButton.ghost(
                label: '再等等', height: 36, onTap: conversation.keepWaiting),
            const SizedBox(width: 10),
            NextButton.ghost(
                label: '重新发', height: 36, onTap: conversation.resend),
          ]),
        ],
      );
}
