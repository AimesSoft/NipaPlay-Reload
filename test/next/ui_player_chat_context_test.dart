import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/conversation/nipa_chat.dart';
import 'package:nipaplay/next/ui/dev/fake_world.dart';
import 'package:nipaplay/next/ui/player/player_layer.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui/shell/top_bar.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import 'player_test_support.dart';

/// What is said over a video goes to Nipa with what plays and where, read
/// the moment it is said: the work and episode as the library knows them
/// (a film without a number), or the file's name; the position, the length,
/// a pause. Shown, the words are yours alone; once the video is gone a
/// faint line says what was playing. Said anywhere else, nothing goes along.
void main() {
  const dragon = UiNowPlaying(
      workId: 'w-dragon',
      work: '寻龙记',
      episodeId: 'e-dragon-3',
      episode: '第 3 集');
  const mark = '[NipaPlay 界面]';

  group('the words', () {
    test('a missing model leaves a system explanation in the turn', () async {
      final port = _UnavailablePort('还没有设置 Nipa 的模型。请打开“设置 Nipa”填写地址和模型名。');
      final chat = NipaChat(port: port, data: _ChatData());
      addTearDown(chat.dispose);

      await chat.say('你好');

      final turn = chat.turns.single;
      final notice = turn.parts.whereType<NoticePart>().single;
      expect(turn.status, 'failed');
      expect(notice.text, contains('还没有设置 Nipa 的模型'));
      expect(notice.text, contains('设置 Nipa'));
      expect(turn.answer, isNull);
      expect(turn.lastWords, isEmpty);
      expect(turn.folded(notice), false);
      expect(turn.foldable, false);
      expect(chat.trouble, isNull, reason: 'the notice is not repeated below');
    });

    test('setup problems point to the right part of 设置 Nipa', () {
      expect(chatUnavailableReason('请先填写地址和模型名'), contains('填写地址和模型名'));
      expect(chatUnavailableReason('请先填写密钥'), contains('填写密钥'));
      expect(chatUnavailableReason('还没有运行环境'), contains('安装运行环境'));
      expect(chatUnavailableReason('正在准备运行环境'), contains('请稍后再试'));
      expect(chatUnavailableReason('模型服务已断开'), contains('模型服务没有启动'));
      expect(chatUnavailableReason(null), contains('检查模型和运行环境'));
    });

    test('an episode, paused: the work, the episode, where, the pause', () {
      final sent = ChatContext.watching(
          '这个人是谁？',
          const Watching(
              path: '/v/寻龙记 03.mkv',
              known: dragon,
              position: Duration(minutes: 10, seconds: 21),
              duration: Duration(minutes: 14, seconds: 48),
              paused: true));
      expect(
          sent,
          '这个人是谁？\n\n$mark 这句话是在播放《寻龙记》第 3 集时说的'
          '（作品 ID：w-dragon；剧集 ID：e-dragon-3；位置 10:21 / 14:48；暂停中）。');
      expect(ChatContext.strip(sent), '这个人是谁？');
      expect(ChatContext.watched(sent), '《寻龙记》');
      expect(ChatContext.aboutTitle(sent), isNull,
          reason: 'not asked from a page');
    });

    test('a film: no episode number; playing, past an hour', () {
      final sent = ChatContext.watching(
          '这是哪一年拍的？',
          const Watching(
              path: '/v/Dune.mkv',
              known: UiNowPlaying(
                  workId: 'w-dune', work: '沙丘', episodeId: 'e-dune'),
              position: Duration(hours: 1, minutes: 2, seconds: 3),
              duration: Duration(hours: 2, minutes: 35)));
      final added = sent.substring(sent.indexOf(mark));
      expect(
          added,
          '$mark 这句话是在播放《沙丘》时说的'
          '（作品 ID：w-dune；剧集 ID：e-dune；位置 1:02:03 / 2:35:00）。');
      expect(added, isNot(contains('第')), reason: 'no episode number');
    });

    test('a file the library does not know: its name and where', () {
      final sent = ChatContext.watching(
          '这是第几集？',
          const Watching(
              path: '/Volumes/影视/[Group] Show - 07 [1080p].mkv',
              position: Duration(minutes: 3)));
      expect(
          sent,
          '这是第几集？\n\n$mark 这句话是在播放「[Group] Show - 07 [1080p].mkv」'
          '时说的（位置 03:00）。');
      expect(ChatContext.watched(sent), '「[Group] Show - 07 [1080p].mkv」');
      expect(ChatContext.strip(sent), '这是第几集？');

      // A source's address: the name, never the key its query carries.
      for (final address in [
        'http://192.168.1.5:8096/Videos/abc/stream.mkv?api_key=SECRET',
        'http://192.168.1.5:8096/Videos/[abc]/stream.mkv?api_key=SECRET',
      ]) {
        final named = ChatContext.watching(
            '', Watching(path: address, position: Duration.zero));
        expect(named, contains('「stream.mkv」'), reason: address);
        expect(named, isNot(contains('SECRET')), reason: address);
      }
    });

    test('with the page it was asked from and the files: each comes back', () {
      const paths = ['/Users/x/Desktop/截屏.png'];
      final sent = ChatContext.watching(
          ChatContext.about(ChatContext.withFiles('这是谁？', paths),
              const UiWork(workId: 'w-dungeon', title: '迷宫饭')),
          const Watching(
              path: '/v/寻龙记 03.mkv',
              known: dragon,
              position: Duration(minutes: 1)));
      expect(ChatContext.strip(sent), '这是谁？');
      expect(ChatContext.files(sent), paths);
      expect(ChatContext.aboutTitle(sent), '迷宫饭');
      expect(ChatContext.watched(sent), '《寻龙记》');
    });

    test('read back from history: your words, and what was playing', () {
      final said = ChatTurn.saidOf({
        'type': 'userMessage',
        'content': [
          {
            'type': 'text',
            'text': ChatContext.watching(
                '再放一遍刚才那段',
                const Watching(
                    path: '/v/寻龙记 03.mkv',
                    known: dragon,
                    position: Duration(minutes: 5)))
          }
        ],
      })!;
      expect(said.text, '再放一遍刚才那段');
      expect(said.watched, '《寻龙记》');
      expect(said.about, isNull);
    });
  });

  test('a stale turn id cannot steal an event after the id moves', () async {
    final port = _ScriptedPort();
    final chat = NipaChat(port: port, data: _ChatData());
    addTearDown(() {
      chat.dispose();
      port.dispose();
    });
    final turn = ChatTurn(id: 'old')..status = 'inProgress';
    chat.thread = 'main';
    chat.turns = [turn];
    // A legacy/direct caller changes the field without the setter.
    turn.id = 'new';
    port.emit({
      'method': 'item/agentMessage/delta',
      'params': {
        'threadId': 'main',
        'turnId': 'new',
        'itemId': 'answer',
        'delta': '新的回答',
      },
    });
    await Future<void>.delayed(Duration.zero);
    port.emit({
      'method': 'item/agentMessage/delta',
      'params': {
        'threadId': 'main',
        'turnId': 'old',
        'itemId': 'stale-answer',
        'delta': '不能投给新回合',
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(chat.turns, hasLength(2));
    expect(turn.id, 'new');
    expect(turn.lastWords, '新的回答');
    expect(chat.turns.last.id, 'old');
    expect(chat.turns.last.lastWords, '不能投给新回合');
  });

  group('over the player', () {
    late _Port port;
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
              (call) async => {'leading': 78.0, 'fullScreen': false});
      port = _Port();
      NextShell.debugServices = (_) => playerTestServices(chat: port);
    });
    tearDown(() {
      NextShell.debugServices = null;
      resetPlayerTestLibrary();
    });

    Future<(PlayerRig, NextShellController)> watch(
        WidgetTester tester, String path,
        {Duration at = const Duration(minutes: 10, seconds: 21),
        Duration length = const Duration(minutes: 14, seconds: 48)}) async {
      final p = await pumpPlayer(tester, status: PlayerStatus.playing);
      p.state
        ..currentVideoPath = path
        ..position = at
        ..duration = length
        ..notify();
      await tester.pump();
      await tester.pump();
      final shell =
          NextShellScope.of(tester.element(find.byType(NextPlayerLayer)));
      shell.toggleChat();
      await tester.pump(const Duration(milliseconds: 600));
      expect(shell.panelOpen.value, isTrue);
      return (p, shell);
    }

    testWidgets(
        'an episode: what plays and where it was when said; shown, your '
        'words alone; nothing goes along once the video is gone',
        (tester) async {
      playerTestLibrary['/v/寻龙记 03.mkv'] = dragon;
      final (p, shell) = await watch(tester, '/v/寻龙记 03.mkv');
      expect(shell.chat.watched, '《寻龙记》');
      p.playback.togglePlay();
      await tester.pump();

      final saying = shell.chat.say('这个人是谁？');
      // The video goes on while the library answers: it was said at 10:21.
      p.state.position = const Duration(minutes: 11);
      await saying;
      await tester.pump();
      expect(
          port.said.single,
          '这个人是谁？\n\n$mark 这句话是在播放《寻龙记》第 3 集时说的'
          '（作品 ID：w-dragon；剧集 ID：e-dragon-3；位置 10:21 / 14:48；暂停中）。');

      expect(find.text('这个人是谁？'), findsOneWidget);
      expect(find.textContaining(mark), findsNothing);
      expect(find.text('看《寻龙记》时'), findsNothing,
          reason: 'it still plays under the conversation');

      // Leaving the video, the conversation becomes the home's: what was
      // said over it says so now.
      p.state
        ..status = PlayerStatus.idle
        ..notify();
      await tester.pump(const Duration(milliseconds: 600));
      // The panel slides away; the home's conversation is the one shown.
      await tester.pump(const Duration(milliseconds: 600));
      expect(shell.homeChatOpen.value, isTrue);
      expect(shell.chat.watched, isNull);
      expect(find.text('看《寻龙记》时'), findsOneWidget);
      expect(find.text('这个人是谁？'), findsOneWidget);

      await shell.chat.say('那下一部呢？');
      await tester.pump();
      expect(port.said.last, '那下一部呢？', reason: 'not over the player');
    });

    testWidgets('a film goes without an episode; playing says no pause',
        (tester) async {
      playerTestLibrary['/v/Dune.mkv'] =
          const UiNowPlaying(workId: 'w-dune', work: '沙丘', episodeId: 'e-dune');
      final (_, shell) = await watch(tester, '/v/Dune.mkv',
          at: const Duration(hours: 1, minutes: 2, seconds: 3),
          length: const Duration(hours: 2, minutes: 35));
      await shell.chat.say('这是哪一年拍的？');
      await tester.pump();
      expect(
          port.said.single,
          '这是哪一年拍的？\n\n$mark 这句话是在播放《沙丘》时说的'
          '（作品 ID：w-dune；剧集 ID：e-dune；位置 1:02:03 / 2:35:00）。');
    });

    testWidgets('a file the library does not know: its name and where',
        (tester) async {
      final (_, shell) =
          await watch(tester, '/Volumes/影视/[Group] Show - 07 [1080p].mkv');
      expect(shell.chat.watched, '「[Group] Show - 07 [1080p].mkv」');
      await shell.chat.say('这是第几集？');
      await tester.pump();
      expect(
          port.said.single,
          '这是第几集？\n\n$mark 这句话是在播放「[Group] Show - 07 [1080p].mkv」'
          '时说的（位置 10:21 / 14:48）。');
      expect(find.text('这是第几集？'), findsOneWidget);
    });

    testWidgets('no video under the conversation: what is said goes alone',
        (tester) async {
      await pumpPlayer(tester);
      final shell = NextShellScope.of(tester.element(find.byType(NextTopBar)));
      await shell.chat.say('今天看什么？');
      await tester.pump();
      expect(port.said.single, '今天看什么？');
    });
  });

  // The scripted world keeps what is said as Codex does: read back, the
  // words are yours and the line says what was playing.
  const samples = '/tmp/nipa-next/visual/tmdb';
  test('the fake world: what was playing reads back from its history',
      () async {
    final world = FakeWorld.load(samples, tasks: false)!;
    final fake = FakeChatPort(world);
    final chat = NipaChat(port: fake, data: world);
    addTearDown(() {
      chat.dispose();
      fake.dispose();
      world.dispose();
    });
    while (chat.thread == null || chat.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    Future<Watching?> read() async => const Watching(
        path: '/v/Frieren - 05.mkv',
        known: UiNowPlaying(
            workId: 'fake:frieren',
            work: '葬送的芙莉莲',
            episodeId: 'fake:frieren:5',
            episode: '第 5 集 死者的幻影'),
        position: Duration(minutes: 12, seconds: 3),
        duration: Duration(minutes: 24),
        paused: true);
    chat.watch(read, named: '《葬送的芙莉莲》');
    await chat.say('刚才那个魔法叫什么？');

    final history = await fake.readThread(chat.thread!);
    final turn = (history['turns'] as List).cast<Map>().last;
    final item = (turn['items'] as List).cast<Map>().first;
    expect(
        (item['content'] as List).single['text'],
        '刚才那个魔法叫什么？\n\n$mark 这句话是在播放《葬送的芙莉莲》第 5 集 死者的幻影时说的'
        '（作品 ID：fake:frieren；剧集 ID：fake:frieren:5；位置 12:03 / 24:00；暂停中）。');
    final said = ChatTurn.fromHistory(turn).parts.whereType<SaidPart>().first;
    expect(said.text, '刚才那个魔法叫什么？');
    expect(said.watched, '《葬送的芙莉莲》');

    chat.unwatch(read);
    expect(chat.watched, isNull);
  }, skip: File('$samples/meta.json').existsSync() ? false : 'no samples');
}

/// A host that is there and keeps what it is told.
class _Port implements ChatPort {
  final said = <String>[];

  @override
  bool get available => true;
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
  Future<String?> mainThread() async => 'main';
  @override
  Future<ChatEvent> listThreads({String? cursor}) async =>
      {'data': const [], 'mainThreadId': 'main'};
  @override
  Future<ChatEvent> readThread(String threadId) async => {'turns': const []};
  @override
  Future<ChatEvent?> startTurn(String threadId, String text) async {
    said.add(text);
    return {
      'turn': {'id': 'turn-${said.length}', 'status': 'inProgress'}
    };
  }

  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ScriptedPort extends _Port {
  final _events = StreamController<ChatEvent>.broadcast();

  @override
  bool get available => false;

  @override
  Stream<ChatEvent> get display => _events.stream;

  void emit(ChatEvent event) => _events.add(event);

  @override
  void dispose() => _events.close();
}

final class _UnavailablePort implements ChatPort {
  _UnavailablePort(this.reason);
  final String reason;

  @override
  bool get available => false;
  @override
  Future<String?> unavailableReason() async => reason;
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
  Future<UiHome> home() async => const UiHome();
  @override
  Stream<List<UiTask>> tasks() => Stream.value(const []);
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<UiWork?> work(String workId) async => null;
  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async =>
      const [];
  @override
  Future<List<UiWork>> library() async => const [];
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      const [];
}
