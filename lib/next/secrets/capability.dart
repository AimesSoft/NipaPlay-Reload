import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../security/credential_vault.dart';
import '../../security/secret_redactor.dart';
import '../capabilities/classic_action.dart';
import '../capabilities/user_authorization.dart';

const _name = StringSchema(minLength: 1, maxLength: 120);

/// Separate namespace: scripts cannot use this API to read other app accounts.
final class SecretsCapability implements Capability {
  SecretsCapability(this.db, this.vault);
  final Database db;
  final CredentialVault vault;
  Future<void> _pending = Future.value();
  Future<JsonMap> _serial(Future<JsonMap> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<JsonMap> _execute(String operation, JsonMap input) =>
      _serial(() async {
        if (operation == 'list') {
          return {
            'names': [
              for (final row in await db.query('harness_secret_names',
                  columns: ['name'], orderBy: 'name'))
                row['name']
            ]
          };
        }
        final name = input['name'] as String;
        if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(name)) {
          throw const Failure(FailureCode.invalidInput,
              'Use letters, digits, dot, underscore or hyphen for a secret name.');
        }
        final ref = CredentialRef('harness_secrets', name);
        try {
          if (operation == 'set') {
            requireUserAuthorization(input);
            final value = input['value'] as String;
            SecretRedactor.remember(ref, value);
            await vault.write(ref, value);
            await db.insert(
                'harness_secret_names',
                {
                  'name': name,
                  'user_authorization':
                      SecretRedactor.text(input['userAuthorization'] as String),
                  'updated_at': DateTime.now().toUtc().toIso8601String()
                },
                conflictAlgorithm: ConflictAlgorithm.replace);
            return {'name': name, 'stored': true};
          }
          if (operation == 'remove') {
            await vault.delete(ref);
            await db.delete('harness_secret_names',
                where: 'name=?', whereArgs: [name]);
            return {'name': name, 'removed': true};
          }
          final value = await vault.read(ref);
          if (value == null) {
            throw const Failure(FailureCode.notFound, 'Secret does not exist.');
          }
          SecretRedactor.remember(ref, value);
          return {'name': name, 'value': value};
        } on Failure {
          rethrow;
        } catch (_) {
          // A backend exception may contain a value. Never pass it to Harness.
          throw const Failure(
              FailureCode.unavailable, 'Credential vault operation failed.');
        }
      });
  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'secrets.set',
                title: '保存脚本密钥',
                description:
                    '在现有保险库的 harness_secrets 命名空间存放密钥；userAuthorization 记录已有用户指令，值不写入数据库或审计。',
                effect: Effect.write,
                input: ObjectSchema({
                  'name': _name,
                  'value':
                      StringSchema(minLength: 1, maxLength: 4096, secret: true),
                  'userAuthorization': userAuthorizationSchema
                }, required: [
                  'name',
                  'value',
                  'userAuthorization'
                ]),
                output: ObjectSchema({'name': _name, 'stored': BooleanSchema()},
                    required: ['name', 'stored'])),
            (input, _) => _execute('set', input)),
        ClassicAction(
            const ActionSpec(
                id: 'secrets.get',
                title: '供脚本读取密钥',
                description: '仅返回脚本命名空间的密钥供进程内使用；输出敏感值从审计与回执脱敏，调用方不得打印、记忆或提交。',
                effect: Effect.read,
                input: ObjectSchema({'name': _name}, required: ['name']),
                output: ObjectSchema(
                    {'name': _name, 'value': StringSchema(secret: true)},
                    required: ['name', 'value'])),
            (input, _) => _execute('get', input)),
        ClassicAction(
            const ActionSpec(
                id: 'secrets.list',
                title: '列出脚本密钥名',
                description: '只列出名字，不读取或返回值。',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: ObjectSchema({'names': ArraySchema(_name)},
                    required: ['names'])),
            (input, _) => _execute('list', input)),
        ClassicAction(
            const ActionSpec(
                id: 'secrets.remove',
                title: '移除脚本密钥',
                description: '删除脚本命名空间中的指定密钥和名字记录。',
                effect: Effect.write,
                input: ObjectSchema({'name': _name}, required: ['name']),
                output: ObjectSchema(
                    {'name': _name, 'removed': BooleanSchema()},
                    required: ['name', 'removed'])),
            (input, _) => _execute('remove', input)),
      ];
}
