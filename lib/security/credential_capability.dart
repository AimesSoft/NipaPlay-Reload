import 'package:nipa_harness/nipa_harness.dart';
import 'credential_store.dart';
import 'credential_vault.dart';

final class CredentialCapability implements Capability {
  CredentialCapability(this.store);
  final CredentialStore store;
  @override
  List<Action> get actions => [_Status(store), _Retry(store)];
}

final class _Status extends Action<NoInput, _StatusResult> {
  _Status(this.store);
  final CredentialStore store;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'credentials.status',
        title: '凭据保险库状态',
        description: '读取本次运行已观察到的凭据失败与授权拒绝；不访问保险库，不返回秘密。',
        effect: Effect.read,
        input: ObjectSchema({}),
        output: ObjectSchema({
          'backend': StringSchema(),
          'notices': ArraySchema(StringSchema()),
          'failures': ArraySchema(ObjectSchema({
            'reference': ObjectSchema(
                {'namespace': StringSchema(), 'key': StringSchema()},
                required: ['namespace', 'key']),
            'reason': StringSchema(),
            'automaticRetryBlocked': BooleanSchema(),
          }, required: [
            'reference',
            'reason',
            'automaticRetryBlocked'
          ]))
        }, required: [
          'backend',
          'notices',
          'failures'
        ]),
      );
  @override
  NoInput decodeInput(JsonMap json) => const NoInput();
  @override
  Future<Outcome<_StatusResult>> run(
          NoInput input, Invocation invocation) async =>
      Completed(_StatusResult(store));
}

final class _StatusResult implements JsonEncodable {
  _StatusResult(this.store);
  final CredentialStore store;
  @override
  JsonMap toJson() => {
        'backend': store.desktop ? 'system' : 'legacy',
        'notices': store.notices.value,
        'failures': [
          for (final entry in store.failures.entries)
            {
              'reference': entry.key.toJson(),
              'reason': entry.value,
              'automaticRetryBlocked':
                  store.vault.blocked.containsKey(entry.key),
            }
        ],
      };
}

final class _Retry extends Action<CredentialRef, _RetryResult> {
  _Retry(this.store);
  final CredentialStore store;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'credentials.retry',
        title: '主动重试指定凭据',
        description: '用户要求重试时，解除指定条目的本次运行授权拒绝并读取一次；可能显示系统授权窗口，仅返回存在状态。',
        effect: Effect.write,
        input: ObjectSchema(
            {'namespace': StringSchema(), 'key': StringSchema()},
            required: ['namespace', 'key']),
        output: ObjectSchema({
          'reference': ObjectSchema(
              {'namespace': StringSchema(), 'key': StringSchema()},
              required: ['namespace', 'key']),
          'available': BooleanSchema()
        }, required: [
          'reference',
          'available'
        ]),
      );
  @override
  CredentialRef decodeInput(JsonMap json) => CredentialRef.fromJson(json);
  @override
  Future<Outcome<_RetryResult>> run(
      CredentialRef input, Invocation invocation) async {
    try {
      return Completed(_RetryResult(input, await store.retry(input)));
    } catch (_) {
      throw Failure(FailureCode.unavailable,
          '$input: ${store.failures[input]}; see credentials.status.');
    }
  }
}

final class _RetryResult implements JsonEncodable {
  _RetryResult(this.ref, this.available);
  final CredentialRef ref;
  final bool available;
  @override
  JsonMap toJson() => {'reference': ref.toJson(), 'available': available};
}
