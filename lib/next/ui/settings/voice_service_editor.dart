import 'package:flutter/widgets.dart';
import '../../voice/model_store.dart';
import '../shell/shell_controller.dart';
import '../data/gui_calls.dart' show rawFailureText;
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import 'controls.dart';

class VoiceServiceEditor extends StatefulWidget {
  const VoiceServiceEditor({super.key});
  @override
  State<VoiceServiceEditor> createState() => _VoiceServiceEditorState();
}

class _VoiceServiceEditorState extends State<VoiceServiceEditor> {
  final _store = VoiceModelStore.instance;
  String _provider = 'local',
      _endpoint = '',
      _model = 'fun-asr-realtime',
      _language = '',
      _key = '';
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _store.load().then((_) {
      if (!mounted) return;
      final config = _store.configuration;
      setState(() {
        _provider = config.provider;
        _endpoint = config.endpoint;
        _model = config.model;
        _language = config.language;
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _message = rawFailureText(e));
    });
  }

  Future<void> _save({bool clear = false}) async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await NextShellScope.of(context).services.calls.call('voice.configure', {
        'provider': _provider,
        'endpoint': _endpoint,
        'model': _model,
        'language': _language,
        if (_provider != 'local' && _key.isNotEmpty && !clear) 'apiKey': _key,
        if (clear) 'clearCredential': true,
      });
      if (mounted) {
        setState(() {
          _key = '';
          _message = clear ? '密钥已删除。' : '配置已保存。开启语音输入后，在对话框点击麦克风。';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = rawFailureText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('语音识别服务', style: NextText.sans(14)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 8, children: [
            for (final entry in const {
              'local': '本机离线',
              'azure': 'Azure',
              'dashscope': '百炼'
            }.entries)
              NextButton.ghost(
                  label: '${_provider == entry.key ? '✓ ' : ''}${entry.value}',
                  onTap: _saving
                      ? null
                      : () => setState(() {
                            if (_provider == entry.key) return;
                            _provider = entry.key;
                            _endpoint = '';
                            _key = '';
                            _language = '';
                            _message = null;
                            _model = 'fun-asr-realtime';
                          })),
          ]),
          const SizedBox(height: 12),
          Text(
              _provider == 'local'
                  ? '使用下方选择的本机模型，录音不上传。'
                  : _provider == 'azure'
                      ? 'Azure 快速转写：结束录音后上传并返回文字。填写支持该接口的 Azure Speech 资源地址。'
                      : '百炼实时转写：边说边返回文字。使用 Fun-ASR / Paraformer / Qwen-Audio-ASR 的 inference 接口。',
              style: NextText.sans(12, color: NextColors.p2)),
          if (_provider != 'local') ...[
            const SizedBox(height: 12),
            LiveTextField(
                value: _endpoint,
                label: '服务地址',
                width: null,
                hint: _provider == 'azure'
                    ? 'https://资源名.cognitiveservices.azure.com'
                    : 'wss://工作空间.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference',
                onChanged: (v) => _endpoint = v),
            const SizedBox(height: 8),
            if (_provider == 'dashscope') ...[
              LiveTextField(
                  value: _model,
                  label: '模型',
                  width: null,
                  onChanged: (v) => _model = v),
              const SizedBox(height: 8),
            ],
            LiveTextField(
                value: _language,
                label: '语言（可选）',
                width: null,
                hint: _provider == 'azure'
                    ? '留空自动识别，中文填写 zh-CN'
                    : '留空自动识别，中文填写 zh',
                onChanged: (v) => _language = v),
            const SizedBox(height: 8),
            LiveTextField(
                value: _key,
                label: 'API Key',
                width: null,
                obscure: true,
                hint: '留空保留同地址已存的密钥',
                onChanged: (v) => _key = v),
            const SizedBox(height: 10),
            Text(
                '保存后，点击麦克风会把录音直接交给所选服务商处理，并可能产生费用。密钥保存在系统凭据库。NipaPlay 不提供中转服务。',
                style: NextText.sans(12, color: NextColors.p2)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, children: [
            NextButton.ghost(
                label: _saving ? '正在保存…' : '保存语音配置',
                onTap: _saving ? null : _save),
            if (_provider != 'local')
              NextButton.ghost(
                  label: '删除此地址的密钥',
                  onTap: _saving ? null : () => _save(clear: true)),
          ]),
          if (_message != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_message!,
                    style: NextText.sans(12, color: NextColors.p2))),
          const SizedBox(height: 18),
        ],
      );
}
