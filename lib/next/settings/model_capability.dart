import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';

import '../capabilities/classic_action.dart';
import '../ui_data/host_settings.dart';

final class ChatModelCapability implements Capability {
  ChatModelCapability(NextHostSettings host)
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'chat.model.status',
                  title: '读取当前和用过的模型',
                  description:
                      'Read the saved choice and the model reported by the running host separately, plus recent choices and supported reasoning levels. No credentials or endpoints are returned.',
                  effect: Effect.read,
                  input: ObjectSchema({}),
                  output: _facts),
              (_, __) async => _status(await host.model())),
          ClassicAction(
              const ActionSpec(
                  id: 'chat.model.candidates',
                  title: '查询候选模型',
                  description:
                      'List model choices from candidate sources. succeeded with no choices, failed, and unavailable are distinct; failures include a sanitized reason.',
                  effect: Effect.read,
                  input: ObjectSchema({}),
                  output: _facts), (_, __) async {
            final result = await host.providerModels();
            return {
              'status': result.status.name,
              if (result.reason != null) 'reason': result.reason,
              'choices': result.choices.map(_choice).toList(),
            };
          }),
          ClassicAction(
              const ActionSpec(
                  id: 'chat.model.set',
                  title: '切换模型或思考强度',
                  description:
                      'Save a choiceId from chat.model.status or chat.model.candidates, or change only reasoning on the current choice. The saved setting is read at the next turn boundary; active turns are not interrupted. A save is not a provider connectivity check.',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'choiceId': StringSchema(minLength: 1),
                    'reasoning':
                        StringSchema(values: ['off', 'low', 'medium', 'high']),
                  }),
                  output: _facts),
              (input, _) => _set(host, input)),
        ];

  static const _facts = ObjectSchema({}, additionalProperties: true);

  @override
  final List<Action> actions;

  static String? _safe(String? text) =>
      text == null ? null : SecretRedactor.text(text);

  static String _id(UiModelChoice choice) =>
      choice.source == UiModelSource.codex
          ? 'codex'
          : sha256
              .convert(utf8.encode(jsonEncode([
                choice.source.name,
                choice.provider,
                choice.baseUrl,
                choice.api?.name,
                choice.model,
              ])))
              .toString();

  static JsonMap _choice(UiModelChoice choice) => {
        'choiceId': _id(choice),
        'source': choice.source.name,
        'model': _safe(choice.model),
        'provider': _safe(choice.provider),
        'api': choice.api?.name,
        'reasoning': choice.reasoning == '' ? 'off' : choice.reasoning,
      };

  static UiModelChoice _current(UiModelSetup setup) => UiModelChoice(
        source: setup.source,
        model: setup.model,
        provider: setup.provider,
        baseUrl: setup.baseUrl,
        api: setup.api,
        reasoning: setup.reasoning,
        compat: setup.compat,
      );

  static List<UiModelChoice> _recent(UiModelSetup setup) => [
        for (final choice in setup.recent)
          if (_compatible(setup, choice)) choice,
      ];

  static bool _compatible(UiModelSetup setup, UiModelChoice choice) =>
      setup.runtime != UiAgentRuntimeKind.codex ||
      choice.api != UiModelApi.chat;

  static bool _reasoning(UiModelSetup setup, UiModelChoice choice) =>
      setup.runtime == UiAgentRuntimeKind.dsh &&
      choice.source == UiModelSource.nipaplay;

  static JsonMap _status(UiModelSetup setup) => {
        'runtime': setup.runtime.name,
        'configured': _choice(setup.source == UiModelSource.codex
            ? const UiModelChoice(source: UiModelSource.codex)
            : _current(setup)),
        'inUse': _safe(setup.inUse),
        'recent': _recent(setup).map(_choice).toList(),
        'codexChoiceAvailable':
            setup.codexAvailable && setup.runtime == UiAgentRuntimeKind.codex,
        'reasoningLevels': _reasoning(setup, _current(setup))
            ? ['off', 'low', 'medium', 'high']
            : [],
        'appliesAt': 'nextTurn',
      };

  static Future<JsonMap> _set(NextHostSettings host, JsonMap input) async {
    final id = input['choiceId'] as String?;
    final reasoning = input['reasoning'] as String?;
    if (id == null && reasoning == null) {
      throw const Failure(
          FailureCode.invalidInput, 'Supply choiceId or reasoning.');
    }
    if (id == null) {
      await host.setModelReasoning(reasoning == 'off' ? '' : reasoning!);
      return {'saved': true, ..._status(await host.model())};
    }
    final setup = await host.model();
    final current = _current(setup);
    UiModelChoice? choice;
    if (id == _id(current)) {
      choice = current;
    } else if (id == 'codex' &&
        setup.codexAvailable &&
        setup.runtime == UiAgentRuntimeKind.codex) {
      choice = const UiModelChoice(source: UiModelSource.codex);
    } else {
      choice = _recent(setup).where((entry) => _id(entry) == id).firstOrNull;
      if (choice == null) {
        final result = await host.providerModels();
        if (result.status != UiModelQueryStatus.succeeded) {
          throw Failure(FailureCode.unavailable, result.reason ?? '候选查询不可用');
        }
        choice = result.choices.where((entry) => _id(entry) == id).firstOrNull;
      }
    }
    if (choice == null || !_compatible(setup, choice)) {
      throw const Failure(FailureCode.invalidInput,
          'Model choice is not available in this runtime.');
    }
    if (reasoning != null && !_reasoning(setup, choice)) {
      throw const Failure(FailureCode.invalidInput,
          'Reasoning is not adjustable for this runtime and source.');
    }
    await host.setModel(UiModelChoice(
      source: choice.source,
      provider: choice.provider,
      baseUrl: choice.baseUrl,
      model: choice.model,
      api: choice.api,
      reasoning: reasoning == 'off' ? '' : reasoning ?? choice.reasoning ?? '',
      compat: choice.compat ?? const {},
    ));
    return {'saved': true, ..._status(await host.model())};
  }
}
