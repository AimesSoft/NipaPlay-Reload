import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../mesh/nipa_peers.dart';

import '../cards/card_views.dart';
import '../conversation/nipa_chat.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/nipa_avatar.dart';
import '../theme/layout.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/words.dart';
import 'composer.dart';
import 'transcript.dart';

/// The conversation as a whole, wherever it is shown (the home expanded,
/// the side panel): its title, which opens the sessions; the transcript;
/// the composer. [trailing] closes or folds it, as its place does.
class ChatFrame extends StatelessWidget {
  const ChatFrame({
    super.key,
    required this.focusNode,
    required this.trailing,
    required this.callbacks,
    this.columnWidth = 720,
    this.textSize = 15,
    this.posterWidth = 150,
    this.sidePadding = 24,
    this.onSent,
  });

  final FocusNode focusNode;
  final Widget trailing;
  final CardCallbacks callbacks;
  final double columnWidth;
  final double textSize;
  final double posterWidth;
  final double sidePadding;
  final VoidCallback? onSent;

  /// A phone's sheet reaches the screen's foot: the composer sits just
  /// above the home indicator, or above the keyboard while it is up.
  static double _phoneFoot(BuildContext context) => math.max(
      MediaQuery.viewInsetsOf(context).bottom + 10,
      MediaQuery.paddingOf(context).bottom + 2);

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final chat = shell.chat;
    final phone = NextLayout.compact(context);
    Widget column(Widget child) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth),
            child: child,
          ),
        );
    return ListenableBuilder(
      listenable: Listenable.merge([chat, shell.services.logins]),
      builder: (context, _) => Column(children: [
        if (phone) ...[
          // A sheet's grabber, and who is talking: her face and the
          // device she runs on.
          Container(
            width: 38,
            height: 5,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
                color: const Color(0x4DFFFFFF),
                borderRadius: BorderRadius.circular(3)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(sidePadding - 4, 12, sidePadding - 8, 4),
            child: Row(children: [
              NipaAvatar(size: 40, mood: chat.mood),
              const SizedBox(width: 12),
              Expanded(child: _PhoneTitle(chat: chat, peers: shell.services.peers)),
              trailing,
            ]),
          ),
        ] else
        Padding(
          padding: EdgeInsets.fromLTRB(sidePadding, 14, sidePadding - 6, 6),
          child: column(Row(children: [
            _Title(chat: chat),
            const Spacer(),
            trailing,
          ])),
        ),
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              // On a phone a tap on the conversation puts the keyboard away
              // (a card or a link under the finger still takes the tap).
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: phone ? focusNode.unfocus : null,
                child: ChatTranscript(
                chat: chat,
                callbacks: callbacks,
                logins: shell.services.logins,
                columnWidth: columnWidth,
                textSize: textSize,
                posterWidth: posterWidth,
                padding: EdgeInsets.fromLTRB(sidePadding, 12, sidePadding, 72),
              ),
              ),
            ),
            if (chat.menuOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: chat.closeMenu,
                ),
              ),
            Positioned(
              left: sidePadding - 10,
              right: sidePadding - 10,
              top: 0,
              child: column(Align(
                alignment: Alignment.topLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.98, end: 1.0).animate(animation),
                      alignment: Alignment.topLeft,
                      child: child,
                    ),
                  ),
                  child: chat.menuOpen
                      ? _SessionMenu(key: const ValueKey('menu'), chat: chat)
                      : const SizedBox.shrink(),
                ),
              )),
            ),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(sidePadding - 8, 0, sidePadding - 8,
              phone ? _phoneFoot(context) : 16),
          child: column(ChatComposer(
            chat: chat,
            controller: shell.askText,
            focusNode: focusNode,
            onSent: onSent,
            textSize: textSize - 0.5,
          )),
        ),
      ]),
    );
  }
}

/// A phone's title: her name in the work titles' face, the device she
/// runs on under it (its dot lit while she can be reached there); it opens
/// the sessions.
class _PhoneTitle extends StatelessWidget {
  const _PhoneTitle({required this.chat, this.peers});
  final NipaChat chat;
  final NipaPeers? peers;

