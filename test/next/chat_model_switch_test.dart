import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Action, Invocation;
import 'package:nipa_harness/nipa_harness.dart' as harness_api show Invocation;
import 'package:nipaplay/next/settings/model_capability.dart';
import 'package:nipaplay/next/settings/responses_probe.dart';
import 'package:nipaplay/next/ui/chat/model_switch.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/conversation/chat_turn.dart';
import 'package:nipaplay/next/ui/conversation/nipa_chat.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui_data/host_settings.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('slash commands never reach the model, even on failure', () async {
    final port = _CommandPort();
    final chat = NipaChat(port: port, data: _EmptyData());
    addTearDown(chat.dispose);
    await chat.say('/ok');
    await chat.say('/failing');
    await chat.say('/throws');
    expect(
        port.commands, [('t1', '/ok'), ('t1', '/failing'), ('t1', '/throws')]);
    expect(port.model, isEmpty);
    expect(chat.turns.map((turn) => turn.status),
        ['completed', 'failed', 'failed']);
    expect((chat.turns[0].parts.last as ReplyPart).text, 'command output');
    expect((chat.turns[1].parts.last as ReplyPart).text, 'command failed');
    expect((chat.turns[2].parts.last as NoticePart).text, '无法执行这条命令。');
    await chat.say('ordinary input');
    expect(port.model, ['ordinary input']);
    // A path is never a command; a line the harness does not know goes to Nipa.
    await chat.say('/Users/me/a.mkv 这集怎么样');
    await chat.say('/unknown 你好');
    expect(port.commands.last, ('t1', '/unknown 你好'));
    expect(port.commands, hasLength(4));
    expect(port.model,
        ['ordinary input', '/Users/me/a.mkv 这集怎么样', '/unknown 你好']);
  });

  test('model actions read and write through host settings without endpoints',
      () async {
    final host = FakeHostSettings()..runtime = UiAgentRuntimeKind.dsh;
    final harness = Harness([ChatModelCapability(host)]);
    Future<JsonMap> invoke(String operation, [JsonMap input = const {}]) async {
      final result = await harness.invokeJson('chat.model.$operation', input,
          harness_api.Invocation(origin: 'test'));
      expect(result, isA<Completed<JsonEncodable>>());
      return (result as Completed<JsonEncodable>).value.toJson() as JsonMap;
    }

    final status = await invoke('status');
    expect(status['inUse'], 'deepseek-flash');
    expect(status['recent'], isNotEmpty);
    final candidates = await invoke('candidates');
    expect(candidates['status'], 'succeeded');
    final choice = (candidates['choices'] as List)
        .cast<JsonMap>()
        .singleWhere((choice) => choice['model'] == 'deepseek-pro');
    expect(choice.containsKey('baseUrl'), isFalse);
    expect(choice.containsKey('apiKey'), isFalse);
    expect(choice['candidateOrigin'], 'provider');
    final saved = await invoke(
        'set', {'choiceId': choice['choiceId'], 'reasoning': 'off'});
    expect(saved['appliesAt'], 'nextTurn');
    expect(host.saved.last.model, 'deepseek-pro');
    expect(host.saved.last.reasoning, '');
  });

  group('listProviderModels', () {
    HttpOverrides? previousOverrides;
    setUp(() {
      previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
    });
    tearDown(() {
      HttpOverrides.global = previousOverrides;
    });

    test('returns sorted deduplicated IDs and normalizes trailing slash',
        () async {
      String? seenPath;
      String? seenAuth;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        seenPath = request.uri.path;
        seenAuth = request.headers.value(HttpHeaders.authorizationHeader);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': [
            {'id': 'deepseek-reasoner'},
            {'id': 'deepseek-chat'},
            {'id': 'deepseek-chat'},
            {'id': ''},
            {'other': 'ignored'},
          ]
        }));
        await request.response.close();
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final models = await listProviderModels(
        client,
        Uri.parse('http://127.0.0.1:${server.port}/v1/'),
        'sk-test-key',
      );
      expect(seenPath, '/v1/models');
      expect(seenAuth, 'Bearer sk-test-key');
      expect(models, ['deepseek-chat', 'deepseek-reasoner']);
    });

    test('throws HttpException when provider returns non-200', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = 404;
        await request.response.close();
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      await expectLater(
        listProviderModels(
          client,
          Uri.parse('http://127.0.0.1:${server.port}/v1'),
          'sk-test-key',
        ),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('ModelMenu widget & helpers', () {
    test('modelLabel and choice helpers preserve provider fields', () {
      const setup = UiModelSetup(
        source: UiModelSource.nipaplay,
        runtime: UiAgentRuntimeKind.dsh,
        provider: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/',
        model: 'deepseek-flash',
        inUse: 'deepseek-flash',
        api: UiModelApi.chat,
        reasoning: 'medium',
        hasKey: true,
      );
      expect(modelLabel(setup), 'deepseek-flash');
      final next = currentChoice(setup, model: 'deepseek-pro');
      expect(next.model, 'deepseek-pro');
      expect(next.api, UiModelApi.chat);
      expect(next.reasoning, 'medium');

      const codex = UiModelSetup(source: UiModelSource.codex);
      expect(modelLabel(codex), 'Codex 配置');
      // Just switched: the running conversation still uses the old one
      // until its next turn; the pill names the choice.
      const switched = UiModelSetup(
          source: UiModelSource.nipaplay,
          model: 'deepseek-pro',
          inUse: 'deepseek-flash');
      expect(modelLabel(switched), 'deepseek-pro');
    });

    testWidgets(
        'ModelMenu switches recent/listed models and DSH reasoning effort',
        (tester) async {
      final host = FakeHostSettings()
        ..runtime = UiAgentRuntimeKind.dsh
        ..dshReasoning = 'low';
      final chat = NipaChat(port: _IdleChatPort(), data: _EmptyData());
      addTearDown(chat.dispose);
      var closed = 0;
      var openedSettings = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ModelMenu(
            host: host,
            chat: chat,
            onSettings: () => openedSettings++,
            onClose: () => closed++,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // Each service lists its own models; the one in use comes first.
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text('OpenRouter'), findsOneWidget);
      expect(
          find.byKey(const Key('chat.model.service.DeepSeek.deepseek-flash')),
          findsOneWidget);
      expect(
          find.byKey(const Key('chat.model.service.DeepSeek.deepseek-pro')),
          findsOneWidget);
      expect(
          find.byKey(const Key(
              'chat.model.service.OpenRouter.google/gemini-4-pro')),
          findsOneWidget);

      // Tapping reasoning '高' updates model without closing the sheet.
      await tester.tap(find.text('高'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(closed, 0);
      expect(host.saved.last.reasoning, 'high');

      // Tapping a listed model switches to it and closes the sheet.
      await tester.tap(
          find.byKey(const Key('chat.model.service.DeepSeek.deepseek-pro')));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(host.saved.last.model, 'deepseek-pro');
      expect(host.saved.last.reasoning, 'high');
      expect(closed, 1);

      // Tapping settings link calls onSettings.
      await tester.tap(find.text('管理模型…'));
      await tester.pump();
      expect(openedSettings, 1);
    });
  });
}

final class _IdleChatPort implements ChatPort {
  @override
  bool get available => true;
  @override
  bool get busy => false;
  @override
  bool busyOn(String threadId) => false;
  @override
  Stream<ChatEvent> get display => const Stream.empty();
  @override
  Stream<ChatEvent> get questions => const Stream.empty();
  @override
  Future<String?> unavailableReason() async => null;
  @override
  Future<String?> mainThread() async => null;
  @override
  Future<String?> newThread() async => 't1';
  @override
  Future<ChatEvent> listThreads({String? cursor}) async =>
      const {'data': <Object?>[], 'nextCursor': null};
  @override
  Future<ChatEvent> readThread(String threadId) async => const {};
  @override
  Future<String?> switchThread(String threadId) async => threadId;
  @override
  Future<ChatEvent?> startTurn(String threadId, String text) async => null;
  @override
  Future<void> steer(String text, {String? threadId}) async {}
  @override
  Future<void> interrupt({String? threadId}) async {}
  @override
  Future<void> answer(
      Object requestId, Map<String, List<String>> answers) async {}
  @override
  void dispose() {}
}

final class _CommandPort extends _IdleChatPort implements SlashCommandPort {
  final commands = <(String, String)>[];
  final model = <String>[];
  @override
  bool get hasSlashCommands => true;
  @override
  Future<String?> mainThread() async => 't1';
  @override
  Future<ChatEvent?> startTurn(String threadId, String text) async {
    model.add(text);
    return const {
      'turn': {'id': 'turn-fixture', 'status': 'inProgress'}
    };
  }

  @override
  Future<ChatEvent> executeSlashCommand(String threadId, String line) async {
    commands.add((threadId, line));
    return switch (line) {
      '/ok' => {'kind': 'success', 'text': 'command output'},
      '/failing' => {'kind': 'error', 'text': 'command failed'},
      _ when line.startsWith('/unknown') => {'kind': 'unknown', 'text': ''},
      _ => throw StateError('fixture command failed'),
    };
  }
}

final class _EmptyData implements NextUiData {
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Stream<List<UiTask>> tasks() => const Stream.empty();
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
