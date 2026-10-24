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

    expect(chat.turns, hasLength(1000));
    expect(chat.visibleTurns, hasLength(NipaChat.historyTurns));
    expect(chat.visibleTurns.first, same(turns[970]));
    expect(chat.visibleTurns.last, same(turns.last));
    expect(find.byKey(ObjectKey(turns[969])), findsNothing);
    expect(find.byKey(ObjectKey(turns[970])), findsOneWidget);
    expect(find.byKey(ObjectKey(turns[999])), findsOneWidget);
    expect(find.text('回合 969'), findsNothing);
    expect(find.text('回合 970'), findsOneWidget);
    expect(find.text('回合 999'), findsOneWidget);
    close();
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
