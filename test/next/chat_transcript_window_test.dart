import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/cards/card_views.dart';
import 'package:nipaplay/next/ui/chat/transcript.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/conversation/nipa_chat.dart';
import 'package:nipaplay/next/ui/data/login_requests.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

void main() {
  testWidgets('a thousand turns build only the visible history window',
      (tester) async {
    final turns = [
      for (var i = 0; i < 1000; i++)
        (ChatTurn()..status = 'completed')
          ..parts.add(ReplyPart('reply-$i', '回合 $i'))
    ];
    final chat = NipaChat(port: _OfflinePort(), data: _ChatData());
    chat.turns = turns;
    final logins = LoginRequests();
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      chat.dispose();
      logins.dispose();
    }

    addTearDown(() {
      close();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatTranscript(
          chat: chat,
          callbacks: const CardCallbacks(),
          logins: logins,
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(chat.turns, hasLength(1000));
    expect(chat.visibleTurns, hasLength(NipaChat.historyTurns));
    expect(chat.visibleTurns.first, same(turns[970]));
    expect(chat.visibleTurns.last, same(turns.last));
    expect(find.byKey(ObjectKey(turns[969])), findsNothing);
    expect(find.byKey(ObjectKey(turns[970])), findsNothing);
    expect(find.byKey(ObjectKey(turns[999])), findsOneWidget);
    expect(find.text('回合 969'), findsNothing);
    expect(find.text('回合 970'), findsNothing);
    expect(find.text('回合 999'), findsOneWidget);
    final scroll = ChatTranscript.debugController!;
    expect(scroll.offset, scroll.position.maxScrollExtent);
    scroll.jumpTo(0);
    await tester.pump();
    expect(find.text('回合 970'), findsOneWidget);
    expect(find.text('回合 999'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    close();
  });
  testWidgets(
      'stream growth follows idle bottom and preserves reading/overscroll',
      (tester) async {
    final chat = NipaChat(port: _OfflinePort(), data: _ChatData());
    final logins = LoginRequests();
    final turn = ChatTurn()..status = 'completed';
    turn.parts.add(ReplyPart('answer', List.filled(80, '原有内容').join('\n\n')));
    chat.turns = [turn];
    Widget view() => MaterialApp(
            home: Scaffold(
                body: ScrollConfiguration(
          behavior: const _Bounce(),
          child: ChatTranscript(
              chat: chat, callbacks: const CardCallbacks(), logins: logins),
        )));
    await tester.pumpWidget(view());
    await tester.pump();
    final scroll = ChatTranscript.debugController!;
    expect(scroll.offset, scroll.position.maxScrollExtent);
    await tester.drag(find.byType(ListView).first, const Offset(0, 300));
    await tester.pumpAndSettle();
    final reading = scroll.offset;
    turn.parts.add(ReplyPart('more', List.filled(20, '新增内容').join('\n\n')));
    await tester.pumpWidget(view());
    await tester.pump();
    expect(scroll.offset, closeTo(reading, 1));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(ListView).first));
    await gesture.moveBy(const Offset(0, -180));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    expect(scroll.position.outOfRange, true);
    final bouncing = scroll.offset;
    turn.parts.add(ReplyPart('last', '输出过程中的新一段'));
    await tester.pumpWidget(view());
    await tester.pump();
    expect(scroll.offset, closeTo(bouncing, 1));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    chat.dispose();
    logins.dispose();
  });
}

final class _OfflinePort implements ChatPort {
  @override
  bool get available => false;
  @override
  Future<String?> unavailableReason() async => null;
  @override
  bool get busy => false;
  @override
  bool busyOn(String threadId) => false;
  @override
  Stream<ChatEvent> get display => const Stream.empty();
  @override
  Stream<ChatEvent> get questions => const Stream.empty();
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ChatData implements NextUiData {
  @override
  Stream<void> get changes => const Stream<void>.empty();
  @override
  Stream<List<UiTask>> tasks() => const Stream<List<UiTask>>.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bounce extends MaterialScrollBehavior {
  const _Bounce();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
