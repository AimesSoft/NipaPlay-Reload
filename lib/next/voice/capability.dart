import 'package:nipa_harness/nipa_harness.dart';
import '../capabilities/classic_action.dart';
import '../capabilities/user_authorization.dart';
import 'configuration.dart';
import 'model_store.dart';

final class VoiceCapability implements Capability {
  VoiceCapability(this.store);
  final VoiceModelStore store;
  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'voice.status',
                title: '查看语音输入配置与状态',
                effect: Effect.read,
                description:
                    '当前设备的语音输入服务、本机模型准备状态、凭据是否已配置、录音阶段、收到的音频字节数与最近错误。不含密钥、录音或转写文本。ready 表示配置就绪，不证明服务连通。手机输入设备与会话宿主可能不同，需查询实际输入设备。',
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) async {
          await store.load();
          return store.status;
        }),
        ClassicAction(
            const ActionSpec(
                id: 'voice.configure',
                title: '配置语音输入服务',
                effect: Effect.write,
                description:
                    '在实际输入设备上选择 local、Azure 快速转写（结束录音后出文字）或百炼 inference 实时转写。用户明确授权服务、地址和凭据使用后才可配置云端；音频直接发送给该服务，按服务商计费。密钥进入凭据库且不回传；留空保留同服务同地址的密钥，地址变化不复用密钥。clearCredential 删除所选服务地址的密钥。此操作停止当前录音，不打开麦克风、不自动发送文本，也不自动启用：settings.set labs.voiceEnabled 开关由用户决定。切换 local 保留下载的模型和云端凭据。',
                input: ObjectSchema({
                  'provider':
                      StringSchema(values: ['local', 'azure', 'dashscope']),
                  'endpoint': StringSchema(
                      description:
                          'Azure Speech HTTPS 资源地址，或百炼完整 WSS /api-ws/v1/inference 地址。不含 query。'),
                  'model': StringSchema(
                      description:
                          '百炼 inference 模型，默认 fun-asr-realtime；可选兼容的 Fun-ASR、Paraformer、Qwen-Audio-ASR 实时模型。Qwen3-ASR-Realtime 不支持。Azure 使用服务默认模型。'),
                  'language':
                      StringSchema(description: '留空自动识别；Azure 如 zh-CN，百炼如 zh。'),
                  'apiKey': StringSchema(secret: true),
                  'clearCredential': BooleanSchema(),
                  'userAuthorization': userAuthorizationSchema,
                }, required: [
                  'provider'
                ]),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, invocation) async {
          final config = VoiceConfiguration.fromJson(input);
          if (!config.local && invocation.origin != 'gui') {
            requireUserAuthorization(input);
          }
          await store.configure(config,
              apiKey: input['apiKey'] as String?,
              clearCredential: input['clearCredential'] == true);
          return store.status;
        }),
      ];
}
