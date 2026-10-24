import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';

import '../media/identity_store.dart' show newMediaId;
import '../tasks/user_consent.dart';
import 'capability.dart';
import 'registry.dart';

/// A setting whose new value can send a key or traffic to another host. When
/// an Agent sets one to anything but its safe value (empty text, or off), the
/// person at NipaPlay is asked first. The settings page and Classic are the
/// person themself and are not asked.
final class ConsentRule {
  const ConsentRule(this.title, this.words);

  /// Names the setting in the question's title.
  final String title;

  /// What the new value does, ahead of the value.
  final String words;
  bool safe(Object? value) => value == '' || value == false;

  /// The words end in a colon when the new value is shown under them.
  bool get listed => words.endsWith('：');
}

const settingConsentRules = <String, ConsentRule>{
  'danmaku.spoilerAiApiUrl': ConsentRule('防剧透 AI 地址', '防剧透 AI 的密钥和弹幕将发往这个地址：'),
  'network.httpProxy': ConsentRule('HTTP 代理', '应用和播放器的网络流量将经过这个代理：'),
  'plugins.githubProxyUrl': ConsentRule('GitHub 代理', '插件列表和插件文件将经过这个地址下载：'),
  'network.bangumiServerUrl':
      ConsentRule('Bangumi 服务器', 'Bangumi 的登录令牌和请求将发往这个地址：'),
  'network.allowInvalidCertificates':
      ConsentRule('自签名证书', '所有 HTTPS 连接都将接受无效或自签名的证书，通信可能被窃听或篡改。'),
};

/// A value as the person reads it: no credentials, query or fragment of an
/// address, and nothing the redactor knows as a secret.
String settingWords(Object? value) {
  if (value is bool) return value ? '开' : '关';
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty) return '（空）';
  final uri = Uri.tryParse(text);
  final shown = uri != null && uri.hasScheme && uri.host.isNotEmpty
      ? '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}'
      : SecretRedactor.text(text);
  return shown.length > 120 ? '${shown.substring(0, 120)}…' : shown;
}

/// The title and question for [changes] (each `key`, `from`, `to`, already in
/// words), [others] more settings in the same call being set with them.
(String, String) settingConsentWords(List<JsonMap> changes, {int others = 0}) {
  final lines = StringBuffer();
  for (final change in changes) {
    final rule = settingConsentRules[change['key']]!;
    lines.writeln(rule.words);
    if (rule.listed) {
      lines.writeln('· ${change['to']}');
      lines.writeln('原来：${change['from']}');
    }
  }
  if (others > 0) lines.writeln('另外 $others 项设置一并修改。');
  final title = changes.length == 1
      ? '更改${settingConsentRules[changes.single['key']]!.title}'
      : '更改设置';
  return (title, lines.toString().trimRight());
}

/// Only this application-owned executor applies a change that needs the
/// person's yes. No Action can supply or persist an approval on their behalf.
final class SettingConsent implements JobExecutor {
  SettingConsent(this.registry,
      {Future<bool> Function(String, String, Future<void>)? prompt})
      : prompt = prompt ??
            ((title, message, stopped) =>
                showUserConsent(title, message, '更改', stopped: stopped));
  final SettingsRegistry registry;
  final Future<bool> Function(String, String, Future<void>) prompt;
  late final Iterable<Capability> _unprotected;

  /// The conversation behind a request, so the answer comes back to it.
  Future<JsonMap?> Function(Invocation)? returnTarget;
  late TaskEngine engine;
  late final Harness _execution = Harness(_unprotected);
  final _previews = <String, JsonMap>{};
  @override
  String get type => 'setting_consent';

  List<Capability> protect(List<Capability> capabilities) {
    _unprotected = capabilities;
    return [
      _SettingConsentCapability([_RequestSettingChange(this)]),
      for (final capability in capabilities)
        if (capability is SettingsCapability)
          _SettingConsentCapability(_guardSettings(capability))
        else
          capability
    ];
  }

  List<Action> _guardSettings(SettingsCapability capability) {
    final actions = <Action>[];
    for (final action in capability.actions) {
      if (action.spec.id == 'settings.set') {
        actions.add(_GuardedSet(this, action.spec));
      } else {
        actions.add(action);
      }
    }
    return actions;
  }