  /// 在工作站上, 在 MacBook Pro 上: a space only beside Latin letters.
  static String _on(String device) {
    final latin = RegExp(r'[A-Za-z0-9]');
    final before = latin.hasMatch(device[0]) ? ' ' : '';
    final after = latin.hasMatch(device[device.length - 1]) ? ' ' : '';
    return '在$before$device$after上';
  }

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: chat.toggleMenu,
        semanticLabel: '对话',
        pressScale: 0.98,
        builder: (context, _) => StreamBuilder<void>(
          stream: peers?.changes,
          builder: (context, _) {
            final device = peers?.chosenName;
            final live = peers?.chosenPeer?.usable ?? false;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.serif(20)),
                if (device != null && device.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: live ? NextColors.mint : NextColors.p4,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(_on(device),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NextText.sans(12, color: NextColors.p3)),
                      ),
                    ]),
                  ),
              ],
            );
          },
        ),
      );
}

/// The session's title; it opens the sessions.
class _Title extends StatelessWidget {
  const _Title({required this.chat});
  final NipaChat chat;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: chat.toggleMenu,
        semanticLabel: '对话',
        pressScale: 0.98,
        builder: (context, hovered) =>
            Row(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(chat.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(15, weight: FontWeight.w600)),
          ),
          const SizedBox(width: 7),
          AnimatedRotation(
            turns: chat.menuOpen ? -0.25 : 0.25,
            duration: const Duration(milliseconds: 180),
            child: NextIcon(NextGlyph.chevronRight,
                size: 11,
                color:
                    hovered || chat.menuOpen ? NextColors.p2 : NextColors.p4),
          ),
        ]),
      );
}

/// A round button for the frame's corner: fold or close.
class FrameButton extends StatelessWidget {
  const FrameButton(
      {super.key,
      required this.glyph,
      required this.label,
      required this.onTap,
      this.turns = 0});
  final NextGlyph glyph;
  final String label;
  final VoidCallback onTap;

  /// Quarter turns of the glyph (a chevron pointing down: 1).
  final int turns;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered ? const Color(0x1AFFFFFF) : const Color(0x00FFFFFF),
          ),
          child: RotatedBox(
            quarterTurns: turns,
            child: NextIcon(glyph,
                size: 14, color: hovered ? NextColors.paper : NextColors.p3),
          ),
        ),
      );
}

/// The main session on top, then a new conversation, then the others,
/// latest first, each titled by its first sentence.
class _SessionMenu extends StatelessWidget {
  const _SessionMenu({super.key, required this.chat});
  final NipaChat chat;

  static String _when(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    String two(int n) => n.toString().padLeft(2, '0');
    if (days == 0) return '${two(at.hour)}:${two(at.minute)}';
    if (days == 1) return '昨天';
    if (at.year == now.year) return '${at.month} 月 ${at.day} 日';
    return '${at.year} 年 ${at.month} 月';
  }

  @override
  Widget build(BuildContext context) {
    final main = chat.main;
    final mainSession = chat.sessions.where((s) => s.id == main).firstOrNull;
    final others = [
      for (final s in chat.sessions)
        if (s.id != main) s
    ];
    Widget divider() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        color: NextColors.line);
    return Container(
      width: 360,
      constraints: const BoxConstraints(maxHeight: 380),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NextColors.line2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 16)),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _MenuRow(
            title: '主对话',
            when: _when(mainSession?.at),
            current: chat.onMain,
            onTap: chat.selectMain,
          ),
          _MenuRow(
            title: '新的对话',
            glyph: NextGlyph.plus,
            current: chat.fresh,
            onTap: chat.startNew,
          ),
          if (others.isNotEmpty) divider(),
          for (final s in others)
            _MenuRow(
              title: s.title,
              when: _when(s.at),
              current: s.id == chat.thread && !chat.onMain,
              onTap: () => chat.select(s.id),
            ),
        ]),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(
      {required this.title,
      required this.current,
      required this.onTap,
      this.when,
      this.glyph});
  final String title;
  final String? when;
  final NextGlyph? glyph;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: title,
        pressScale: 0.99,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hovered || current
                ? const Color(0x12FFFFFF)
                : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            if (glyph case final g?) ...[
              NextIcon(g,
                  size: 12,
                  color: current || hovered ? NextColors.paper : NextColors.p3),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(13.5,
                      weight: current ? FontWeight.w600 : FontWeight.w400,
                      color: current || hovered
                          ? NextColors.paper
                          : NextColors.p2)),
            ),
            if (when != null && when!.isNotEmpty) ...[
              const SizedBox(width: 12),
              NumText(when!, style: NextText.sans(11.5, color: NextColors.p3)),
            ],
          ]),
        ),
      );
}
