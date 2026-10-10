import 'package:nipa_harness/nipa_harness.dart';
import 'platform_session.dart';

final class PlatformSessionCapability implements Capability {
  PlatformSessionCapability(PlatformSessions sessions)
      : actions = [
          _SessionAction(sessions, 'sessions.status', Effect.read),
          _SessionAction(sessions, 'sessions.logout', Effect.write),
          _SessionAction(sessions, 'ui.open_platform_login', Effect.write),
        ];
  @override
  final List<Action> actions;
}

final class _Data implements JsonEncodable {
  const _Data(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _SessionAction extends Action<_Data, _Data> {
  const _SessionAction(this.sessions, this.id, this.effect);
  final PlatformSessions sessions;
  final String id;
  final Effect effect;
  @override
  ActionSpec get spec => ActionSpec(
        id: id,
        title: id,
        description: switch (id) {
          'sessions.status' => '按平台查看本机会话状态和宿主引用；仅检查本地 cookie，'
              '不验证线上登录，不返回秘密。省略 platforms 时查询优酷与 B 站。',
          'sessions.logout' => '注销指定平台的本机会话并关闭该平台登录窗口；幂等。',
          _ => '在 NipaPlay 内置 WebView 中打开平台登录页。'
              '登录与密码输入只能由用户完成；打开页面不表示已登录。仅支持 macOS。',
        },
        effect: effect,
        input: id == 'ui.open_platform_login'
            ? const ObjectSchema({
                'platform': StringSchema(values: sessionPlatforms),
              }, required: [
                'platform'
              ])
            : ObjectSchema({
                'platforms':
                    const ArraySchema(StringSchema(values: sessionPlatforms)),
              }, required: id == 'sessions.logout' ? ['platforms'] : []),
        output: const ObjectSchema({
          'sessions': ArraySchema(ObjectSchema({
            'platform': StringSchema(values: sessionPlatforms),
            'supported': BooleanSchema(),
            'status': StringSchema(values: [
              'unsupported',
              'sessionPresent',
              'expiredOrRejected',
              'loggedOut',
              'unavailable'
            ]),
            'sessionAvailable': BooleanSchema(),
            'credentialRef': ObjectSchema({
              'namespace': StringSchema(),
              'key': StringSchema(),
            }, required: [
              'namespace',
              'key'
            ]),
            'accessRef': StringSchema(nullable: true),
            'loginHint': StringSchema(),
            'verification': StringSchema(values: ['localCookiesOnly']),
            'notice': StringSchema(nullable: true),
          }, required: [
            'platform',
            'supported',
            'status',
            'sessionAvailable',
            'credentialRef',
            'accessRef',
            'loginHint',
            'verification'
          ])),
          'opened': BooleanSchema(),
        }, required: [
          'sessions'
        ]),
      );
  @override
  _Data decodeInput(JsonMap json) => _Data(json);
  @override
  Future<Outcome<_Data>> run(_Data input, Invocation invocation) async {
    final platforms = id == 'ui.open_platform_login'
        ? [input.json['platform'] as String]
        : (input.json['platforms'] as List?)?.cast<String>() ??
            sessionPlatforms;
    if (platforms.isEmpty ||
        platforms.length > 2 ||
        platforms.toSet().length != platforms.length) {
      throw const Failure(FailureCode.invalidInput, '请选择 1–2 个不同的平台。');
    }
    for (final platform in platforms) {
      if (id == 'sessions.logout') await sessions.logout(platform);
      if (id == 'ui.open_platform_login') await sessions.openLogin(platform);
    }
    return Completed(_Data({
      'sessions': [for (final p in platforms) sessions.status(p)],
      if (id == 'ui.open_platform_login') 'opened': true,
    }));
  }
}