  /// What in this call needs the person's yes: null when nothing does (an
  /// invalid value there fails by itself, as in any batch). A call with such a
  /// change is not applied until they answer; an invalid value of one of the
  /// settings that need the question, in the same call, rejects the whole call.
  Future<JsonMap?> gate(JsonMap input, Invocation invocation) async {
    if (invocation.origin == 'gui') return null;
    final raw = input['changes'];
    final changes = raw is List
        ? [
            for (final change in raw)
              if (change is Map) Map<String, Object?>.from(change)
          ]
        : [input];
    final needs = <JsonMap>[];
    var others = 0;
    final violations = <SchemaViolation>[];
    for (var i = 0; i < changes.length; i++) {
      final change = changes[i];
      final key = change['key'];
      final rule = key is String ? settingConsentRules[key] : null;
      if (rule == null || !change.containsKey('value')) {
        others++;
        continue;
      }
      final value = change['value'];
      final entry = registry.lookup(key as String);
      if (rule.safe(value) || entry == null) {
        others++;
        continue;
      }
      try {
        registry.check(key, value);
      } on Failure catch (failure) {
        violations.addAll([
          for (final v in failure.violations)
            SchemaViolation(
                raw is List ? '/changes/$i${v.path}' : v.path, v.message),
          if (failure.violations.isEmpty)
            SchemaViolation(
                raw is List ? '/changes/$i/value' : '/value', failure.message),
        ]);
        continue;
      }
      final current = await entry.read();
      if (jsonEncode(current) == jsonEncode(value)) {
        others++;
        continue;
      }
      needs.add({
        'key': key,
        'from': settingWords(current),
        'to': settingWords(value),
      });
    }
    if (needs.isEmpty) return null;
    if (violations.isNotEmpty) {
      throw Failure(FailureCode.invalidInput, 'Invalid setting value.',
          violations: violations);
    }
    return {'changes': needs, 'others': others};
  }

  @override
  Future<void> execute(JobContext context) => _run(context);
  @override
  Future<void> recover(JobContext context) async {
    final applying = context.job.phase == 'applying';
    await context.fail(
        Failure(
            FailureCode.conflict,
            applying
                ? 'The application stopped while applying an approved change; read the settings to see which took effect.'
                : 'The application restarted before the user answered; nothing was changed.'),
        JobReceipt(
            verification: applying
                ? VerificationLevel.unverified
                : VerificationLevel.verified,
            details: {
              'changed': false,
              'reason': applying ? 'interrupted_change' : 'interrupted_question'
            }));
  }

  Future<void> _run(JobContext context) async {
    if (context.job.cancelRequestedAt != null) {
      await context.cancelled(JobReceipt(
          verification: VerificationLevel.verified,
          details: {'changed': false}));
      return;
    }
    await context.waitingUser();
    final input = context.job.input;
    final plan = (input['plan'] as Map).cast<String, Object?>();
    final (title, message) = settingConsentWords([
      for (final c in (plan['changes'] as List))
        (c as Map).cast<String, Object?>()
    ], others: plan['others'] as int? ?? 0);
    final approved = await prompt(title, message, context.stopRequested);
    final current = await context.snapshot();
    if (current.cancelRequestedAt != null) {
      await context.cancelled(JobReceipt(
          verification: VerificationLevel.verified,
          details: {'changed': false}));
      return;
    }
    if (!approved) {
      await context.fail(
          const Failure(FailureCode.conflict, '用户没有同意修改设置'),
          JobReceipt(
              verification: VerificationLevel.verified,
              details: {'changed': false, 'reason': 'user_declined'}));
      return;
    }
    await context.running(phase: 'applying');
    final outcome = await _execution.invokeJson(
        'settings.set',
        (input['arguments'] as Map).cast<String, Object?>(),
        Invocation(
            origin: input['origin'] as String,
            id: input['invocationId'] as String));
    switch (outcome) {
      case Completed(:final value):
        final result = value.toJson();
        final failures = (result['results'] as List?)
                ?.where((item) => (item as Map)['status'] == 'failed')
                .toList() ??
            [];
        if (failures.isNotEmpty) {
          await context.fail(
              const Failure(FailureCode.unavailable,
                  'Some requested changes failed; read the per-item results. Changes that succeeded are kept.'),
              JobReceipt(
                  verification: VerificationLevel.acknowledged,
                  details: {'changed': true, 'result': result}));
          return;
        }
        await context.markSideEffectCommitted();
        await context.succeed(
            JobReceipt(
                verification: VerificationLevel.verified,
                details: {'changed': true, 'result': result}),
            phase: 'applied');
      case Failed(:final failure):
        await context.fail(
            failure,
            JobReceipt(
                verification: VerificationLevel.verified,
                details: {'changed': false, 'reason': 'change_failed'}));
      case NeedsDecision():
        throw StateError(
            'A settings change cannot delegate approval to an Agent.');
    }
  }
}

