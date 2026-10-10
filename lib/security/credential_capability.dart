import 'package:nipa_harness/nipa_harness.dart';
import 'credential_store.dart';

final class CredentialCapability implements Capability {
  CredentialCapability(this.store);
  final CredentialStore store;
  @override
  List<Action> get actions => [_Status(store)];
}

final class _Status extends Action<NoInput, _StatusResult> {
  _Status(this.store);
  final CredentialStore store;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'credentials.status',
        title: '凭据保险库状态',
        description: '检查系统保险库、迁移失败与重新登录提示；不返回秘密。',
        effect: Effect.read,
        input: ObjectSchema({}),
        output: ObjectSchema(
            {'backend': StringSchema(), 'notices': ArraySchema(StringSchema())},
            required: ['backend', 'notices']),
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
        'notices': store.notices.value
      };
}
