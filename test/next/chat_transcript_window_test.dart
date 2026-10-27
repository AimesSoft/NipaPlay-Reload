import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/cards/card_views.dart';
import 'package:nipaplay/next/ui/chat/transcript.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/conversation/nipa_chat.dart';
import 'package:nipaplay/next/ui/data/login_requests.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

void main() {
  testWidgets(
      'history pages reach the first of a thousand variable-height turns',
      (tester) async {
    final port = _HistoryPort(1000);
    final chat = NipaChat(port: port, data: _ChatData());
    final logins = LoginRequests();
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      chat.dispose();
      logins.dispose();
    }

    addTearDown(close);
    await tester.runAsync(() => chat.select('long'));
    expect(chat.turns, hasLength(30));
    expect(chat.turns.first.id, 'turn-970');
    expect(chat.hasEarlierHistory, true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: chat,
          builder: (context, _) => ChatTranscript(
            chat: chat,
            callbacks: const CardCallbacks(),
            logins: logins,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final scroll = ChatTranscript.debugController!;
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(find.text('回合 999'), findsOneWidget);
    expect(find.text('回合 970'), findsNothing);

    // Reaching the top expands a page without moving its existing anchor.
    scroll.jumpTo(0);
    await tester.pump();
    final anchorY = tester.getTopLeft(find.text('回合 970')).dy;
    await tester.pumpAndSettle();
    expect(chat.turns, hasLength(60));
    expect(tester.getTopLeft(find.text('回合 970')).dy, closeTo(anchorY, 1));
    expect(scroll.offset, closeTo(0, 1));
    expect(scroll.position.minScrollExtent, lessThan(0));

    // Read through every page. Widget creation stays bounded by the viewport,
    // even though all one thousand messages have become accessible.
    while (chat.hasEarlierHistory) {
      scroll.jumpTo(scroll.position.minScrollExtent + 1);
      await tester.pumpAndSettle();
    }
    expect(chat.turns, hasLength(1000));
    expect(chat.turns.first.id, 'turn-0');
    expect(chat.turns.map((turn) => turn.id).toSet(), hasLength(1000));
    scroll.jumpTo(scroll.position.minScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('已到对话开头'), findsOneWidget);
    expect(find.text('回合 0'), findsOneWidget);
    expect(find.text('回合 999'), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(
        find
            .byWidgetPredicate((widget) =>
                widget is Text && (widget.data ?? '').startsWith('回合 '))
            .evaluate()
            .length,
        lessThan(20));
    expect(port.reads, 1, reason: 'expanding does not re-fetch the whole log');
    await tester.pumpWidget(const SizedBox.shrink());
    close();
  });

  testWidgets('new turns do not dislodge someone reading earlier messages',
      (tester) async {
    final chat = NipaChat(port: _HistoryPort(65), data: _ChatData());
    final logins = LoginRequests();
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      chat.dispose();
      logins.dispose();
    }

    addTearDown(close);
    await tester.runAsync(() => chat.select('long'));
    Widget view() => MaterialApp(
            home: Scaffold(
                body: ListenableBuilder(
          listenable: chat,
          builder: (context, _) => ChatTranscript(
              chat: chat, callbacks: const CardCallbacks(), logins: logins),
        )));
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    final scroll = ChatTranscript.debugController!;
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('回合 35')).dy;
    final offset = scroll.offset;
    chat.turns = [
      ...chat.turns,
      (ChatTurn(id: 'new')..status = 'completed')
        ..parts.add(ReplyPart('new-answer', '新回复'))
    ];
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(offset, 1));
    expect(tester.getTopLeft(find.text('回合 35')).dy, closeTo(before, 1));
    await tester.tap(find.bySemanticsLabel('回到最新').first);
    await tester.pumpAndSettle();
    expect(find.text('新回复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    close();
  });

  test('switching sessions discards an older page still being parsed',
      () async {
    final port = _HistoryPort(90);
    final chat = NipaChat(port: port, data: _ChatData());
    addTearDown(chat.dispose);
    await chat.select('long');
    final pending = chat.loadEarlierHistory();
    await chat.select('short');
    await pending;
    expect(chat.thread, 'short');
    expect(chat.turns, hasLength(2));
    expect(chat.turns.first.id, 'turn-0');
    expect(chat.hasEarlierHistory, false);
    expect(chat.loadingEarlier, false);
  });

  test('a repeated interrupted input is hidden across a page boundary',
      () async {
    final port = _HistoryPort(31);
    port.history[0] = {
      'id': 'retry',
      'status': 'interrupted',
      'items': [
        {
          'id': 'input-retry',
          'type': 'userMessage',
          'content': [
            {'type': 'text', 'text': '问题 1'}
          ]
        }
      ],
    };
    final chat = NipaChat(port: port, data: _ChatData());
    addTearDown(chat.dispose);
    await chat.select('long');
    await chat.loadEarlierHistory();
    expect(chat.turns, hasLength(30));
    expect(chat.turns.any((turn) => turn.id == 'retry'), false);
    expect(chat.hasEarlierHistory, false);
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
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, 300));
    await tester.pumpAndSettle();
    final reading = scroll.offset;
    turn.parts.add(ReplyPart('more', List.filled(20, '新增内容').join('\n\n')));
    await tester.pumpWidget(view());
    await tester.pump();
    expect(scroll.offset, closeTo(reading, 1));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(CustomScrollView).first));
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

class _OfflinePort implements ChatPort {
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

final class _HistoryPort extends _OfflinePort {
  _HistoryPort(int count)
      : history = [
          for (var i = 0; i < count; i++)
            {
              'id': 'turn-$i',
              'status': 'completed',
              'items': [
                {
                  'id': 'input-$i',
                  'type': 'userMessage',
                  'content': [
                    {
                      'type': 'text',
                      'text': i % 3 == 0
                          ? '问题 $i\n${List.filled(i % 5 + 1, '不同高度的内容').join('\n')}'
                          : '问题 $i'
                    }
                  ]
                },
                {'id': 'reply-$i', 'type': 'agentMessage', 'text': '回合 $i'},
              ],
            },
        ];
  final List<Map<String, Object?>> history;
  int reads = 0;
  @override
  Future<ChatEvent> readThread(String threadId) async {
    reads++;
    return {'turns': threadId == 'short' ? history.sublist(0, 2) : history};
  }
}

final class _ChatData implements NextUiData {
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      const [];
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
