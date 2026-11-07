import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import '../../security/credential_vault.dart';

/// A recording takes an immutable snapshot; changing settings affects the next one.
class VoiceConfiguration {
  const VoiceConfiguration(
      {this.provider = 'local',
      this.endpoint = '',
      this.model = 'fun-asr-realtime',
      this.language = ''});
  final String provider, endpoint, model, language;
  bool get local => provider == 'local';
  bool get streaming => provider != 'azure';
  CredentialRef get credential => CredentialRef(
      'voice', sha256.convert(utf8.encode('$provider\n$endpoint')).toString());
  String get label => switch (provider) {
        'azure' => 'Azure（结束录音后转写）',
        'dashscope' => '百炼实时转写',
        _ => '本机离线识别',
      };
  Map<String, Object?> toJson() => {
        'provider': provider,
        'endpoint': endpoint,
        'model': model,
        'language': language,
      };
  factory VoiceConfiguration.fromJson(Map<String, Object?> json) =>
      VoiceConfiguration(
        provider: json['provider'] as String? ?? 'local',
        endpoint: (json['endpoint'] as String? ?? '')
            .trim()
            .replaceFirst(RegExp(r'/+$'), ''),
        model: (json['model'] as String? ?? 'fun-asr-realtime').trim(),
        language: (json['language'] as String? ?? '').trim(),
      );
  void validate() {
    if (local) return;
    final uri = Uri.tryParse(endpoint);
    if (!['azure', 'dashscope'].contains(provider) ||
        uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.scheme != (provider == 'azure' ? 'https' : 'wss')) {
      throw const Failure(FailureCode.invalidInput,
          '云端语音地址必须是 Azure HTTPS 资源地址或百炼 WSS inference 地址，不含凭据、查询或片段。');
    }
    if (provider == 'dashscope' &&
        (!uri.path.endsWith('/api-ws/v1/inference') ||
            !RegExp(r'^(fun-asr|paraformer|qwen-audio-asr)').hasMatch(model))) {
      throw const Failure(FailureCode.invalidInput,
          '请选择百炼 inference 协议的 Fun-ASR、Paraformer 或 Qwen-Audio-ASR 实时模型；Qwen3-ASR-Realtime 使用另一种协议。');
    }
    if (provider == 'azure' &&
        uri.path.isNotEmpty &&
        uri.path != '/speechtotext/transcriptions:transcribe') {
      throw const Failure(FailureCode.invalidInput, 'Azure 请填写 Speech 资源地址。');
    }
  }
}
