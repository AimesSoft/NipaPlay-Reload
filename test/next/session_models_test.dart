@TestOn('!windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/chat/model_launch.dart';
import 'package:nipaplay/next/ui_data/host_settings.dart';

void main() {
  Future<ChatHost Function()> fixture(
    Map<String, Object?> config, {
    bool chatgpt = false,
    bool noCatalog = false,
  }) async {
    final root = await Directory.systemTemp.createTemp('session-models-');
    addTearDown(() => root.delete(recursive: true));
    final node = await Process.run('/usr/bin/env', ['node', '--version']);
    expect(node.exitCode, 0,
        reason: 'The app-server fixture requires Node.js.');
    final script = File('test/next/fixtures/model_app_server.mjs').absolute;
    final executable = File('${root.path}/codex');
    await executable
        .writeAsString('#!/bin/sh\nexec node ${jsonEncode(script.path)}\n');
    expect((await Process.run('chmod', ['700', executable.path])).exitCode, 0);
    final endpoint = AgentEndpoint(
      harness: Harness([]),
      seed: {},
      appVersion: 'test',
      port: 0,
      credentialFile: File('${root.path}/endpoint.json'),
      seedRepository: Directory('${root.path}/seed'),
    );
    addTearDown(endpoint.stop);
    return () {
      final host = ChatHost(
        endpoint: endpoint,
        repository: root,
        modelLaunch: () async => ModelLaunch(
          revision: 0,
          home: root,
          executable: executable.path,
          environment: {
            'NIPA_TEST_MODEL_CONFIG': jsonEncode(config),
            if (chatgpt) 'NIPA_TEST_ACCOUNT': 'chatgpt',
            if (noCatalog) 'NIPA_TEST_NO_CATALOG': '1',
          },
        ),
      );
      addTearDown(host.close);
      return host;
    };
  }

  const baseline = {
    'model': 'configured-model',
    'model_reasoning_effort': 'low'
  };
  const persisted = UiModelChoice(
      source: UiModelSource.codex,
      catalog: UiAgentRuntimeKind.codex,
      model: 'saved-model',
      reasoning: 'medium');
  const once = UiModelChoice(
      source: UiModelSource.codex,
      catalog: UiAgentRuntimeKind.codex,
      model: 'once-model',
      reasoning: 'high');

  Future<String> start(ChatHost host) async =>
      (await host.startThread())['thread']['id'] as String;

  Future<void> assertWire(
      ChatHost host, String id, String model, String effort) async {
    final wire = (await host.startThreadTurn(id, 'fixture'))['wire'] as Map;
    expect(wire, containsPair('model', model));
    expect(wire, containsPair('effort', effort));
  }

  test('saved choice survives a new host and resume; new thread uses defaults',
      () async {
    final create = await fixture(baseline);
    final writer = create();
    await writer.start();
    final original = await start(writer);
    await writer.selectSessionModel(persisted);
    await writer.close();

    final reader = create();
    await reader.start();
    await reader.resumeThread(original);
    expect((await reader.sessionModel())?.model, 'saved-model');
    await assertWire(reader, original, 'saved-model', 'medium');

    final fresh = await start(reader);
    expect(fresh, isNot(original));
    expect(await reader.sessionModel(), isNull);
    await assertWire(reader, fresh, 'configured-model', 'low');
  });

  for (final hasSavedChoice in [false, true]) {
    test(
        'one turn explicitly restores model and effort (saved=$hasSavedChoice)',
        () async {
      final create = await fixture(baseline);
      final host = create();
      await host.start();
      final id = await start(host);
      if (hasSavedChoice) await host.selectSessionModel(persisted);
      await host.selectSessionModel(once, once: true);
      await assertWire(host, id, 'once-model', 'high');
      await assertWire(
          host,
          id,
          hasSavedChoice ? 'saved-model' : 'configured-model',
          hasSavedChoice ? 'medium' : 'low');
    });
  }

  for (final config in <Map<String, Object?>>[
    {'model_provider': 'custom'},
    {...baseline, 'model_provider': 'nipaplay'},
    {...baseline, 'openai_base_url': 'https://proxy.example/v1'},
    {...baseline, 'chatgpt_base_url': 'https://proxy.example/backend-api'},
  ]) {
    test('custom route never asks for Codex catalog: ${config.keys.join(', ')}',
        () async {
      final create = await fixture(config, chatgpt: true, noCatalog: true);
      final host = create();
      await host.start();
      expect(await host.runtimeModels(), isNull);
    });
  }

  for (final chatgpt in [false, true]) {
    test('official route labels its catalog (ChatGPT account=$chatgpt)',
        () async {
      final create = await fixture(baseline, chatgpt: chatgpt);
      final host = create();
      await host.start();
      final choice = (await host.runtimeModels())!.single;
      expect(choice.model, 'catalog-model');
      expect(
          choice.candidateOrigin,
          chatgpt
              ? UiModelCandidateOrigin.chatgptAccount
              : UiModelCandidateOrigin.openai);
    });
  }
}