final class _SettingConsentCapability implements Capability {
  _SettingConsentCapability(this.actions);
  @override
  final List<Action> actions;
}

final class _Json implements JsonEncodable {
  _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _GuardedSet extends Action<_Json, _Json> {
  _GuardedSet(this.consent, this.original);
  final SettingConsent consent;
  final ActionSpec original;
  @override
  ActionSpec get spec => ActionSpec(
      id: original.id,
      title: original.title,
      effect: original.effect,
      input: original.input,
      description: '${original.description} '
          'These settings can send a key or traffic to another host: danmaku.spoilerAiApiUrl, network.httpProxy, plugins.githubProxyUrl, network.bangumiServerUrl, network.allowInvalidCertificates. '
          'Setting one of them to a value other than empty text (or off) returns NeedsDecision and changes nothing, including the other changes in the same call; an invalid value for one of them in the same call rejects the whole call. '
          'Its option settings.set.request creates a setting_consent task, asks the user in NipaPlay, and only after the user agrees applies the original call with the original reason and expectedRevision. '
          'waiting_user means nothing has changed; task.wait and followup.register can observe it. A refusal fails with 用户没有同意修改设置. When the user answers (change or cancel, or closing the window) the outcome returns to the requesting conversation. '
          'Setting them to empty text or off, settings.reset, and the settings page need no question. No confirmation argument bypasses this.',
      output: original.output);
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final plan = await consent.gate(input.value, invocation);
    if (plan == null) {
      final outcome = await consent._execution
          .invokeJson(original.id, input.value, invocation);
      return switch (outcome) {
        Completed(:final value) => Completed(_Json(value.toJson())),
        Failed(:final failure) => Failed(failure),
        NeedsDecision(:final decision) => NeedsDecision(decision),
      };
    }
    final id = newMediaId('settings-preview');
    consent._previews[id] = {
      'arguments': input.value,
      'plan': plan,
      'origin': invocation.origin,
      'invocationId': invocation.id,
    };
    if (consent._previews.length > 64) {
      consent._previews.remove(consent._previews.keys.first);
    }
    return NeedsDecision(Decision(
        prompt: '这次修改会让密钥或网络流量去往别处，需要用户同意：${jsonEncode(plan)}',
        options: [
          DecisionOption(
              label: '请求用户确认',
              call: ActionCall('settings.set.request', {'previewId': id}))
        ]));
  }
}

final class _RequestSettingChange extends Action<_Json, _Json> {
  _RequestSettingChange(this.consent);
  final SettingConsent consent;
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'settings.set.request',
      title: '请求用户确认设置修改',
      description:
          'Use the option returned by settings.set. The process-local preview is single-use and caller-bound. '
          'Creates a persistent setting_consent task and asks the user in NipaPlay; the change is applied only after the user agrees. '
          'When the user answers (Change, Cancel or closing the window) the outcome returns to the requesting conversation, queued while a turn is active; a followup you registered on the task jobId replaces that return. The facts carry state and whether it changed. '
          'This action cannot approve the change. Restart before requesting requires calling settings.set again.',
      effect: Effect.write,
      input: ObjectSchema({'previewId': StringSchema(minLength: 1)},
          required: ['previewId']),
      output: ObjectSchema(
          {'job': ObjectSchema({}, additionalProperties: true)},
          required: ['job']));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final id = input.value['previewId'] as String;
    final plan = consent._previews[id];
    if (plan == null || plan['origin'] != invocation.origin) {
      throw const Failure(FailureCode.conflict,
          'The settings preview is missing or belongs to another caller.');
    }
    consent._previews.remove(id);
    final target = await consent.returnTarget?.call(invocation);
    final job =
        await consent.engine.submit(type: consent.type, title: '修改设置', input: {
      'arguments': plan['arguments'],
      'plan': plan['plan'],
      'keys': [
        for (final c in (plan['plan'] as Map)['changes'] as List)
          (c as Map)['key']
      ],
      'origin': plan['origin'],
      'invocationId': plan['invocationId'],
      if (target != null) 'returnTo': target,
    });
    return Completed(_Json({'job': job.toJson()}));
  }
}
